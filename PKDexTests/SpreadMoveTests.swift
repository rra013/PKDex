//
//  SpreadMoveTests.swift
//  PKDexTests
//
//  Spread moves in doubles:
//    * `SpreadMoves` reads targets from the Showdown data (the sim's old
//      hand-written list missed half of them and included Earth Power);
//    * the 0.75x reduction applies only when a move hits more than one
//      Pokemon at the time it's used;
//    * `allAdjacent` moves (Earthquake, Surf) also hit the user's ally;
//    * the calc's legacy engine applies the doubles toggle to spread moves only.
//
//  Battle runs pin rolls so damage comparisons
//  are exact.
//

import Testing
import Foundation
@testable import PKDex

@MainActor
private enum TS {
    static func pkmn(_ name: String, id: Int, type1: String = "Normal",
                     hp: Int = 200, def: Int = 100, spd: Int = 100) -> PKMNStats {
        PKMNStats(id: id, speciesID: id, name: name, type1: type1, type2: nil,
                  baseHP: hp, baseAtk: 100, baseDef: def, baseSpAtk: 100,
                  baseSpDef: spd, baseSpeed: 100, ability1: "blaze")
    }

    static func mv(_ name: String, id: Int, type: String, dmg: String,
                   power: Int, contact: Bool = false) -> MoveData {
        MoveData(id: id, name: name, type: type, damageClass: dmg, power: power,
                 accuracy: 100, pp: 16, priority: 0, minHits: nil, maxHits: nil,
                 drain: 0, healing: 0, critRate: 0, makesContact: contact)
    }

    static func slot(_ p: PKMNStats, _ moves: [MoveData]) -> TeamSlotInfo {
        TeamSlotInfo(spreadName: "t-\(p.id)", pokemonID: p.id, pokemonName: p.name,
                     type1: p.type1, type2: p.type2, abilityName: "blaze",
                     itemRawValue: nil, championsMode: false, natureID: "hardy",
                     level: 50, evHP: 0, evAtk: 0, evDef: 0, evSpAtk: 0, evSpDef: 0,
                     evSpeed: 0,
                     moveSlots: moves.map {
                         TeamMoveInfo(moveID: $0.id, moveName: $0.name, moveType: $0.type,
                                      damageClass: $0.damageClass, power: $0.power, isSTAB: false)
                     })
    }

    static func engine(_ format: BattleFormat, _ a: [(PKMNStats, [MoveData])],
                       _ b: [(PKMNStats, [MoveData])]) -> BattleEngine {
        let allP = a.map(\.0) + b.map(\.0)
        let allM = a.flatMap(\.1) + b.flatMap(\.1)
        let s1 = BattleSide(label: "Side 1", slots: a.map { slot($0.0, $0.1) },
                            format: format, allPokemon: allP, allMoves: allM)
        let s2 = BattleSide(label: "Side 2", slots: b.map { slot($0.0, $0.1) },
                            format: format, allPokemon: allP, allMoves: allM)
        let e = BattleEngine(format: format, side1: s1, side2: s2,
                             allPokemon: allP, allMoves: allM)
        e.rollOverride = .init(crit: false, roll: .max)
        return e
    }

    static func damageTaken(_ p: BattleParticipant) -> Int { p.maxHP - p.currentHP }
}

@Suite("Spread Moves — Targeting Data")
struct SpreadTargetingTests {
    @Test("Targets come from the move data", arguments: [
        ("Hyper Voice", MoveTargeting.allAdjacentFoes),
        ("Earthquake", .allAdjacent),
        ("Water Spout", .allAdjacentFoes),   // missing from the old sim list
        ("Make It Rain", .allAdjacentFoes),  // missing from the old sim list
        ("Earth Power", .single),            // wrongly on the old sim list
        ("Thunderbolt", .single),
        ("hyper-voice", .allAdjacentFoes),   // spelling-insensitive
        ("Glaciate", .allAdjacentFoes),      // fallback: not in Champions data
    ])
    func targeting(name: String, expected: MoveTargeting) {
        #expect(SpreadMoves.targeting(of: name) == expected)
    }
}

@MainActor
@Suite("Spread Moves — Battle Sim")
struct SpreadBattleTests {
    private static let voice = TS.mv("Hyper Voice", id: 1, type: "Normal", dmg: "special", power: 90)
    private static let quake = TS.mv("Earthquake", id: 2, type: "Ground", dmg: "physical", power: 100)

    /// Damage one foe takes from Hyper Voice in singles: the unreduced hit.
    private static func singlesDamage() -> Int {
        let e = TS.engine(.singles, [(TS.pkmn("A", id: 1), [Self.voice])],
                          [(TS.pkmn("F", id: 3), [])])
        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e.executeTurn()
        return TS.damageTaken(e.side2.active(at: 0)!)
    }

    @Test("Two foes: each takes the 0.75x spread hit")
    func twoFoesAreReduced() {
        let e = TS.engine(.doubles,
                          [(TS.pkmn("A", id: 1), [Self.voice]), (TS.pkmn("P", id: 2), [])],
                          [(TS.pkmn("F", id: 3), []), (TS.pkmn("G", id: 4), [])])
        e.setAction(side: 0, slot: 0, action: .spreadMove(moveIndex: 0))
        e.executeTurn()
        let full = Self.singlesDamage()
        for slot in 0..<2 {
            let taken = TS.damageTaken(e.side2.active(at: slot)!)
            #expect(taken < full, "slot \(slot): \(taken) vs unreduced \(full)")
            #expect(abs(Double(taken) - Double(full) * 0.75) <= 2)
        }
    }

    @Test("One foe left: a spread move does full damage")
    func loneFoeIsNotReduced() {
        let e = TS.engine(.doubles,
                          [(TS.pkmn("A", id: 1), [Self.voice]), (TS.pkmn("P", id: 2), [])],
                          [(TS.pkmn("F", id: 3), []), (TS.pkmn("G", id: 4), [])])
        let gone = e.side2.active(at: 1)!
        gone.currentHP = 0
        e.setAction(side: 0, slot: 0, action: .spreadMove(moveIndex: 0))
        e.executeTurn()
        #expect(TS.damageTaken(e.side2.active(at: 0)!) == Self.singlesDamage())
    }

    @Test("Earthquake also hits the user's ally")
    func earthquakeHitsAlly() {
        let e = TS.engine(.doubles,
                          [(TS.pkmn("A", id: 1), [Self.quake]), (TS.pkmn("P", id: 2), [])],
                          [(TS.pkmn("F", id: 3), []), (TS.pkmn("G", id: 4), [])])
        e.setAction(side: 0, slot: 0, action: .spreadMove(moveIndex: 0))
        e.executeTurn()
        #expect(TS.damageTaken(e.side1.active(at: 1)!) > 0, "ally should be hit")
        #expect(TS.damageTaken(e.side1.active(at: 0)!) == 0, "user isn't hit")
        #expect(TS.damageTaken(e.side2.active(at: 0)!) > 0)
    }

    @Test("Hyper Voice doesn't hit the ally")
    func foesOnlyMoveSparesAlly() {
        let e = TS.engine(.doubles,
                          [(TS.pkmn("A", id: 1), [Self.voice]), (TS.pkmn("P", id: 2), [])],
                          [(TS.pkmn("F", id: 3), []), (TS.pkmn("G", id: 4), [])])
        e.setAction(side: 0, slot: 0, action: .spreadMove(moveIndex: 0))
        e.executeTurn()
        #expect(TS.damageTaken(e.side1.active(at: 1)!) == 0)
    }
}

@Suite("Spread Moves — Calc Legacy Engine")
struct SpreadLegacyCalcTests {
    private static let side = CalcSnapshot(
        species: SpeciesSnapshot(name: "Test", type1: "Normal", type2: nil,
                                 baseHP: 100, baseAtk: 100, baseDef: 100,
                                 baseSpAtk: 100, baseSpDef: 100, baseSpeed: 100),
        megaForm: nil, nature: allNatures.first { $0.id == "serious" }!,
        level: 50, selectedAbility: nil, heldItem: .none, moves: [],
        championsMode: false)

    private static func damage(_ name: String, doubles: Bool) -> Double {
        var field = FieldSnapshot(); field.multi = doubles
        let move = MoveSnapshot(id: 1, name: name, type: "Normal",
                                damageClass: "special", power: 90, makesContact: false)
        return CalcEngine.evaluate(move: move, attacker: side, defender: side,
                                   field: field).damageMax
    }

    @Test("The doubles toggle reduces spread moves")
    func spreadIsReduced() {
        #expect(Self.damage("Hyper Voice", doubles: true) < Self.damage("Hyper Voice", doubles: false))
    }

    @Test("The doubles toggle leaves single-target moves alone")
    func singleTargetUnaffected() {
        #expect(Self.damage("Tri Attack", doubles: true) == Self.damage("Tri Attack", doubles: false))
    }
}
