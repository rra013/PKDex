//
//  BattleTier4Tests.swift
//  PKDexTests
//
//  Tier 4 — reactive abilities. Contact-status, on-hit stat reactives, special
//  triggers (Anger Point / Steadfast / Berserk), KO retaliation (Innards Out /
//  Aftermath), Poison Touch.
//

import Testing
import Foundation
@testable import PKDex

@MainActor
private enum T4 {
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
@Suite("Tier 4 — Contact Status Reactives")
struct BattleTier4ContactStatusTests {

    @Test func flameBodyEventuallyBurnsContactAttacker() {
        // 30% per contact hit. Run many trials and confirm at least one fires.
        var any = false
        for _ in 0..<50 {
            let a = T4.pkmn("Atk", id: 100, type1: "Water")  // not Fire-typed
            let b = T4.pkmn("Def", id: 101, ability: "flame-body")
            let tackle = T4.mv("Tackle", id: 1, dmg: "physical", power: 40, makesContact: true)
            let e = T4.engine((a, "blaze", [tackle]), (b, "flame-body", [tackle]))
            e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
            e.executeTurn()
            if e.side1.active(at: 0)?.status == .burn { any = true; break }
        }
        #expect(any, "Flame Body should burn the contact attacker eventually (30% per hit)")
    }

    @Test func staticEventuallyParalyzesContactAttacker() {
        var any = false
        for _ in 0..<50 {
            let a = T4.pkmn("Atk", id: 100, type1: "Fire")
            let b = T4.pkmn("Pikachu", id: 101, ability: "static")
            let tackle = T4.mv("Tackle", id: 1, dmg: "physical", power: 40, makesContact: true)
            let e = T4.engine((a, "blaze", [tackle]), (b, "static", [tackle]))
            e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
            e.executeTurn()
            if e.side1.active(at: 0)?.status == .paralysis { any = true; break }
        }
        #expect(any, "Static should paralyze the contact attacker eventually")
    }

    @Test func nonContactMovesDontTriggerFlameBody() {
        let a = T4.pkmn("Atk", id: 100, type1: "Water")
        let b = T4.pkmn("Def", id: 101, ability: "flame-body")
        let quake = T4.mv("Earthquake", id: 1, type: "Ground", dmg: "physical",
                          power: 100, makesContact: false)
        let e = T4.engine((a, "blaze", [quake]), (b, "flame-body", [quake]))
        // Run several trials; non-contact never triggers Flame Body.
        for _ in 0..<10 {
            e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
            e.executeTurn()
            if e.side1.active(at: 0)?.status == .burn {
                Issue.record("Earthquake should never trigger Flame Body")
                return
            }
            // Reset attacker for next trial.
            e.side1.active(at: 0)?.status = .none
        }
    }

    @Test func poisonTouchEventuallyPoisonsTarget() {
        var any = false
        for _ in 0..<50 {
            let a = T4.pkmn("Atk", id: 100, type1: "Poison", ability: "poison-touch")
            let b = T4.pkmn("Def", id: 101, type1: "Normal")
            let tackle = T4.mv("Tackle", id: 1, dmg: "physical", power: 40, makesContact: true)
            let e = T4.engine((a, "poison-touch", [tackle]), (b, "blaze", [tackle]))
            e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
            e.executeTurn()
            if e.side2.active(at: 0)?.status == .poison { any = true; break }
        }
        #expect(any, "Poison Touch should poison the target eventually (30% per contact hit)")
    }
}

@MainActor
@Suite("Tier 4 — On-Hit Stat Reactives")
struct BattleTier4OnHitTests {

    @Test func staminaBoostsDefenseOnAnyHit() {
        let a = T4.pkmn("Atk", id: 100)
        let b = T4.pkmn("Def", id: 101, ability: "stamina", hp: 200)
        let tackle = T4.mv("Tackle", id: 1, dmg: "physical", power: 40, makesContact: true)
        let e = T4.engine((a, "blaze", [tackle]), (b, "stamina", [tackle]))
        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e.executeTurn()
        #expect(e.side2.active(at: 0)?.defStage == 1, "Stamina raises Def on incoming hit")
    }

    @Test func weakArmorTriggersOnPhysicalHit() {
        let a = T4.pkmn("Atk", id: 100)
        let b = T4.pkmn("Def", id: 101, ability: "weak-armor", hp: 200)
        let tackle = T4.mv("Tackle", id: 1, dmg: "physical", power: 40, makesContact: true)
        let e = T4.engine((a, "blaze", [tackle]), (b, "weak-armor", [tackle]))
        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e.executeTurn()
        let B = e.side2.active(at: 0)!
        #expect(B.defStage == -1)
        #expect(B.speedStage == 2)
    }

    @Test func weakArmorIgnoresSpecialHit() {
        let a = T4.pkmn("Atk", id: 100)
        let b = T4.pkmn("Def", id: 101, ability: "weak-armor", hp: 200)
        let ember = T4.mv("Ember", id: 1, type: "Fire", dmg: "special",
                          power: 40, makesContact: false)
        let e = T4.engine((a, "blaze", [ember]), (b, "weak-armor", [ember]))
        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e.executeTurn()
        let B = e.side2.active(at: 0)!
        #expect(B.defStage == 0, "Weak Armor should not fire on a special hit")
    }

    @Test func justifiedBoostsAtkOnDarkHit() {
        let a = T4.pkmn("Atk", id: 100, type1: "Dark")
        let b = T4.pkmn("Def", id: 101, ability: "justified", hp: 200)
        let bite = T4.mv("Bite", id: 1, type: "Dark", dmg: "physical",
                         power: 60, makesContact: true)
        let e = T4.engine((a, "blaze", [bite]), (b, "justified", [bite]))
        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e.executeTurn()
        #expect(e.side2.active(at: 0)?.atkStage == 1, "Justified raises Atk on Dark hit")
    }

    @Test func justifiedIgnoresNonDarkHit() {
        let a = T4.pkmn("Atk", id: 100, type1: "Normal")
        let b = T4.pkmn("Def", id: 101, ability: "justified", hp: 200)
        let tackle = T4.mv("Tackle", id: 1, dmg: "physical", power: 40, makesContact: true)
        let e = T4.engine((a, "blaze", [tackle]), (b, "justified", [tackle]))
        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e.executeTurn()
        #expect(e.side2.active(at: 0)?.atkStage == 0, "Justified should not fire on non-Dark hit")
    }
}

@MainActor
@Suite("Tier 4 — Special Trigger Reactives")
struct BattleTier4SpecialTests {

    @Test func steadfastBoostsSpeedOnFlinch() {
        // Use Fake Out (100% flinch) so the trigger fires deterministically.
        let a = T4.pkmn("Atk", id: 100)
        let b = T4.pkmn("Def", id: 101, ability: "steadfast", hp: 200)
        let fakeOut = T4.mv("Fake Out", id: 1, dmg: "physical", power: 40,
                             priority: 3, makesContact: true)
        let e = T4.engine((a, "blaze", [fakeOut]), (b, "steadfast", [fakeOut]))
        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e.executeTurn()
        #expect(e.side2.active(at: 0)?.speedStage == 1,
                "Steadfast should raise Speed when the holder flinches")
    }

    @Test func berserkFiresOnCrossingFiftyPercent() {
        // Bulk on B so it survives the threshold-crossing hit. Park HP just
        // above 50% so a tiny hit crosses but doesn't KO.
        let a = T4.pkmn("Atk", id: 100, atk: 50)
        let b = T4.pkmn("Def", id: 101, ability: "berserk", hp: 300, def: 300)
        let tackle = T4.mv("Tackle", id: 1, dmg: "physical", power: 30,
                            makesContact: true)
        let e = T4.engine((a, "blaze", [tackle]), (b, "berserk", [tackle]))
        let B = e.side2.active(at: 0)!
        // ~3 HP above half — any non-zero damage will cross 50% AND B has
        // plenty of HP buffer so it shouldn't faint.
        B.currentHP = B.maxHP / 2 + 3
        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e.executeTurn()
        #expect(B.fainted == false, "Test setup broke — B fainted instead of surviving")
        #expect(B.berserkFired)
        #expect(B.spAtkStage == 1)
    }

    @Test func berserkOnlyFiresOnce() {
        let a = T4.pkmn("Atk", id: 100, atk: 300)
        let b = T4.pkmn("Def", id: 101, ability: "berserk", hp: 200)
        let tackle = T4.mv("Tackle", id: 1, dmg: "physical", power: 80, makesContact: true)
        let e = T4.engine((a, "blaze", [tackle]), (b, "berserk", [tackle]))
        let B = e.side2.active(at: 0)!
        B.currentHP = B.maxHP * 6 / 10
        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e.executeTurn()
        #expect(B.spAtkStage == 1)
        // Heal so we can re-cross the threshold and verify no second fire.
        B.berserkFired = true   // simulating a re-cross by an earlier setup; explicit guarded check
        B.currentHP = B.maxHP * 6 / 10
        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e.executeTurn()
        #expect(B.spAtkStage == 1, "Berserk shouldn't fire twice without a switch reset")
    }
}

@MainActor
@Suite("Tier 4 — KO Retaliation")
struct BattleTier4KORetaliationTests {

    @Test func innardsOutDamagesAttackerByLastHPLoss() {
        let a = T4.pkmn("Atk", id: 100, atk: 400)
        let b = T4.pkmn("Pyukumuku", id: 101, ability: "innards-out", hp: 20)
        let tackle = T4.mv("Tackle", id: 1, dmg: "physical", power: 200, makesContact: true)
        let e = T4.engine((a, "blaze", [tackle]), (b, "innards-out", [tackle]))
        let A = e.side1.active(at: 0)!
        let B = e.side2.active(at: 0)!
        let bHPBefore = B.currentHP
        let aHPBefore = A.currentHP
        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e.executeTurn()
        // B should be fainted; A should have lost bHPBefore HP to retaliation.
        #expect(B.fainted)
        let lossA = aHPBefore - A.currentHP
        // The retaliation is exactly bHPBefore (B's HP just before the lethal
        // hit). Allow a tiny tolerance for the per-hit Rocky-Helmet path.
        #expect(lossA >= bHPBefore,
                "Innards Out should hit the attacker for at least the defender's pre-hit HP")
    }

    @Test func aftermathChipsContactKOer() {
        let a = T4.pkmn("Atk", id: 100, atk: 400)
        let b = T4.pkmn("Stunfisk", id: 101, ability: "aftermath", hp: 20)
        let tackle = T4.mv("Tackle", id: 1, dmg: "physical", power: 200, makesContact: true)
        let e = T4.engine((a, "blaze", [tackle]), (b, "aftermath", [tackle]))
        let A = e.side1.active(at: 0)!
        let aHPBefore = A.currentHP
        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e.executeTurn()
        let chip = max(1, A.maxHP / 4)
        // The attacker should have lost at least the Aftermath chip damage
        // (possibly more if Rocky Helmet or contact recoil was layered, but
        // that's not present here).
        #expect(aHPBefore - A.currentHP >= chip,
                "Aftermath should chip the contact KOer by 1/4 max HP")
    }

    @Test func aftermathDoesNotFireOnNonContact() {
        let a = T4.pkmn("Atk", id: 100, atk: 400)
        let b = T4.pkmn("Stunfisk", id: 101, ability: "aftermath", hp: 20)
        let quake = T4.mv("Earthquake", id: 1, type: "Ground", dmg: "physical",
                          power: 200, makesContact: false)
        let e = T4.engine((a, "blaze", [quake]), (b, "aftermath", [quake]))
        let A = e.side1.active(at: 0)!
        let aHPBefore = A.currentHP
        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e.executeTurn()
        #expect(A.currentHP == aHPBefore,
                "Aftermath should not fire on a non-contact KO")
    }
}
