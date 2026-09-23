//
//  BattleTier8Tests.swift
//  PKDexTests
//
//  Tier 8 — semi-invulnerable two-turn moves (Dig / Fly / Dive / Bounce /
//  Phantom Force / Shadow Force). Verify the charge invulnerability, the
//  hit-through exceptions (EQ on Dig, Surf on Dive, Gust on Fly), the 2×
//  damage on those, and Protect bypass for Phantom/Shadow Force.
//

import Testing
import Foundation
@testable import PKDex

@MainActor
private enum T8 {
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
                   power: Int? = 80, priority: Int = 0,
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
@Suite("Tier 8 — Charge → Release with Invulnerability")
struct BattleTier8ChargeReleaseTests {

    @Test func digChargesThenStrikesNextTurn() {
        // A digging defender goes underground for turn 1, then strikes turn 2.
        // The attacker is much slower so its hit always resolves second.
        let a = T8.pkmn("Atk", id: 100, hp: 300, spe: 30)
        let b = T8.pkmn("Diglett", id: 50, type1: "Ground", atk: 200, spe: 200)
        let dig = T8.mv("Dig", id: 1, type: "Ground", dmg: "physical",
                        power: 80, makesContact: true)
        let tackle = T8.mv("Tackle", id: 2, dmg: "physical", power: 40, makesContact: true)
        let e = T8.engine((a, "blaze", [tackle]), (b, "blaze", [dig]))
        let B = e.side2.active(at: 0)!
        // Turn 1 — B digs, A tackles into thin air.
        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e.setAction(side: 1, slot: 0, action: .move(moveIndex: 0, targetSide: 0, targetSlot: 0))
        e.executeTurn()
        #expect(B.chargedMoveKey == "dig", "Dig sets the charge state")
        #expect(B.currentHP == B.maxHP, "B should be untouchable underground")
        // Turn 2 — B strikes.
        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e.setAction(side: 1, slot: 0, action: .move(moveIndex: 0, targetSide: 0, targetSlot: 0))
        e.executeTurn()
        #expect(B.chargedMoveKey == nil, "Release clears the charge state")
    }

    @Test func tackleMissesAirborneFlyUser() {
        let a = T8.pkmn("Atk", id: 100, atk: 200, spe: 30)
        let b = T8.pkmn("Bird", id: 101, type1: "Flying", spe: 200)
        let fly = T8.mv("Fly", id: 1, type: "Flying", dmg: "physical", power: 90)
        let tackle = T8.mv("Tackle", id: 2, dmg: "physical", power: 40, makesContact: true)
        let e = T8.engine((a, "blaze", [tackle]), (b, "blaze", [fly]))
        let B = e.side2.active(at: 0)!
        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e.setAction(side: 1, slot: 0, action: .move(moveIndex: 0, targetSide: 0, targetSlot: 0))
        e.executeTurn()
        #expect(B.currentHP == B.maxHP, "Tackle should miss the airborne Fly user")
    }

    @Test func phantomForceVanishesAndBypassesProtect() {
        // Side 2 user vanishes. Side 1 uses Protect. On release turn the
        // Phantom Force should hit anyway.
        // Bracer is Psychic so the Ghost-typed Phantom Force isn't typeless-immune.
        let a = T8.pkmn("Bracer", id: 100, type1: "Psychic", hp: 300, spe: 30)
        let b = T8.pkmn("Ghost", id: 101, type1: "Ghost", atk: 200, spe: 200)
        let pf = T8.mv("Phantom Force", id: 1, type: "Ghost", dmg: "physical",
                        power: 90, makesContact: true)
        let protectM = T8.mv("Protect", id: 2, dmg: "status", power: nil, priority: 4)
        let e = T8.engine((a, "blaze", [protectM]), (b, "blaze", [pf]))
        let A = e.side1.active(at: 0)!
        // Turn 1: B charges Phantom Force; A queues Protect.
        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 0, targetSlot: 0))
        e.setAction(side: 1, slot: 0, action: .move(moveIndex: 0, targetSide: 0, targetSlot: 0))
        e.executeTurn()
        #expect(e.side2.active(at: 0)?.chargedMoveKey == "phantomforce")
        // Turn 2: A uses Protect; B releases Phantom Force — should hit through.
        let beforeHP = A.currentHP
        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 0, targetSlot: 0))
        e.setAction(side: 1, slot: 0, action: .move(moveIndex: 0, targetSide: 0, targetSlot: 0))
        e.executeTurn()
        #expect(A.currentHP < beforeHP, "Phantom Force should hit through Protect")
    }
}

@MainActor
@Suite("Tier 8 — Hit-Through Exceptions")
struct BattleTier8ExceptionTests {

    @Test func earthquakeHitsDiggingTargetForDoubleDamage() {
        // Compare EQ damage vs digging defender vs same EQ vs idle defender.
        // The digging one should take ~2× the idle damage.
        let a = T8.pkmn("Atk", id: 100, atk: 200, spe: 30)
        let bDig = T8.pkmn("Diglett", id: 50, type1: "Ground", hp: 400, spe: 200)
        let bIdle = T8.pkmn("Idle", id: 51, type1: "Ground", hp: 400, spe: 200)
        let dig = T8.mv("Dig", id: 1, type: "Ground", dmg: "physical", power: 80)
        let eq = T8.mv("Earthquake", id: 2, type: "Ground", dmg: "physical",
                       power: 100, makesContact: false)
        let splash = T8.mv("Splash", id: 3, dmg: "status", power: nil)
        let e1 = T8.engine((a, "blaze", [eq]), (bDig, "blaze", [dig]))
        let e2 = T8.engine((a, "blaze", [eq]), (bIdle, "blaze", [splash]))
        // Both engines: A uses EQ. B1 digs (then is hit underground), B2 splashes.
        e1.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e1.setAction(side: 1, slot: 0, action: .move(moveIndex: 0, targetSide: 0, targetSlot: 0))
        e1.executeTurn()
        e2.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e2.setAction(side: 1, slot: 0, action: .move(moveIndex: 0, targetSide: 0, targetSlot: 0))
        e2.executeTurn()
        let dmgDig = e1.side2.active(at: 0)!.maxHP - e1.side2.active(at: 0)!.currentHP
        let dmgIdle = e2.side2.active(at: 0)!.maxHP - e2.side2.active(at: 0)!.currentHP
        #expect(dmgDig > 0, "EQ should hit through Dig")
        #expect(dmgDig > Int(Double(dmgIdle) * 1.5),
                "EQ on a digging target should be ~2× damage (allow some variance)")
    }

    @Test func gustHitsFlyingTarget() {
        let a = T8.pkmn("Atk", id: 100, spa: 200, spe: 30)
        let b = T8.pkmn("Bird", id: 101, type1: "Flying", hp: 400, spe: 200)
        let fly = T8.mv("Fly", id: 1, type: "Flying", dmg: "physical", power: 90)
        let gust = T8.mv("Gust", id: 2, type: "Flying", dmg: "special",
                          power: 40, makesContact: false)
        let e = T8.engine((a, "blaze", [gust]), (b, "blaze", [fly]))
        let B = e.side2.active(at: 0)!
        let before = B.currentHP
        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e.setAction(side: 1, slot: 0, action: .move(moveIndex: 0, targetSide: 0, targetSlot: 0))
        e.executeTurn()
        #expect(B.currentHP < before, "Gust should hit an airborne target")
    }

    @Test func nothingHitsPhantomForceUser() {
        // Phantom Force is `.vanished` — no exceptions, nothing connects.
        let a = T8.pkmn("Atk", id: 100, atk: 200, spe: 30)
        let b = T8.pkmn("Ghost", id: 101, type1: "Ghost", spe: 200)
        let pf = T8.mv("Phantom Force", id: 1, type: "Ghost", dmg: "physical", power: 90)
        // Even Earthquake should miss a vanished mon.
        let eq = T8.mv("Earthquake", id: 2, type: "Ground", dmg: "physical",
                       power: 100, makesContact: false)
        let e = T8.engine((a, "blaze", [eq]), (b, "blaze", [pf]))
        let B = e.side2.active(at: 0)!
        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e.setAction(side: 1, slot: 0, action: .move(moveIndex: 0, targetSide: 0, targetSlot: 0))
        e.executeTurn()
        #expect(B.currentHP == B.maxHP, "Nothing should hit a vanished Phantom Force user")
    }
}
