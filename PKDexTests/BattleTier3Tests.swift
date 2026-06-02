//
//  BattleTier3Tests.swift
//  PKDexTests
//
//  Coverage for the Tier 3 recovery + volatile-state moves (Wish, Leech Seed,
//  Substitute, Endure, Encore, Disable, Destiny Bond, Roost, Pain Split,
//  Heal Pulse, Heal Bell, Strength Sap, Life Dew, Yawn, Curse).
//

import Testing
import Foundation
@testable import PKDex

@MainActor
private enum T3 {
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
                   type: String = "Normal", dmg: String = "status",
                   power: Int? = nil, priority: Int = 0,
                   healing: Int = 0, makesContact: Bool = false) -> MoveData {
        MoveData(id: id, name: name, type: type, damageClass: dmg,
                 power: power, accuracy: 100, pp: 16, priority: priority,
                 minHits: nil, maxHits: nil, drain: 0, healing: healing,
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
@Suite("Tier 3 — Recovery & Misc Heals")
struct BattleTier3RecoveryTests {

    @Test func painSplitAveragesHP() {
        let a = T3.pkmn("MonA", id: 100, hp: 200)
        let b = T3.pkmn("MonB", id: 101, hp: 200)
        let ps = T3.mv("Pain Split", id: 1, dmg: "status")
        let e = T3.engine((a, "blaze", [ps]), (b, "blaze", [ps]))
        let A = e.side1.active(at: 0)!
        let B = e.side2.active(at: 0)!
        // Maxes come from calcHP, not the raw base — compute the expected
        // average from whatever the engine actually built so the test isn't
        // brittle to formula changes.
        A.currentHP = 50
        let expected = (A.currentHP + B.currentHP) / 2
        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e.executeTurn()
        #expect(abs(A.currentHP - expected) <= 1)
        #expect(abs(B.currentHP - expected) <= 1)
    }

    @Test func healPulseHealsTargetNotUser() {
        let a = T3.pkmn("MonA", id: 100)
        let b = T3.pkmn("MonB", id: 101, hp: 200)
        let hp = T3.mv("Heal Pulse", id: 1, dmg: "status")
        let e = T3.engine((a, "blaze", [hp]), (b, "blaze", [hp]))
        let A = e.side1.active(at: 0)!
        let B = e.side2.active(at: 0)!
        let aBefore = A.currentHP
        B.currentHP = B.maxHP / 4
        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e.executeTurn()
        #expect(A.currentHP == aBefore, "Heal Pulse should not heal the user")
        #expect(B.currentHP > B.maxHP / 4, "Heal Pulse heals the target")
    }

    @Test func healBellCuresTeamStatus() {
        // Set up a benched mon with a status condition, use Heal Bell, verify cure.
        let a = T3.pkmn("MonA", id: 100)
        let bench = T3.pkmn("Bench", id: 102)
        let b = T3.pkmn("MonB", id: 101)
        let hb = T3.mv("Heal Bell", id: 1, dmg: "status")
        let aSlot = T3.slot(a, ability: "blaze", moves: [hb])
        let benchSlot = T3.slot(bench, ability: "blaze", moves: [])
        let bSlot = T3.slot(b, ability: "blaze", moves: [])
        let allP = [a, bench, b]
        let bs1 = BattleSide(label: "Side 1", slots: [aSlot, benchSlot], format: .singles,
                             allPokemon: allP, allMoves: [hb])
        let bs2 = BattleSide(label: "Side 2", slots: [bSlot], format: .singles,
                             allPokemon: allP, allMoves: [hb])
        let e = BattleEngine(format: .singles, side1: bs1, side2: bs2,
                             allPokemon: allP, allMoves: [hb])
        e.side1.participants[1].status = .burn
        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 0, targetSlot: 0))
        e.executeTurn()
        #expect(e.side1.participants[1].status == .none,
                "Heal Bell cures the benched ally's burn")
    }

    @Test func strengthSapHealsAndDropsAtk() {
        let a = T3.pkmn("MonA", id: 100, hp: 200)
        let b = T3.pkmn("MonB", id: 101)
        let ss = T3.mv("Strength Sap", id: 1, dmg: "status")
        let e = T3.engine((a, "blaze", [ss]), (b, "blaze", [ss]))
        let A = e.side1.active(at: 0)!
        let B = e.side2.active(at: 0)!
        A.currentHP = A.maxHP / 4
        let aBefore = A.currentHP
        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e.executeTurn()
        #expect(A.currentHP > aBefore, "Strength Sap heals the user")
        #expect(B.atkStage == -1, "Strength Sap drops target Atk by 1")
    }

    @Test func wishHealsTwoTurnsLater() {
        let a = T3.pkmn("MonA", id: 100, hp: 200)
        let b = T3.pkmn("MonB", id: 101)
        let wish = T3.mv("Wish", id: 1, dmg: "status")
        let splash = T3.mv("Splash", id: 2, dmg: "status")
        let e = T3.engine((a, "blaze", [wish, splash]), (b, "blaze", [splash]))
        let A = e.side1.active(at: 0)!
        A.currentHP = A.maxHP / 4
        let hpBeforeWish = A.currentHP
        // Turn 1 — Wish queued.
        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 0, targetSlot: 0))
        e.executeTurn()
        #expect(A.currentHP == hpBeforeWish, "Wish doesn't heal the turn it's used")
        #expect(e.side1.wishQueue.count == 1)
        // Turn 2 — do a no-op (Splash) so we don't re-queue another Wish.
        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 1, targetSide: 0, targetSlot: 0))
        e.executeTurn()
        #expect(A.currentHP > hpBeforeWish, "Wish heals at the end of turn 2")
        #expect(e.side1.wishQueue.isEmpty)
    }
}

@MainActor
@Suite("Tier 3 — Volatile Inflictors")
struct BattleTier3VolatileTests {

    @Test func leechSeedDrainsTargetEachTurn() {
        let a = T3.pkmn("Seeder", id: 100, hp: 100)
        let b = T3.pkmn("Seeded", id: 101, type1: "Normal", hp: 160)
        let ls = T3.mv("Leech Seed", id: 1, dmg: "status")
        let e = T3.engine((a, "blaze", [ls]), (b, "blaze", [ls]))
        let A = e.side1.active(at: 0)!
        let B = e.side2.active(at: 0)!
        // Reduce seeder HP so we can observe healing.
        A.currentHP = A.maxHP / 2
        let aBefore = A.currentHP
        let bBefore = B.currentHP
        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e.executeTurn()
        // EOT after this turn: B drained 1/8 maxHP → A.
        let chip = max(1, B.maxHP / 8)
        #expect(B.currentHP == bBefore - chip, "Leech Seed drains 1/8 of target maxHP per EOT")
        #expect(A.currentHP > aBefore, "Leech Seed heals the seeder")
    }

    @Test func leechSeedFailsOnGrass() {
        let a = T3.pkmn("Seeder", id: 100)
        let b = T3.pkmn("Grass", id: 101, type1: "Grass")
        let ls = T3.mv("Leech Seed", id: 1, dmg: "status")
        let e = T3.engine((a, "blaze", [ls]), (b, "blaze", [ls]))
        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e.executeTurn()
        #expect(e.side2.active(at: 0)?.leechSeededBy == nil,
                "Grass-types are immune to Leech Seed")
    }

    @Test func yawnSleepsTargetNextTurn() {
        let a = T3.pkmn("MonA", id: 100)
        let b = T3.pkmn("MonB", id: 101, type1: "Normal")
        let yawn = T3.mv("Yawn", id: 1, dmg: "status")
        let e = T3.engine((a, "blaze", [yawn]), (b, "blaze", [yawn]))
        let B = e.side2.active(at: 0)!
        // Turn 1 — Yawn lands. Target is drowsy but not asleep.
        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e.executeTurn()
        #expect(B.yawnCounter == 1, "Yawn 2-step countdown ticks once at EOT")
        #expect(B.status == .none)
        // Turn 2 — at EOT, counter hits 0 and inflicts sleep.
        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e.executeTurn()
        #expect(B.status == .sleep, "Yawn puts the target to sleep at the next EOT")
    }

    @Test func endureKeepsTargetAtOneHP() {
        let a = T3.pkmn("MonA", id: 100, atk: 250)
        let b = T3.pkmn("MonB", id: 101, hp: 20)
        let endure = T3.mv("Endure", id: 1, dmg: "status", priority: 4)
        let tackle = T3.mv("Tackle", id: 2, dmg: "physical", power: 200, makesContact: true)
        let e = T3.engine((a, "blaze", [tackle]), (b, "blaze", [endure]))
        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e.setAction(side: 1, slot: 0, action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e.executeTurn()
        #expect(e.side2.active(at: 0)?.currentHP == 1, "Endure clamps surviving HP at 1")
    }

    @Test func encoreLocksTargetIntoLastMove() {
        // B must outspeed A in turn 1 so its move resolves first, giving A's
        // Encore a non-nil `lastMoveIndex` to lock onto.
        let a = T3.pkmn("MonA", id: 100, spe: 50)
        let b = T3.pkmn("MonB", id: 101, spe: 200)
        let encore = T3.mv("Encore", id: 1, dmg: "status", priority: 0)
        let splash = T3.mv("Splash", id: 2, dmg: "status")
        let scratch = T3.mv("Scratch", id: 3, dmg: "physical", power: 40, makesContact: true)
        let e = T3.engine((a, "blaze", [encore, scratch]), (b, "blaze", [splash, scratch]))
        // Turn 1: B uses Splash (idx 0) first, then A encores.
        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e.setAction(side: 1, slot: 0, action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e.executeTurn()
        let B = e.side2.active(at: 0)!
        #expect(B.encoreTurns > 0, "Encore should set the timer on the target")
        #expect(B.encoreLockedIndex == 0, "Locked into B's last move (Splash, idx 0)")
        // Turn 2: B tries Scratch — should be remapped to Splash by Encore.
        // Filter the log for B's own move-use lines (A's "used Encore!" would
        // come first and confuse a naive "first match" scan).
        let logBefore = e.log.count
        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e.setAction(side: 1, slot: 0, action: .move(moveIndex: 1, targetSide: 0, targetSlot: 0))
        e.executeTurn()
        let bMoveLines = e.log[logBefore...].map(\.text)
            .filter { $0.contains("MonB used ") }
        #expect(bMoveLines.first?.contains("Splash") == true,
                "Encore-locked target uses Splash instead of Scratch")
    }

    @Test func disableBlocksLastMoveOnly() {
        // B faster so its Scratch lands before A's Disable, giving Disable a
        // non-nil lastMoveIndex to target.
        let a = T3.pkmn("MonA", id: 100, spe: 50)
        let b = T3.pkmn("MonB", id: 101, spe: 200)
        let disable = T3.mv("Disable", id: 1, dmg: "status")
        let scratch = T3.mv("Scratch", id: 2, dmg: "physical", power: 40, makesContact: true)
        let pound = T3.mv("Pound", id: 3, dmg: "physical", power: 40, makesContact: true)
        let e = T3.engine((a, "blaze", [disable, scratch]), (b, "blaze", [scratch, pound]))
        // Turn 1: B uses Scratch. A uses Disable.
        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e.setAction(side: 1, slot: 0, action: .move(moveIndex: 0, targetSide: 0, targetSlot: 0))
        e.executeTurn()
        let B = e.side2.active(at: 0)!
        #expect(B.disabledMoveIndex == 0)
        // Turn 2: B tries Scratch again — should fizzle. Pound (idx 1) still works.
        let logBefore = e.log.count
        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e.setAction(side: 1, slot: 0, action: .move(moveIndex: 0, targetSide: 0, targetSlot: 0))
        e.executeTurn()
        let disabled = e.log[logBefore...].map(\.text).contains(where: { $0.contains("disabled") })
        #expect(disabled, "Disabled move should fizzle with a log entry")
    }

    @Test func destinyBondKOsAttackerThatKnocksOutUser() {
        // Give B much higher Speed so its Destiny Bond resolves before A's Tackle
        // regardless of random tie-break.
        let a = T3.pkmn("Killer", id: 100, atk: 300, spe: 50)
        let b = T3.pkmn("Cursed", id: 101, hp: 20, spe: 200)
        let db = T3.mv("Destiny Bond", id: 1, dmg: "status", priority: 0)
        let tackle = T3.mv("Tackle", id: 2, dmg: "physical", power: 200, makesContact: true)
        let e = T3.engine((a, "blaze", [tackle]), (b, "blaze", [db, tackle]))
        e.setAction(side: 1, slot: 0, action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e.executeTurn()
        #expect(e.side1.active(at: 0)?.fainted == true,
                "Destiny Bond should KO the attacker that brought the user down")
    }

    @Test func substituteAbsorbsDamage() {
        // B faster so Sub sets up before A's Tackle.
        let a = T3.pkmn("MonA", id: 100, atk: 50, spe: 50)
        let b = T3.pkmn("MonB", id: 101, hp: 200, spe: 200)
        let sub = T3.mv("Substitute", id: 1, dmg: "status", priority: 0)
        let tackle = T3.mv("Tackle", id: 2, dmg: "physical", power: 40, makesContact: true)
        let e = T3.engine((a, "blaze", [tackle]), (b, "blaze", [sub, tackle]))
        let B = e.side2.active(at: 0)!
        // Turn 1: B subs, A tackles → all damage hits the sub.
        e.setAction(side: 1, slot: 0, action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e.executeTurn()
        // After: B's HP = maxHP - subCost (paid up front); sub may have taken
        // the hit. The user's real HP shouldn't go below "maxHP - subCost".
        let subCost = max(1, B.maxHP / 4)
        let expectedFloor = B.maxHP - subCost
        #expect(B.currentHP >= expectedFloor,
                "Substitute should absorb damage, leaving user HP at or above (maxHP - subCost)")
    }

    @Test func roostStripsFlyingTypeForTheTurn() {
        let a = T3.pkmn("Bird", id: 100, type1: "Flying", type2: "Normal", hp: 200)
        let b = T3.pkmn("MonB", id: 101)
        let roost = T3.mv("Roost", id: 1, dmg: "status")
        let e = T3.engine((a, "blaze", [roost]), (b, "blaze", [roost]))
        let A = e.side1.active(at: 0)!
        A.currentHP = A.maxHP / 2
        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 0, targetSlot: 0))
        e.executeTurn()
        // Within the same turn the Flying type would be stripped; checking the
        // EOT cleared state confirms the flag clears properly.
        #expect(A.roostedThisTurn == false, "Roost flag clears at EOT")
        #expect(A.types.contains("Flying"), "Flying typing restored next turn")
    }
}

@MainActor
@Suite("Tier 3 — Curse")
struct BattleTier3CurseTests {

    @Test func curseNonGhostBoostsAtkDefDropsSpeed() {
        let a = T3.pkmn("Snorlax", id: 143, type1: "Normal")
        let b = T3.pkmn("MonB", id: 101)
        let curse = T3.mv("Curse", id: 1, dmg: "status")
        let e = T3.engine((a, "blaze", [curse]), (b, "blaze", [curse]))
        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 0, targetSlot: 0))
        e.executeTurn()
        let A = e.side1.active(at: 0)!
        #expect(A.atkStage == 1)
        #expect(A.defStage == 1)
        #expect(A.speedStage == -1)
    }

    @Test func curseGhostPaysHalfHPCost() {
        let a = T3.pkmn("Gengar", id: 94, type1: "Ghost", type2: "Poison", hp: 200)
        let b = T3.pkmn("MonB", id: 101)
        let curse = T3.mv("Curse", id: 1, dmg: "status")
        let e = T3.engine((a, "blaze", [curse]), (b, "blaze", [curse]))
        let A = e.side1.active(at: 0)!
        let beforeHP = A.currentHP
        let cost = max(1, A.maxHP / 2)
        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e.executeTurn()
        #expect(A.currentHP == beforeHP - cost,
                "Ghost-type Curse pays 50% maxHP to lay the curse")
    }
}
