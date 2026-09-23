//
//  BattleTier7Tests.swift
//  PKDexTests
//
//  Tier 7 — multi-turn charge moves. Solar Beam (sun bypass), Sky Attack,
//  Meteor Beam (charge +SpA), Electro Shot (rain bypass), Skull Bash
//  (charge +Def), Geomancy (status release +2 SpA/SpD/Spe).
//

import Testing
import Foundation
@testable import PKDex

@MainActor
private enum T7 {
    static func pkmn(_ name: String, id: Int = 1,
                     type1: String = "Normal", type2: String? = nil,
                     ability: String = "blaze",
                     hp: Int = 100, atk: Int = 100, def: Int = 100,
                     spa: Int = 100, spd: Int = 100, spe: Int = 100) -> PKMNStats {
        PKMNStats(id: id, speciesID: id, name: name,
                  type1: type1, type2: type2,
                  baseHP: hp, baseAtk: atk, baseDef: def,
                  baseSpAtk: spa, baseSpDef: spd, baseSpeed: spe,
                  ability1: ability)
    }

    static func mv(_ name: String, id: Int,
                   type: String = "Normal", dmg: String = "physical",
                   power: Int? = 60, priority: Int = 0,
                   makesContact: Bool = true) -> MoveData {
        MoveData(id: id, name: name, type: type, damageClass: dmg,
                 power: power, accuracy: 100, pp: 16, priority: priority,
                 minHits: nil, maxHits: nil, drain: 0, healing: 0,
                 critRate: 0, makesContact: makesContact)
    }

    static func slot(_ p: PKMNStats, ability: String, moves: [MoveData]) -> TeamSlotInfo {
        TeamSlotInfo(
            spreadName: "fx-\(p.name)",
            pokemonID: p.id, pokemonName: p.name,
            type1: p.type1, type2: p.type2,
            abilityName: ability, itemRawValue: nil,
            championsMode: false, natureID: "hardy", level: 50,
            evHP: 0, evAtk: 0, evDef: 0, evSpAtk: 0, evSpDef: 0, evSpeed: 0,
            moveSlots: moves.map {
                TeamMoveInfo(moveID: $0.id, moveName: $0.name, moveType: $0.type,
                             damageClass: $0.damageClass, power: $0.power, isSTAB: false)
            }
        )
    }

    static func engine(_ a: (PKMNStats, String, [MoveData]),
                       _ b: (PKMNStats, String, [MoveData])) -> BattleEngine {
        let sA = slot(a.0, ability: a.1, moves: a.2)
        let sB = slot(b.0, ability: b.1, moves: b.2)
        let allP = [a.0, b.0]
        let allM = a.2 + b.2
        let bs1 = BattleSide(label: "Side 1", slots: [sA], format: .singles,
                             allPokemon: allP, allMoves: allM)
        let bs2 = BattleSide(label: "Side 2", slots: [sB], format: .singles,
                             allPokemon: allP, allMoves: allM)
        return BattleEngine(format: .singles, side1: bs1, side2: bs2,
                            allPokemon: allP, allMoves: allM)
    }
}

@MainActor
@Suite("Tier 7 — Charge Turn vs Release Turn")
struct BattleTier7ChargeReleaseTests {

    @Test func solarBeamChargesThenReleases() {
        let a = T7.pkmn("MonA", id: 100, spa: 200)
        let b = T7.pkmn("MonB", id: 101, hp: 400)
        let sb = T7.mv("Solar Beam", id: 1, type: "Grass", dmg: "special",
                       power: 120, makesContact: false)
        let e = T7.engine((a, "blaze", [sb]), (b, "blaze", [sb]))
        let A = e.side1.active(at: 0)!
        let B = e.side2.active(at: 0)!
        let bBefore = B.currentHP
        // Turn 1 — charge.
        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e.executeTurn()
        #expect(A.chargedMoveKey == "solarbeam")
        #expect(B.currentHP == bBefore, "Charge turn should deal no damage")
        // Turn 2 — release.
        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e.executeTurn()
        #expect(A.chargedMoveKey == nil, "Release should clear the charge flag")
        #expect(B.currentHP < bBefore, "Release turn should deal damage")
    }

    @Test func solarBeamSkipsChargeInSun() {
        let a = T7.pkmn("MonA", id: 100, spa: 200)
        let b = T7.pkmn("MonB", id: 101, hp: 400)
        let sb = T7.mv("Solar Beam", id: 1, type: "Grass", dmg: "special",
                       power: 120, makesContact: false)
        let e = T7.engine((a, "blaze", [sb]), (b, "blaze", [sb]))
        e.weather = .sun
        e.weatherTurns = 5
        let A = e.side1.active(at: 0)!
        let B = e.side2.active(at: 0)!
        let bBefore = B.currentHP
        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e.executeTurn()
        #expect(A.chargedMoveKey == nil, "Sun should skip the charge state")
        #expect(B.currentHP < bBefore, "Sun-Solar-Beam should hit in one turn")
    }

    @Test func electroShotSkipsChargeInRain() {
        let a = T7.pkmn("MonA", id: 100, spa: 200)
        let b = T7.pkmn("MonB", id: 101, hp: 400)
        let es = T7.mv("Electro Shot", id: 1, type: "Electric", dmg: "special",
                        power: 130, makesContact: false)
        let e = T7.engine((a, "blaze", [es]), (b, "blaze", [es]))
        e.weather = .rain
        e.weatherTurns = 5
        let A = e.side1.active(at: 0)!
        let B = e.side2.active(at: 0)!
        let bBefore = B.currentHP
        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e.executeTurn()
        #expect(A.chargedMoveKey == nil)
        #expect(B.currentHP < bBefore)
    }
}

@MainActor
@Suite("Tier 7 — Charge-Turn Self Boosts")
struct BattleTier7ChargeBoostsTests {

    @Test func meteorBeamBoostsSpAOnCharge() {
        let a = T7.pkmn("MonA", id: 100, spa: 200)
        let b = T7.pkmn("MonB", id: 101, hp: 400)
        let mb = T7.mv("Meteor Beam", id: 1, type: "Rock", dmg: "special",
                        power: 120, makesContact: false)
        let e = T7.engine((a, "blaze", [mb]), (b, "blaze", [mb]))
        let A = e.side1.active(at: 0)!
        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e.executeTurn()
        #expect(A.spAtkStage == 1, "Meteor Beam should boost SpA during the charge turn")
        #expect(A.chargedMoveKey == "meteorbeam")
    }

    @Test func skullBashBoostsDefOnCharge() {
        let a = T7.pkmn("MonA", id: 100)
        let b = T7.pkmn("MonB", id: 101, hp: 400)
        let sb = T7.mv("Skull Bash", id: 1, dmg: "physical", power: 130, makesContact: true)
        let e = T7.engine((a, "blaze", [sb]), (b, "blaze", [sb]))
        let A = e.side1.active(at: 0)!
        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e.executeTurn()
        #expect(A.defStage == 1, "Skull Bash should raise Def on the charge turn")
        #expect(A.chargedMoveKey == "skullbash")
    }
}

@MainActor
@Suite("Tier 7 — Geomancy")
struct BattleTier7GeomancyTests {

    @Test func geomancyReleaseBoostsThreeStats() {
        let a = T7.pkmn("Xerneas", id: 716, type1: "Fairy")
        let b = T7.pkmn("MonB", id: 101)
        let gm = T7.mv("Geomancy", id: 1, type: "Fairy", dmg: "status",
                        power: nil, makesContact: false)
        let e = T7.engine((a, "blaze", [gm]), (b, "blaze", [gm]))
        let A = e.side1.active(at: 0)!
        // Turn 1 — charge.
        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 0, targetSlot: 0))
        e.executeTurn()
        #expect(A.chargedMoveKey == "geomancy")
        #expect(A.spAtkStage == 0, "Boosts shouldn't land until the release turn")
        // Turn 2 — release.
        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 0, targetSlot: 0))
        e.executeTurn()
        #expect(A.chargedMoveKey == nil)
        #expect(A.spAtkStage == 2)
        #expect(A.spDefStage == 2)
        #expect(A.speedStage == 2)
    }
}

@MainActor
@Suite("Tier 7 — Charge Lock & Switch Reset")
struct BattleTier7LockTests {

    @Test func chargingLocksUserIntoTheChargedMove() {
        // Even if the user queues a different move on turn 2, the engine
        // should force the release of the charged one.
        let a = T7.pkmn("MonA", id: 100, spa: 200)
        let b = T7.pkmn("MonB", id: 101, hp: 400)
        let sb = T7.mv("Solar Beam", id: 1, type: "Grass", dmg: "special", power: 120)
        let tackle = T7.mv("Tackle", id: 2, dmg: "physical", power: 40, makesContact: true)
        let e = T7.engine((a, "blaze", [sb, tackle]), (b, "blaze", [sb]))
        let A = e.side1.active(at: 0)!
        // Turn 1 — Solar Beam charge.
        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e.executeTurn()
        #expect(A.chargedMoveKey == "solarbeam")
        // Turn 2 — pick Tackle (idx 1) — should be overridden back to Solar Beam.
        let logBefore = e.log.count
        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 1, targetSide: 1, targetSlot: 0))
        e.executeTurn()
        let lines = e.log[logBefore...].map(\.text)
        #expect(lines.contains(where: { $0.contains("used Solar Beam") }),
                "Charged user should release Solar Beam regardless of queue")
        #expect(!lines.contains(where: { $0.contains("used Tackle") }))
    }

    @Test func switchingClearsCharge() {
        let a = T7.pkmn("MonA", id: 100, spa: 200)
        let bench = T7.pkmn("Bench", id: 102)
        let b = T7.pkmn("MonB", id: 101)
        let sb = T7.mv("Solar Beam", id: 1, type: "Grass", dmg: "special", power: 120)
        let aSlot = T7.slot(a, ability: "blaze", moves: [sb])
        let benchSlot = T7.slot(bench, ability: "blaze", moves: [])
        let bSlot = T7.slot(b, ability: "blaze", moves: [])
        let allP = [a, bench, b]
        let bs1 = BattleSide(label: "Side 1", slots: [aSlot, benchSlot], format: .singles,
                             allPokemon: allP, allMoves: [sb])
        let bs2 = BattleSide(label: "Side 2", slots: [bSlot], format: .singles,
                             allPokemon: allP, allMoves: [sb])
        let e = BattleEngine(format: .singles, side1: bs1, side2: bs2,
                             allPokemon: allP, allMoves: [sb])
        let A = e.side1.participants[0]
        // Charge.
        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e.executeTurn()
        #expect(A.chargedMoveKey == "solarbeam")
        // Switch out — charge state should reset.
        e.setAction(side: 0, slot: 0, action: .switchTo(benchIndex: 1))
        e.executeTurn()
        #expect(A.chargedMoveKey == nil)
        #expect(A.chargedMoveIndex == nil)
    }
}
