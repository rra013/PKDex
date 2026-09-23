//
//  BattleTier2Tests.swift
//  PKDexTests
//
//  Coverage for the Tier 2 secondary-effect dictionary additions and the new
//  fields added to `SecondaryEffect` (selfBoosts, setsHazardOnFoe,
//  groundsTarget, curesTargetBurn, saltCureVolatile, requiresTargetBoost).
//

import Testing
import Foundation
@testable import PKDex

@MainActor
private enum T2 {
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
                   power: Int? = 50, priority: Int = 0,
                   makesContact: Bool = false) -> MoveData {
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

// MARK: - Pure dictionary additions

@MainActor
@Suite("Tier 2 — Secondary Effect Dictionary")
struct BattleTier2SecondaryEffectsTests {

    @Test func nuzzleAlwaysParalyzes() {
        let a = T2.pkmn("Pichu", id: 172, type1: "Electric")
        let b = T2.pkmn("Bulba", id: 1, type1: "Grass")
        let nuz = T2.mv("Nuzzle", id: 1, type: "Electric", dmg: "physical",
                        power: 20, makesContact: true)
        let e = T2.engine((a, "blaze", [nuz]), (b, "blaze", [nuz]))
        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e.executeTurn()
        let s = e.side2.active(at: 0)?.status ?? .none
        #expect(s == .paralysis, "Nuzzle is 100% paralysis on hit")
    }

    @Test func mysticalFireDropsTargetSpA() {
        let a = T2.pkmn("Delphox", id: 655, type1: "Fire")
        let b = T2.pkmn("Bulba", id: 1, type1: "Grass")
        let mf = T2.mv("Mystical Fire", id: 1, type: "Fire", dmg: "special", power: 75)
        let e = T2.engine((a, "blaze", [mf]), (b, "blaze", [mf]))
        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e.executeTurn()
        #expect(e.side2.active(at: 0)?.spAtkStage == -1,
                "Mystical Fire is 100% -1 SpA")
    }

    @Test func luminaCrashDropsTargetSpDByTwo() {
        let a = T2.pkmn("MonA", id: 100)
        let b = T2.pkmn("MonB", id: 101)
        let lc = T2.mv("Lumina Crash", id: 1, type: "Psychic", dmg: "special", power: 80)
        let e = T2.engine((a, "blaze", [lc]), (b, "blaze", [lc]))
        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e.executeTurn()
        #expect(e.side2.active(at: 0)?.spDefStage == -2,
                "Lumina Crash drops target SpD by 2")
    }

    @Test func icyWindDropsTargetSpeed() {
        let a = T2.pkmn("MonA", id: 100)
        let b = T2.pkmn("MonB", id: 101)
        let iw = T2.mv("Icy Wind", id: 1, type: "Ice", dmg: "special", power: 55)
        let e = T2.engine((a, "blaze", [iw]), (b, "blaze", [iw]))
        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e.executeTurn()
        #expect(e.side2.active(at: 0)?.speedStage == -1,
                "Icy Wind drops target Speed")
    }

    @Test func chargeBeamUsuallyBoostsSpA() {
        // Chance: 70%. Run several rolls and verify it boosted at least once.
        var any = false
        for _ in 0..<25 {
            let a = T2.pkmn("MonA", id: 100)
            let b = T2.pkmn("MonB", id: 101)
            let cb = T2.mv("Charge Beam", id: 1, type: "Electric", dmg: "special", power: 50)
            let e = T2.engine((a, "blaze", [cb]), (b, "blaze", [cb]))
            e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
            e.executeTurn()
            if e.side1.active(at: 0)?.spAtkStage == 1 { any = true; break }
        }
        #expect(any, "Charge Beam should boost SpA at least once across 25 rolls (70% each)")
    }

    @Test func powerUpPunchAlwaysBoostsAtk() {
        let a = T2.pkmn("MonA", id: 100)
        let b = T2.pkmn("MonB", id: 101)
        let pup = T2.mv("Power-Up Punch", id: 1, type: "Fighting", dmg: "physical",
                        power: 40, makesContact: true)
        let e = T2.engine((a, "blaze", [pup]), (b, "blaze", [pup]))
        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e.executeTurn()
        #expect(e.side1.active(at: 0)?.atkStage == 1,
                "Power-Up Punch is 100% +1 Atk on the attacker")
    }

    @Test func flameChargeAlwaysBoostsSpeed() {
        let a = T2.pkmn("MonA", id: 100)
        let b = T2.pkmn("MonB", id: 101)
        let fc = T2.mv("Flame Charge", id: 1, type: "Fire", dmg: "physical",
                       power: 50, makesContact: true)
        let e = T2.engine((a, "blaze", [fc]), (b, "blaze", [fc]))
        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e.executeTurn()
        #expect(e.side1.active(at: 0)?.speedStage == 1)
    }
}

// MARK: - StatChanges dictionary additions

@MainActor
@Suite("Tier 2 — StatChanges Additions")
struct BattleTier2StatChangesTests {

    @Test func featherDanceDropsTargetAtkByTwo() {
        let a = T2.pkmn("MonA", id: 100)
        let b = T2.pkmn("MonB", id: 101)
        let fd = T2.mv("Feather Dance", id: 1, dmg: "status", power: nil)
        let e = T2.engine((a, "blaze", [fd]), (b, "blaze", [fd]))
        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e.executeTurn()
        #expect(e.side2.active(at: 0)?.atkStage == -2)
    }

    @Test func eerieImpulseDropsTargetSpAByTwo() {
        let a = T2.pkmn("MonA", id: 100)
        let b = T2.pkmn("MonB", id: 101)
        let ei = T2.mv("Eerie Impulse", id: 1, dmg: "status", power: nil)
        let e = T2.engine((a, "blaze", [ei]), (b, "blaze", [ei]))
        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e.executeTurn()
        #expect(e.side2.active(at: 0)?.spAtkStage == -2)
    }

    @Test func tickleDropsTargetAtkAndDef() {
        let a = T2.pkmn("MonA", id: 100)
        let b = T2.pkmn("MonB", id: 101)
        let tk = T2.mv("Tickle", id: 1, dmg: "status", power: nil)
        let e = T2.engine((a, "blaze", [tk]), (b, "blaze", [tk]))
        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e.executeTurn()
        #expect(e.side2.active(at: 0)?.atkStage == -1)
        #expect(e.side2.active(at: 0)?.defStage == -1)
    }

    @Test func scaryFaceDropsTargetSpeedByTwo() {
        let a = T2.pkmn("MonA", id: 100)
        let b = T2.pkmn("MonB", id: 101)
        let sf = T2.mv("Scary Face", id: 1, dmg: "status", power: nil)
        let e = T2.engine((a, "blaze", [sf]), (b, "blaze", [sf]))
        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e.executeTurn()
        #expect(e.side2.active(at: 0)?.speedStage == -2)
    }

    @Test func growthBoostsAtkAndSpA() {
        let a = T2.pkmn("MonA", id: 100)
        let b = T2.pkmn("MonB", id: 101)
        let gr = T2.mv("Growth", id: 1, dmg: "status", power: nil)
        let e = T2.engine((a, "blaze", [gr]), (b, "blaze", [gr]))
        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 0, targetSlot: 0))
        e.executeTurn()
        #expect(e.side1.active(at: 0)?.atkStage == 1)
        #expect(e.side1.active(at: 0)?.spAtkStage == 1)
    }

    @Test func victoryDanceBoostsAtkDefSpeed() {
        let a = T2.pkmn("MonA", id: 100)
        let b = T2.pkmn("MonB", id: 101)
        let vd = T2.mv("Victory Dance", id: 1, dmg: "status", power: nil)
        let e = T2.engine((a, "blaze", [vd]), (b, "blaze", [vd]))
        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 0, targetSlot: 0))
        e.executeTurn()
        let p = e.side1.active(at: 0)!
        #expect(p.atkStage == 1)
        #expect(p.defStage == 1)
        #expect(p.speedStage == 1)
    }
}

// MARK: - Extended secondary effect fields

@MainActor
@Suite("Tier 2 — Extended Secondary Fields")
struct BattleTier2ExtendedTests {

    @Test func stoneAxeSetsSpikesOnFoeSide() {
        let a = T2.pkmn("MonA", id: 100, type1: "Rock")
        let b = T2.pkmn("MonB", id: 101)
        let sa = T2.mv("Stone Axe", id: 1, type: "Rock", dmg: "physical",
                       power: 65, makesContact: true)
        let e = T2.engine((a, "blaze", [sa]), (b, "blaze", [sa]))
        #expect(e.side2.spikesLayers == 0)
        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e.executeTurn()
        #expect(e.side2.spikesLayers == 1, "Stone Axe sets Spikes on the foe's side")
    }

    @Test func smackDownGroundsFlyingTarget() {
        let a = T2.pkmn("MonA", id: 100)
        let b = T2.pkmn("Flier", id: 101, type1: "Flying")
        let sd = T2.mv("Smack Down", id: 1, type: "Rock", dmg: "physical", power: 50)
        let e = T2.engine((a, "blaze", [sd]), (b, "blaze", [sd]))
        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e.executeTurn()
        #expect(e.side2.active(at: 0)?.grounded == true)
    }

    @Test func sparklingAriaCuresBurn() {
        let a = T2.pkmn("MonA", id: 100, type1: "Water")
        let b = T2.pkmn("MonB", id: 101, type1: "Grass")
        let sa = T2.mv("Sparkling Aria", id: 1, type: "Water", dmg: "special", power: 90)
        let e = T2.engine((a, "blaze", [sa]), (b, "blaze", [sa]))
        let target = e.side2.active(at: 0)!
        target.status = .burn
        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e.executeTurn()
        let s = e.side2.active(at: 0)?.status ?? .none
        #expect(s == .none, "Sparkling Aria heals the target's burn on hit")
    }

    @Test func saltCureChipsEachEndOfTurn() {
        let a = T2.pkmn("MonA", id: 100)
        let b = T2.pkmn("MonB", id: 101, hp: 200)
        let sc = T2.mv("Salt Cure", id: 1, type: "Rock", dmg: "physical", power: 40)
        let e = T2.engine((a, "blaze", [sc]), (b, "blaze", [sc]))
        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e.executeTurn()
        let p = e.side2.active(at: 0)!
        #expect(p.saltCured)
        let hpAfterTurn1 = p.currentHP
        // Pass a turn — Salt Cure should chip.
        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e.executeTurn()
        // It chips twice (once during turn 1 EOT after the move, once turn 2 EOT
        // after the second hit). Verify HP keeps dropping.
        #expect(p.currentHP < hpAfterTurn1, "Salt Cure chips every end-of-turn")
    }

    @Test func saltCureDoublesAgainstWaterType() {
        // Use a Water defender. The chip damage at EOT should be 1/4 maxHP, not 1/8.
        let a = T2.pkmn("MonA", id: 100)
        let b = T2.pkmn("Wave", id: 101, type1: "Water", hp: 160)
        let sc = T2.mv("Salt Cure", id: 1, type: "Rock", dmg: "physical", power: 1)
        let e = T2.engine((a, "blaze", [sc]), (b, "blaze", [sc]))
        let p = e.side2.active(at: 0)!
        let hpStart = p.currentHP
        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e.executeTurn()
        // After turn 1: move damage (tiny) + 1/4 max HP salt chip on Water.
        let saltChip = max(1, p.maxHP / 4)
        // We can't isolate the move damage exactly here, but post-EOT HP should
        // be at most (hpStart - saltChip), allowing for the small move damage.
        #expect(p.currentHP <= hpStart - saltChip,
                "Salt Cure should hit Water types for ~1/4 max HP, not 1/8")
    }

    @Test func burningJealousyFizzlesWithoutBoost() {
        let a = T2.pkmn("MonA", id: 100, type1: "Fire")
        let b = T2.pkmn("MonB", id: 101, type1: "Normal")
        let bj = T2.mv("Burning Jealousy", id: 1, type: "Fire", dmg: "special", power: 70)
        let e = T2.engine((a, "blaze", [bj]), (b, "blaze", [bj]))
        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e.executeTurn()
        let s = e.side2.active(at: 0)?.status ?? .none
        #expect(s == .none, "Burning Jealousy needs a boosted target — should fizzle when none")
    }

    @Test func burningJealousyBurnsBoostedTarget() {
        let a = T2.pkmn("MonA", id: 100, type1: "Fire")
        let b = T2.pkmn("MonB", id: 101, type1: "Normal")
        let bj = T2.mv("Burning Jealousy", id: 1, type: "Fire", dmg: "special", power: 70)
        let e = T2.engine((a, "blaze", [bj]), (b, "blaze", [bj]))
        e.side2.active(at: 0)!.atkStage = 2
        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e.executeTurn()
        let s = e.side2.active(at: 0)?.status ?? .none
        #expect(s == .burn, "Burning Jealousy burns boosted targets")
    }
}
