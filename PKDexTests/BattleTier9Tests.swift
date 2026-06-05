//
//  BattleTier9Tests.swift
//  PKDexTests
//
//  Tier 9 — weight-based power moves (Heavy Slam, Heat Crash, Low Kick,
//  Grass Knot), Sky Drop charge invulnerability, Ice Face block + snow restore.
//

import Testing
import Foundation
@testable import PKDex

@MainActor
private enum T9 {
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
@Suite("Tier 9 — Weight Tables & Pure Functions")
struct BattleTier9WeightTableTests {

    @Test func heavySlamPowerBands() {
        // Heaviest attacker (e.g. Metagross 550 kg) vs Mimikyu 1 kg → ratio
        // tiny → 120 power.
        let p1 = BattleMoveEffects.heavySlamPower(attackerWeight: 550, defenderWeight: 1)
        #expect(p1 == 120)
        // 100/50 = 0.5 → 60 power
        let p2 = BattleMoveEffects.heavySlamPower(attackerWeight: 100, defenderWeight: 50)
        #expect(p2 == 60)
        // 100/80 = 0.8 → 40 power (default)
        let p3 = BattleMoveEffects.heavySlamPower(attackerWeight: 100, defenderWeight: 80)
        #expect(p3 == 40)
        // 100/25 = 0.25 → 100 power (matches the 0.25 cap exactly)
        let p4 = BattleMoveEffects.heavySlamPower(attackerWeight: 100, defenderWeight: 25)
        #expect(p4 == 100)
    }

    @Test func weightPowerBands() {
        #expect(BattleMoveEffects.weightPower(defenderWeight: 5)   == 20)
        #expect(BattleMoveEffects.weightPower(defenderWeight: 20)  == 40)
        #expect(BattleMoveEffects.weightPower(defenderWeight: 40)  == 60)
        #expect(BattleMoveEffects.weightPower(defenderWeight: 80)  == 80)
        #expect(BattleMoveEffects.weightPower(defenderWeight: 150) == 100)
        #expect(BattleMoveEffects.weightPower(defenderWeight: 300) == 120)
    }

    @Test func weightForSpeciesFallsBackToFifty() {
        #expect(BattleMoveEffects.weightForSpecies("DefinitelyNotAPokemon") == 50)
        #expect(BattleMoveEffects.weightForSpecies("Snorlax") == 460)
        #expect(BattleMoveEffects.weightForSpecies("Mimikyu") == 1)
    }
}

@MainActor
@Suite("Tier 9 — Heavy Slam vs Low Kick in Battle")
struct BattleTier9WeightedDamageTests {

    @Test func heavySlamHitsHarderAgainstLightTarget() {
        // Compare Heavy Slam dmg from Metagross vs (heavy) Tyranitar to
        // Metagross vs (light) Mimikyu. The light target should take more.
        let mg = T9.pkmn("Metagross", id: 376, type1: "Steel", atk: 100)
        // Both targets carry huge HP so neither gets capped — the test is
        // looking at the *ratio*, not absolute damage.
        let tyr = T9.pkmn("Tyranitar", id: 248, type1: "Rock", hp: 600, def: 100)
        let mk = T9.pkmn("Mimikyu", id: 778, type1: "Ghost", type2: "Fairy",
                         hp: 600, def: 100)
        let hs = T9.mv("Heavy Slam", id: 1, type: "Steel", dmg: "physical",
                        power: 1, makesContact: true)
        let e1 = T9.engine((mg, "blaze", [hs]), (tyr, "blaze", [hs]))
        let e2 = T9.engine((mg, "blaze", [hs]), (mk, "blaze", [hs]))
        e1.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e2.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e1.executeTurn()
        e2.executeTurn()
        let dmgTyr = e1.side2.active(at: 0)!.maxHP - e1.side2.active(at: 0)!.currentHP
        let dmgMk = e2.side2.active(at: 0)!.maxHP - e2.side2.active(at: 0)!.currentHP
        #expect(dmgMk > dmgTyr,
                "Heavy Slam vs a 1kg Mimikyu should hit harder than vs a 202kg Tyranitar")
    }

    @Test func lowKickScalesWithDefenderWeight() {
        let atk = T9.pkmn("Atk", id: 100, atk: 200)
        let tiny = T9.pkmn("Wisp", id: 50, hp: 300)      // unknown → 50 kg → 60 BP
        let huge = T9.pkmn("Snorlax", id: 143, hp: 300)  // 460 kg → 120 BP
        let lk = T9.mv("Low Kick", id: 1, type: "Fighting", dmg: "physical",
                        power: 1, makesContact: true)
        let e1 = T9.engine((atk, "blaze", [lk]), (tiny, "blaze", [lk]))
        let e2 = T9.engine((atk, "blaze", [lk]), (huge, "blaze", [lk]))
        e1.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e2.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e1.executeTurn()
        e2.executeTurn()
        let dmgTiny = e1.side2.active(at: 0)!.maxHP - e1.side2.active(at: 0)!.currentHP
        let dmgHuge = e2.side2.active(at: 0)!.maxHP - e2.side2.active(at: 0)!.currentHP
        #expect(dmgHuge > dmgTiny,
                "Low Kick on Snorlax should hit harder than on a default-weight target")
    }
}

@MainActor
@Suite("Tier 9 — Sky Drop & Ice Face")
struct BattleTier9MiscTests {

    @Test func skyDropChargeUserIsAirborne() {
        // Sky Drop user is invulnerable during the charge, like Fly. Tackle
        // misses; Gust hits.
        let a = T9.pkmn("Atk", id: 100, atk: 200, spa: 200, spe: 30)
        let b = T9.pkmn("Bird", id: 101, type1: "Flying", spe: 200)
        let sd = T9.mv("Sky Drop", id: 1, type: "Flying", dmg: "physical", power: 60)
        let tackle = T9.mv("Tackle", id: 2, dmg: "physical", power: 40, makesContact: true)
        let e = T9.engine((a, "blaze", [tackle]), (b, "blaze", [sd]))
        let B = e.side2.active(at: 0)!
        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e.setAction(side: 1, slot: 0, action: .move(moveIndex: 0, targetSide: 0, targetSlot: 0))
        e.executeTurn()
        #expect(B.chargedMoveKey == "skydrop")
        #expect(B.currentHP == B.maxHP, "Sky Drop user should be airborne / untouchable to Tackle")
    }

    @Test func iceFaceBlocksFirstPhysicalHit() {
        let a = T9.pkmn("Atk", id: 100, atk: 300)
        let b = T9.pkmn("Eiscue", id: 875, type1: "Ice",
                        ability: "ice-face", hp: 300)
        let tackle = T9.mv("Tackle", id: 1, dmg: "physical", power: 100, makesContact: true)
        let e = T9.engine((a, "blaze", [tackle]), (b, "ice-face", [tackle]))
        let B = e.side2.active(at: 0)!
        #expect(B.iceFaceIntact, "Eiscue should enter with Ice Face intact")
        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e.executeTurn()
        #expect(B.currentHP == B.maxHP, "Ice Face should fully block the first physical hit")
        #expect(B.iceFaceIntact == false, "Ice Face should bust after the first physical hit")
    }

    @Test func iceFaceLetsSpecialHitsThrough() {
        let a = T9.pkmn("Atk", id: 100, spa: 200)
        let b = T9.pkmn("Eiscue", id: 875, type1: "Ice",
                        ability: "ice-face", hp: 300)
        let ember = T9.mv("Ember", id: 1, type: "Fire", dmg: "special",
                           power: 80, makesContact: false)
        let e = T9.engine((a, "blaze", [ember]), (b, "ice-face", [ember]))
        let B = e.side2.active(at: 0)!
        let before = B.currentHP
        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e.executeTurn()
        #expect(B.currentHP < before, "Special hits should pass through Ice Face")
        #expect(B.iceFaceIntact, "Ice Face only busts on physical hits")
    }

    @Test func iceFaceRestoresOnSnow() {
        let a = T9.pkmn("Atk", id: 100, atk: 300)
        let b = T9.pkmn("Eiscue", id: 875, type1: "Ice",
                        ability: "ice-face", hp: 300)
        let tackle = T9.mv("Tackle", id: 1, dmg: "physical", power: 100, makesContact: true)
        let snow = T9.mv("Snowscape", id: 2, type: "Ice", dmg: "status")
        let e = T9.engine((a, "blaze", [tackle, snow]), (b, "ice-face", [tackle]))
        let B = e.side2.active(at: 0)!
        // Bust Ice Face with a tackle.
        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e.executeTurn()
        #expect(B.iceFaceIntact == false)
        // Set snow weather — the EOT shouldn't matter; setWeather restores.
        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 1, targetSide: 0, targetSlot: 0))
        e.executeTurn()
        #expect(B.iceFaceIntact, "Snow should restore Ice Face on the Eiscue")
    }
}
