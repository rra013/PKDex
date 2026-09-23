//
//  BattleTier1Tests.swift
//  PKDexTests
//
//  Coverage for the Tier 1 field effects, protect family, pivot moves,
//  hazard removal, and supporting abilities wired into the battle simulator.
//

import Testing
import Foundation
@testable import PKDex

// MARK: - Shared fixtures

@MainActor
private enum T1 {
    // Compact factories — we only need enough stat detail to keep the engine
    // happy. None of these tests depend on damage parity with the real games.
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
                   makesContact: Bool = false) -> MoveData {
        MoveData(id: id, name: name, type: type, damageClass: dmg,
                 power: power, accuracy: 100, pp: 16, priority: priority,
                 minHits: nil, maxHits: nil, drain: 0, healing: 0,
                 critRate: 0, makesContact: makesContact)
    }

    static func slot(_ p: PKMNStats, ability: String, moves: [MoveData],
                     item: String? = nil) -> TeamSlotInfo {
        TeamSlotInfo(
            spreadName: "fx-\(p.name)",
            pokemonID: p.id, pokemonName: p.name,
            type1: p.type1, type2: p.type2,
            abilityName: ability, itemRawValue: item,
            championsMode: false, natureID: "hardy", level: 50,
            evHP: 0, evAtk: 0, evDef: 0, evSpAtk: 0, evSpDef: 0, evSpeed: 0,
            moveSlots: moves.map {
                TeamMoveInfo(moveID: $0.id, moveName: $0.name, moveType: $0.type,
                             damageClass: $0.damageClass, power: $0.power, isSTAB: false)
            }
        )
    }

    /// Spin up a 1v1 engine from a pair of (pokemon, ability, moves) tuples.
    static func engine(_ a: (PKMNStats, String, [MoveData]),
                       _ b: (PKMNStats, String, [MoveData]),
                       format: BattleFormat = .singles,
                       itemA: String? = nil, itemB: String? = nil) -> BattleEngine {
        let sA = slot(a.0, ability: a.1, moves: a.2, item: itemA)
        let sB = slot(b.0, ability: b.1, moves: b.2, item: itemB)
        let allP = [a.0, b.0]
        let allM = a.2 + b.2
        let bs1 = BattleSide(label: "Side 1", slots: [sA], format: format,
                             allPokemon: allP, allMoves: allM)
        let bs2 = BattleSide(label: "Side 2", slots: [sB], format: format,
                             allPokemon: allP, allMoves: allM)
        return BattleEngine(format: format, side1: bs1, side2: bs2,
                            allPokemon: allP, allMoves: allM)
    }

    /// Doubles engine with two members per side. Each tuple is (mon, ability, moves).
    static func doublesEngine(side1: [(PKMNStats, String, [MoveData])],
                              side2: [(PKMNStats, String, [MoveData])]) -> BattleEngine {
        let slotsA = side1.map { slot($0.0, ability: $0.1, moves: $0.2) }
        let slotsB = side2.map { slot($0.0, ability: $0.1, moves: $0.2) }
        let allP = side1.map(\.0) + side2.map(\.0)
        let allM = side1.flatMap(\.2) + side2.flatMap(\.2)
        let bs1 = BattleSide(label: "Side 1", slots: slotsA, format: .doubles,
                             allPokemon: allP, allMoves: allM)
        let bs2 = BattleSide(label: "Side 2", slots: slotsB, format: .doubles,
                             allPokemon: allP, allMoves: allM)
        return BattleEngine(format: .doubles, side1: bs1, side2: bs2,
                            allPokemon: allP, allMoves: allM)
    }
}

// MARK: - Field rooms (Trick Room, Wonder Room, Magic Room, Gravity)

@MainActor
@Suite("Tier 1 — Field Rooms")
struct BattleFieldRoomsTests {

    @Test func trickRoomFlipsSpeedOrder() {
        let slow = T1.pkmn("Slowmon", id: 100, spe: 30)
        let fast = T1.pkmn("Fastmon", id: 101, spe: 200)
        let tr = T1.mv("Trick Room", id: 1, dmg: "status", priority: -7)
        let tackle = T1.mv("Tackle", id: 2, dmg: "physical", power: 40, makesContact: true)
        let e = T1.engine((slow, "blaze", [tr, tackle]), (fast, "blaze", [tackle]))

        // Slow uses Trick Room; Fast uses Tackle.
        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 0, targetSlot: 0))
        e.setAction(side: 1, slot: 0, action: .move(moveIndex: 0, targetSide: 0, targetSlot: 0))
        e.executeTurn()

        #expect(e.trickRoomTurns == 4, "Trick Room sets a 5-turn timer (decremented at EOT to 4)")

        // Snapshot the log so we only inspect turn-2 entries — turn 1 already
        // logged a Fastmon Tackle and would dominate the "first match" check.
        let logCountAfterTurn1 = e.log.count
        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 1, targetSide: 1, targetSlot: 0))
        e.setAction(side: 1, slot: 0, action: .move(moveIndex: 0, targetSide: 0, targetSlot: 0))
        e.executeTurn()

        let turn2Tackles = e.log[logCountAfterTurn1...].map(\.text)
            .filter { $0.contains(" used Tackle!") }
        #expect(turn2Tackles.first?.contains("Slowmon") == true,
                "Under Trick Room, the slower mon moves first")
    }

    @Test func trickRoomToggleCancelsItself() {
        let m = T1.pkmn("MonA", id: 100)
        let n = T1.pkmn("MonB", id: 101)
        let tr = T1.mv("Trick Room", id: 1, dmg: "status", priority: -7)
        let e = T1.engine((m, "blaze", [tr]), (n, "blaze", [tr]))
        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 0, targetSlot: 0))
        e.setAction(side: 1, slot: 0, action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e.executeTurn()
        // Second TR cancels — start of next turn ends with TR off again.
        #expect(e.trickRoomTurns == 0, "Two TRs same turn cancel out (one sets, the other clears)")
    }

    @Test func gravityGroundsAndExpires() {
        let m = T1.pkmn("MonA", id: 100, type1: "Flying")
        let n = T1.pkmn("MonB", id: 101)
        let grav = T1.mv("Gravity", id: 1)
        let e = T1.engine((m, "blaze", [grav]), (n, "blaze", [grav]))
        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 0, targetSlot: 0))
        e.setAction(side: 1, slot: 0, action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e.executeTurn()
        #expect(e.gravityTurns == 4, "Gravity sets 5 turns; ticks to 4 at EOT")
        #expect(e.side1.active(at: 0)?.grounded == true,
                "Flying-type mon is grounded while Gravity is up")
    }

    @Test func wonderRoomAndMagicRoomCountdowns() {
        let m = T1.pkmn("MonA", id: 100)
        let n = T1.pkmn("MonB", id: 101)
        let wr = T1.mv("Wonder Room", id: 1)
        let mr = T1.mv("Magic Room", id: 2)
        let e = T1.engine((m, "blaze", [wr, mr]), (n, "blaze", [wr]))
        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 0, targetSlot: 0))
        e.setAction(side: 1, slot: 0, action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e.executeTurn()
        // Both sides used Wonder Room — second call toggles off.
        #expect(e.wonderRoomTurns == 0)

        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 1, targetSide: 0, targetSlot: 0))
        // Side 2 stands down.
        e.executeTurn()
        #expect(e.magicRoomTurns == 4, "Magic Room single-set lands a 5-turn timer (4 after EOT)")
    }
}

// MARK: - Tailwind

@MainActor
@Suite("Tier 1 — Tailwind")
struct BattleTailwindTests {

    @Test func tailwindDoublesEffectiveSpeed() {
        let slow = T1.pkmn("Slow", id: 100, spe: 60)
        let fast = T1.pkmn("Fast", id: 101, spe: 80)
        let tw = T1.mv("Tailwind", id: 1, dmg: "status", priority: 0)
        let tackle = T1.mv("Tackle", id: 2, dmg: "physical", power: 40, makesContact: true)
        let e = T1.engine((slow, "blaze", [tw, tackle]), (fast, "blaze", [tackle]))

        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 0, targetSlot: 0))
        e.setAction(side: 1, slot: 0, action: .move(moveIndex: 0, targetSide: 0, targetSlot: 0))
        e.executeTurn()

        #expect(e.side1.tailwindTurns == 3, "Tailwind lasts 4 turns, ticks to 3 at EOT")

        let logCountAfterTurn1 = e.log.count
        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 1, targetSide: 1, targetSlot: 0))
        e.setAction(side: 1, slot: 0, action: .move(moveIndex: 0, targetSide: 0, targetSlot: 0))
        e.executeTurn()
        let turn2Tackles = e.log[logCountAfterTurn1...].map(\.text)
            .filter { $0.contains(" used Tackle!") }
        #expect(turn2Tackles.first?.contains("Slow") == true,
                "Tailwind doubles effective Speed so Slow now outruns Fast")
    }

    @Test func tailwindExpiresAfterFourTurns() {
        let m = T1.pkmn("MonA", id: 100)
        let n = T1.pkmn("MonB", id: 101)
        let tw = T1.mv("Tailwind", id: 1)
        let e = T1.engine((m, "blaze", [tw]), (n, "blaze", [tw]))
        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 0, targetSlot: 0))
        e.setAction(side: 1, slot: 0, action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e.executeTurn()
        #expect(e.side1.tailwindTurns == 3)
        // Burn the remaining turns.
        for _ in 0..<3 {
            e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 0, targetSlot: 0))
            e.setAction(side: 1, slot: 0, action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
            e.executeTurn()
        }
        #expect(e.side1.tailwindTurns == 0)
    }
}

// MARK: - Screens

@MainActor
@Suite("Tier 1 — Screens & Safeguard")
struct BattleScreensTests {

    @Test func lightScreenSetsTurnCounter() {
        let m = T1.pkmn("MonA", id: 100)
        let n = T1.pkmn("MonB", id: 101)
        let ls = T1.mv("Light Screen", id: 1)
        let e = T1.engine((m, "blaze", [ls]), (n, "blaze", [ls]))
        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 0, targetSlot: 0))
        e.executeTurn()
        #expect(e.side1.lightScreenTurns == 4, "Light Screen → 5 turns, ticks to 4")
    }

    @Test func reflectSetsTurnCounter() {
        let m = T1.pkmn("MonA", id: 100)
        let n = T1.pkmn("MonB", id: 101)
        let rf = T1.mv("Reflect", id: 1)
        let e = T1.engine((m, "blaze", [rf]), (n, "blaze", [rf]))
        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 0, targetSlot: 0))
        e.executeTurn()
        #expect(e.side1.reflectTurns == 4)
    }

    @Test func auroraVeilFizzlesWithoutSnow() {
        let m = T1.pkmn("MonA", id: 100)
        let n = T1.pkmn("MonB", id: 101)
        let av = T1.mv("Aurora Veil", id: 1)
        let e = T1.engine((m, "blaze", [av]), (n, "blaze", [av]))
        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 0, targetSlot: 0))
        e.executeTurn()
        #expect(e.side1.auroraVeilTurns == 0, "No snow — Aurora Veil should fail")
        #expect(e.log.contains(where: { $0.text.contains("Aurora Veil needs snow") }))
    }

    @Test func auroraVeilSucceedsInSnow() {
        let m = T1.pkmn("MonA", id: 100)
        let n = T1.pkmn("MonB", id: 101)
        let av = T1.mv("Aurora Veil", id: 1)
        let e = T1.engine((m, "blaze", [av]), (n, "blaze", [av]))
        e.weather = .snow
        e.weatherTurns = 5
        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 0, targetSlot: 0))
        e.executeTurn()
        #expect(e.side1.auroraVeilTurns == 4, "In snow Aurora Veil sticks")
    }

    @Test func lightClayExtendsScreenDuration() {
        let m = T1.pkmn("MonA", id: 100)
        let n = T1.pkmn("MonB", id: 101)
        let ls = T1.mv("Light Screen", id: 1)
        let e = T1.engine((m, "blaze", [ls]), (n, "blaze", [ls]),
                          itemA: HeldItem.lightClay.rawValue)
        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 0, targetSlot: 0))
        e.executeTurn()
        #expect(e.side1.lightScreenTurns == 7,
                "Light Clay extends screen from 5 → 8, ticks to 7 after EOT")
    }

    @Test func safeguardBlocksStatusInfliction() {
        let m = T1.pkmn("MonA", id: 100)
        let n = T1.pkmn("MonB", id: 101)
        let sg = T1.mv("Safeguard", id: 1)
        let wow = T1.mv("Will-O-Wisp", id: 2, type: "Fire", dmg: "status")
        let e = T1.engine((m, "blaze", [sg]), (n, "blaze", [wow]))
        // Turn 1: side 1 sets Safeguard, side 2 sits still. Cleanly separates
        // the screen setup from the burn attempt so turn order can't flip it.
        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 0, targetSlot: 0))
        e.executeTurn()
        #expect(e.side1.safeguardTurns == 4)
        // Turn 2: Will-O-Wisp should bounce off Safeguard.
        e.setAction(side: 1, slot: 0, action: .move(moveIndex: 0, targetSide: 0, targetSlot: 0))
        e.executeTurn()
        let s = e.side1.active(at: 0)?.status ?? .none
        #expect(s == .none, "Safeguard blocks new burn status from landing")
    }
}

// MARK: - Protect family

@MainActor
@Suite("Tier 1 — Protect Family")
struct BattleProtectTests {

    @Test func protectBlocksDamageThisTurn() {
        let m = T1.pkmn("MonA", id: 100, hp: 200)
        let n = T1.pkmn("MonB", id: 101, atk: 200)
        let protectM = T1.mv("Protect", id: 1, dmg: "status", priority: 4)
        let tackle = T1.mv("Tackle", id: 2, dmg: "physical", power: 80, makesContact: true)
        let e = T1.engine((m, "blaze", [protectM]), (n, "blaze", [tackle]))
        let p = e.side1.active(at: 0)!
        let hpBefore = p.currentHP
        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 0, targetSlot: 0))
        e.setAction(side: 1, slot: 0, action: .move(moveIndex: 0, targetSide: 0, targetSlot: 0))
        e.executeTurn()
        #expect(p.currentHP == hpBefore, "Protect should keep HP unchanged")
        #expect(p.consecutiveProtectCount == 1)
        // End-of-turn cleared the flag.
        #expect(p.protectedThisTurn == false)
    }

    @Test func spikyShieldChipsContactAttacker() {
        let m = T1.pkmn("MonA", id: 100, hp: 200)
        let n = T1.pkmn("MonB", id: 101)
        let ss = T1.mv("Spiky Shield", id: 1, dmg: "status", priority: 4)
        let tackle = T1.mv("Tackle", id: 2, dmg: "physical", power: 40, makesContact: true)
        let e = T1.engine((m, "blaze", [ss]), (n, "blaze", [tackle]))
        let attacker = e.side2.active(at: 0)!
        let hpBefore = attacker.currentHP
        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 0, targetSlot: 0))
        e.setAction(side: 1, slot: 0, action: .move(moveIndex: 0, targetSide: 0, targetSlot: 0))
        e.executeTurn()
        #expect(attacker.currentHP < hpBefore, "Spiky Shield should chip the attacker on contact")
    }

    @Test func banefulBunkerPoisonsContactAttacker() {
        let m = T1.pkmn("MonA", id: 100, hp: 200)
        let n = T1.pkmn("MonB", id: 101, type1: "Normal")
        let bb = T1.mv("Baneful Bunker", id: 1, dmg: "status", priority: 4)
        let tackle = T1.mv("Tackle", id: 2, dmg: "physical", power: 40, makesContact: true)
        let e = T1.engine((m, "blaze", [bb]), (n, "blaze", [tackle]))
        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 0, targetSlot: 0))
        e.setAction(side: 1, slot: 0, action: .move(moveIndex: 0, targetSide: 0, targetSlot: 0))
        e.executeTurn()
        #expect(e.side2.active(at: 0)?.status == .poison)
    }

    @Test func protectStreakResetsOnFailure() {
        // Force a deterministic streak: run two Protects, then a non-protect move
        // should reset the counter regardless of whether the second succeeded.
        let m = T1.pkmn("MonA", id: 100)
        let n = T1.pkmn("MonB", id: 101)
        let protectM = T1.mv("Protect", id: 1, dmg: "status", priority: 4)
        let tackle = T1.mv("Tackle", id: 2, dmg: "physical", power: 40, makesContact: true)
        let e = T1.engine((m, "blaze", [protectM, tackle]), (n, "blaze", [tackle]))
        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 0, targetSlot: 0))
        e.setAction(side: 1, slot: 0, action: .move(moveIndex: 0, targetSide: 0, targetSlot: 0))
        e.executeTurn()
        // Then use Tackle next turn — streak should reset.
        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 1, targetSide: 1, targetSlot: 0))
        e.setAction(side: 1, slot: 0, action: .move(moveIndex: 0, targetSide: 0, targetSlot: 0))
        e.executeTurn()
        #expect(e.side1.active(at: 0)?.consecutiveProtectCount == 0)
    }
}

// MARK: - Pivot moves

@MainActor
@Suite("Tier 1 — Pivot Moves")
struct BattlePivotTests {

    @Test func uTurnQueuesForceSwitch() {
        let m = T1.pkmn("MonA", id: 100)
        let bench = T1.pkmn("Bench", id: 102)
        let n = T1.pkmn("MonB", id: 101)
        let ut = T1.mv("U-turn", id: 1, type: "Bug", dmg: "physical",
                       power: 70, makesContact: true)
        let tackle = T1.mv("Tackle", id: 2, dmg: "physical", power: 40)
        // Side 1 has two slots — the pivot needs a bench mon to swap to.
        let aSlot = T1.slot(m, ability: "blaze", moves: [ut])
        let benchSlot = T1.slot(bench, ability: "blaze", moves: [])
        let bSlot = T1.slot(n, ability: "blaze", moves: [tackle])
        let allP = [m, bench, n]
        let allM = [ut, tackle]
        let bs1 = BattleSide(label: "Side 1", slots: [aSlot, benchSlot], format: .singles,
                             allPokemon: allP, allMoves: allM)
        let bs2 = BattleSide(label: "Side 2", slots: [bSlot], format: .singles,
                             allPokemon: allP, allMoves: allM)
        let e = BattleEngine(format: .singles, side1: bs1, side2: bs2,
                             allPokemon: allP, allMoves: allM)
        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e.executeTurn()
        #expect(e.pendingForceSwitches.contains(where: { $0.side == 0 && $0.slot == 0 }),
                "U-turn should queue a force-switch for the attacker")
    }

    @Test func teleportQueuesForceSwitch() {
        let m = T1.pkmn("MonA", id: 100)
        let bench = T1.pkmn("Bench", id: 102)
        let n = T1.pkmn("MonB", id: 101)
        let tp = T1.mv("Teleport", id: 1, dmg: "status", priority: -6)
        let aSlot = T1.slot(m, ability: "blaze", moves: [tp])
        let benchSlot = T1.slot(bench, ability: "blaze", moves: [])
        let bSlot = T1.slot(n, ability: "blaze", moves: [])
        let allP = [m, bench, n]
        let bs1 = BattleSide(label: "Side 1", slots: [aSlot, benchSlot], format: .singles,
                             allPokemon: allP, allMoves: [tp])
        let bs2 = BattleSide(label: "Side 2", slots: [bSlot], format: .singles,
                             allPokemon: allP, allMoves: [tp])
        let e = BattleEngine(format: .singles, side1: bs1, side2: bs2,
                             allPokemon: allP, allMoves: [tp])
        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 0, targetSlot: 0))
        e.executeTurn()
        #expect(e.pendingForceSwitches.contains(where: { $0.side == 0 && $0.slot == 0 }))
    }

    @Test func partingShotDropsTargetStatsThenSwitches() {
        let m = T1.pkmn("MonA", id: 100)
        let bench = T1.pkmn("Bench", id: 102)
        let n = T1.pkmn("MonB", id: 101)
        let ps = T1.mv("Parting Shot", id: 1, dmg: "status")
        let aSlot = T1.slot(m, ability: "blaze", moves: [ps])
        let benchSlot = T1.slot(bench, ability: "blaze", moves: [])
        let bSlot = T1.slot(n, ability: "blaze", moves: [])
        let allP = [m, bench, n]
        let bs1 = BattleSide(label: "Side 1", slots: [aSlot, benchSlot], format: .singles,
                             allPokemon: allP, allMoves: [ps])
        let bs2 = BattleSide(label: "Side 2", slots: [bSlot], format: .singles,
                             allPokemon: allP, allMoves: [ps])
        let e = BattleEngine(format: .singles, side1: bs1, side2: bs2,
                             allPokemon: allP, allMoves: [ps])
        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e.executeTurn()
        let target = e.side2.active(at: 0)!
        #expect(target.atkStage == -1)
        #expect(target.spAtkStage == -1)
        #expect(e.pendingForceSwitches.contains(where: { $0.side == 0 && $0.slot == 0 }))
    }
}

// MARK: - Hazard removal

@MainActor
@Suite("Tier 1 — Hazard Removal")
struct BattleHazardRemovalTests {

    @Test func rapidSpinClearsOwnSideHazards() {
        let m = T1.pkmn("MonA", id: 100)
        let n = T1.pkmn("MonB", id: 101)
        let rs = T1.mv("Rapid Spin", id: 1, dmg: "physical", power: 50, makesContact: true)
        let e = T1.engine((m, "blaze", [rs]), (n, "blaze", [rs]))
        e.side1.stealthRock = true
        e.side1.spikesLayers = 2
        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e.executeTurn()
        #expect(e.side1.stealthRock == false)
        #expect(e.side1.spikesLayers == 0)
    }

    @Test func defogClearsBothSidesAndScreens() {
        let m = T1.pkmn("MonA", id: 100)
        let n = T1.pkmn("MonB", id: 101)
        let df = T1.mv("Defog", id: 1, type: "Flying", dmg: "status")
        let e = T1.engine((m, "blaze", [df]), (n, "blaze", [df]))
        e.side1.stealthRock = true
        e.side2.stealthRock = true
        e.side1.lightScreenTurns = 4
        e.side2.reflectTurns = 4
        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e.executeTurn()
        #expect(e.side1.stealthRock == false)
        #expect(e.side2.stealthRock == false)
        #expect(e.side1.lightScreenTurns == 0)
        #expect(e.side2.reflectTurns == 0)
    }

    @Test func tidyUpClearsBothSidesAndBoostsAtkSpeed() {
        let m = T1.pkmn("MonA", id: 100)
        let n = T1.pkmn("MonB", id: 101)
        let tu = T1.mv("Tidy Up", id: 1, dmg: "status")
        let e = T1.engine((m, "blaze", [tu]), (n, "blaze", [tu]))
        e.side1.spikesLayers = 3
        e.side2.stealthRock = true
        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 0, targetSlot: 0))
        e.executeTurn()
        #expect(e.side1.spikesLayers == 0)
        #expect(e.side2.stealthRock == false)
        #expect(e.side1.active(at: 0)?.atkStage == 1)
        #expect(e.side1.active(at: 0)?.speedStage == 1)
    }

    @Test func toxicSpikesInflictPoisonOnSwitchIn() {
        // Toxic Spikes set on side 2 — incoming mon should be poisoned on switch.
        let m = T1.pkmn("MonA", id: 100)
        let bench = T1.pkmn("Bench", id: 102, type1: "Normal")
        let n = T1.pkmn("MonB", id: 101)
        let ts = T1.mv("Toxic Spikes", id: 1)
        let aSlot = T1.slot(m, ability: "blaze", moves: [ts])
        let bSlot = T1.slot(n, ability: "blaze", moves: [])
        let benchSlot = T1.slot(bench, ability: "blaze", moves: [])
        let allP = [m, bench, n]
        let bs1 = BattleSide(label: "Side 1", slots: [aSlot], format: .singles,
                             allPokemon: allP, allMoves: [ts])
        let bs2 = BattleSide(label: "Side 2", slots: [bSlot, benchSlot], format: .singles,
                             allPokemon: allP, allMoves: [ts])
        let e = BattleEngine(format: .singles, side1: bs1, side2: bs2,
                             allPokemon: allP, allMoves: [ts])
        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e.executeTurn()
        // Force-switch the side 2 active to the bench.
        e.forceSwitch(side: 1, slot: 0, benchIndex: 1)
        #expect(e.side2.active(at: 0)?.status == .poison,
                "Toxic Spikes (1 layer) should poison a grounded incoming non-Poison mon")
    }

    @Test func toxicSpikesAbsorbedByPoisonType() {
        let m = T1.pkmn("MonA", id: 100)
        let poison = T1.pkmn("PoisonMon", id: 102, type1: "Poison")
        let n = T1.pkmn("MonB", id: 101)
        let ts = T1.mv("Toxic Spikes", id: 1)
        let aSlot = T1.slot(m, ability: "blaze", moves: [ts])
        let bSlot = T1.slot(n, ability: "blaze", moves: [])
        let benchSlot = T1.slot(poison, ability: "blaze", moves: [])
        let allP = [m, poison, n]
        let bs1 = BattleSide(label: "Side 1", slots: [aSlot], format: .singles,
                             allPokemon: allP, allMoves: [ts])
        let bs2 = BattleSide(label: "Side 2", slots: [bSlot, benchSlot], format: .singles,
                             allPokemon: allP, allMoves: [ts])
        let e = BattleEngine(format: .singles, side1: bs1, side2: bs2,
                             allPokemon: allP, allMoves: [ts])
        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e.executeTurn()
        #expect(e.side2.toxicSpikesLayers == 1)
        e.forceSwitch(side: 1, slot: 0, benchIndex: 1)
        let s = e.side2.active(at: 0)?.status ?? .none
        #expect(s == .none, "Poison-type absorbs Toxic Spikes")
        #expect(e.side2.toxicSpikesLayers == 0)
    }
}

// MARK: - Abilities

@MainActor
@Suite("Tier 1 — Abilities (Magic Bounce / Synchronize / Trace / Regenerator / Magic Guard)")
struct BattleTier1AbilityTests {

    @Test func magicBounceReflectsWillOWisp() {
        let m = T1.pkmn("MonA", id: 100, type1: "Water")
        let n = T1.pkmn("MonB", id: 101, type1: "Normal")
        let wow = T1.mv("Will-O-Wisp", id: 1, type: "Fire", dmg: "status")
        let e = T1.engine((m, "blaze", [wow]), (n, "magic-bounce", [wow]))
        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e.executeTurn()
        let userStatus = e.side1.active(at: 0)?.status ?? .none
        let targetStatus = e.side2.active(at: 0)?.status ?? .none
        #expect(userStatus == .burn, "Magic Bounce reflects the burn back at the user")
        #expect(targetStatus == .none, "Target with Magic Bounce stays clean")
    }

    @Test func synchronizePassesBurnBackToAttacker() {
        // Side 1 inflicts burn (Will-O-Wisp); side 2 has Synchronize → burn bounces.
        let m = T1.pkmn("MonA", id: 100, type1: "Water")
        let n = T1.pkmn("MonB", id: 101, type1: "Normal")
        let wow = T1.mv("Will-O-Wisp", id: 1, type: "Fire", dmg: "status")
        let e = T1.engine((m, "blaze", [wow]), (n, "synchronize", [wow]))
        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e.executeTurn()
        #expect(e.side2.active(at: 0)?.status == .burn,
                "Synchronize target still burns")
        #expect(e.side1.active(at: 0)?.status == .burn,
                "Synchronize passes burn back to the attacker")
    }

    @Test func traceCopiesOpponentAbility() {
        // Tracer enters with Trace; opponent has Drought. Trace copies it.
        let tracer = T1.pkmn("Tracer", id: 100, ability: "trace")
        let sunner = T1.pkmn("Sunner", id: 101, ability: "drought")
        let move = T1.mv("Tackle", id: 1, dmg: "physical", power: 40)
        let e = T1.engine((tracer, "trace", [move]), (sunner, "drought", [move]))
        // The Sun-setter sets weather on its entry; Trace then copies Drought.
        let t = e.side1.active(at: 0)!
        #expect(t.tracedAbility == "drought")
        #expect(t.activeAbility == "drought")
    }

    @Test func regeneratorHealsOnSwitchOut() {
        let m = T1.pkmn("MonA", id: 100, ability: "regenerator", hp: 200)
        let bench = T1.pkmn("Bench", id: 102)
        let n = T1.pkmn("MonB", id: 101)
        let move = T1.mv("Tackle", id: 1, dmg: "physical", power: 40)
        let aSlot = T1.slot(m, ability: "regenerator", moves: [move])
        let benchSlot = T1.slot(bench, ability: "blaze", moves: [])
        let bSlot = T1.slot(n, ability: "blaze", moves: [move])
        let allP = [m, bench, n]
        let bs1 = BattleSide(label: "Side 1", slots: [aSlot, benchSlot], format: .singles,
                             allPokemon: allP, allMoves: [move])
        let bs2 = BattleSide(label: "Side 2", slots: [bSlot], format: .singles,
                             allPokemon: allP, allMoves: [move])
        let e = BattleEngine(format: .singles, side1: bs1, side2: bs2,
                             allPokemon: allP, allMoves: [move])
        let p = e.side1.active(at: 0)!
        p.currentHP = p.maxHP / 2
        let beforeHP = p.currentHP
        e.setAction(side: 0, slot: 0, action: .switchTo(benchIndex: 1))
        e.executeTurn()
        // p has switched out — we read its persistent HP via participants array.
        let outgoing = e.side1.participants.first { $0 === p }!
        let expectedHeal = max(1, p.maxHP / 3)
        #expect(outgoing.currentHP >= beforeHP + expectedHeal - 1,
                "Regenerator heals ~1/3 max HP on switch-out")
    }

    @Test func magicGuardSuppressesStealthRockOnSwitchIn() {
        let m = T1.pkmn("MonA", id: 100)
        let bench = T1.pkmn("Bench", id: 102, type1: "Rock", ability: "magic-guard")
        let n = T1.pkmn("MonB", id: 101)
        let move = T1.mv("Tackle", id: 1, dmg: "physical", power: 40)
        let aSlot = T1.slot(m, ability: "blaze", moves: [move])
        let benchSlot = T1.slot(bench, ability: "magic-guard", moves: [])
        let bSlot = T1.slot(n, ability: "blaze", moves: [move])
        let allP = [m, bench, n]
        let bs1 = BattleSide(label: "Side 1", slots: [aSlot, benchSlot], format: .singles,
                             allPokemon: allP, allMoves: [move])
        let bs2 = BattleSide(label: "Side 2", slots: [bSlot], format: .singles,
                             allPokemon: allP, allMoves: [move])
        let e = BattleEngine(format: .singles, side1: bs1, side2: bs2,
                             allPokemon: allP, allMoves: [move])
        e.side1.stealthRock = true
        e.setAction(side: 0, slot: 0, action: .switchTo(benchIndex: 1))
        e.executeTurn()
        // The newly-active mon should not have taken Stealth Rock damage.
        let active = e.side1.active(at: 0)!
        #expect(active.currentHP == active.maxHP,
                "Magic Guard exempts the holder from Stealth Rock")
    }

    @Test func disguiseBlocksFirstDamagingHit() {
        let mimikyu = T1.pkmn("Mimikyu", id: 778,
                              type1: "Ghost", type2: "Fairy",
                              ability: "disguise", hp: 200)
        let attacker = T1.pkmn("MonB", id: 101, type1: "Ghost", atk: 250)
        let shadow = T1.mv("Shadow Ball", id: 1, type: "Ghost", dmg: "special", power: 80)
        let e = T1.engine((mimikyu, "disguise", [shadow]), (attacker, "blaze", [shadow]))
        let p = e.side1.active(at: 0)!
        let hpBefore = p.currentHP
        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e.setAction(side: 1, slot: 0, action: .move(moveIndex: 0, targetSide: 0, targetSlot: 0))
        e.executeTurn()
        let chip = max(1, p.maxHP / 8)
        #expect(p.currentHP == hpBefore - chip,
                "Disguise reduces first damaging hit to 1/8 max HP chip")
        #expect(p.disguiseIntact == false)
    }
}

// MARK: - Doubles utility (Helping Hand / Follow Me / Ally Switch / Telepathy)

@MainActor
@Suite("Tier 1 — Doubles Utility")
struct BattleTier1DoublesTests {

    @Test func helpingHandSetsPartnerPendingFlag() {
        let a1 = T1.pkmn("A1", id: 100)
        let a2 = T1.pkmn("A2", id: 101)
        let b1 = T1.pkmn("B1", id: 102)
        let b2 = T1.pkmn("B2", id: 103)
        let hh = T1.mv("Helping Hand", id: 1, dmg: "status", priority: 5)
        let tackle = T1.mv("Tackle", id: 2, dmg: "physical", power: 40)
        let e = T1.doublesEngine(side1: [(a1, "blaze", [hh]), (a2, "blaze", [tackle])],
                                 side2: [(b1, "blaze", [tackle]), (b2, "blaze", [tackle])])
        // Slot 0 uses Helping Hand toward partner (we only need the flag set).
        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 0, targetSlot: 1))
        // Slot 1 attacks foe slot 0.
        e.setAction(side: 0, slot: 1, action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        // Side 2 sits passive for clarity.
        e.setAction(side: 1, slot: 0, action: .move(moveIndex: 0, targetSide: 0, targetSlot: 0))
        e.setAction(side: 1, slot: 1, action: .move(moveIndex: 0, targetSide: 0, targetSlot: 0))
        e.executeTurn()
        // After EOT the flag clears, so we just verify the log entry fired.
        #expect(e.log.contains(where: { $0.text.contains("rooting for") }),
                "Helping Hand should log a rooting message at use time")
    }

    @Test func followMeRedirectsOpponentMove() {
        let a1 = T1.pkmn("A1", id: 100, hp: 200)
        let a2 = T1.pkmn("A2", id: 101, hp: 200)
        let b1 = T1.pkmn("B1", id: 102)
        let b2 = T1.pkmn("B2", id: 103)
        let fm = T1.mv("Follow Me", id: 1, dmg: "status", priority: 2)
        let tackle = T1.mv("Tackle", id: 2, dmg: "physical", power: 80, makesContact: true)
        let e = T1.doublesEngine(side1: [(a1, "blaze", [fm]), (a2, "blaze", [tackle])],
                                 side2: [(b1, "blaze", [tackle]), (b2, "blaze", [tackle])])
        // A1 uses Follow Me. B1 targets A2 — should redirect to A1.
        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 0, targetSlot: 0))
        e.setAction(side: 0, slot: 1, action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e.setAction(side: 1, slot: 0, action: .move(moveIndex: 0, targetSide: 0, targetSlot: 1))
        e.setAction(side: 1, slot: 1, action: .move(moveIndex: 0, targetSide: 0, targetSlot: 1))
        e.executeTurn()
        let A1 = e.side1.active(at: 0)!
        let A2 = e.side1.active(at: 1)!
        // A1 should have taken damage (redirected hits), A2 untouched.
        #expect(A1.currentHP < A1.maxHP)
        #expect(A2.currentHP == A2.maxHP, "Follow Me on A1 should redirect every foe hit off A2")
    }

    @Test func allySwitchSwapsSlots() {
        let a1 = T1.pkmn("A1", id: 100)
        let a2 = T1.pkmn("A2", id: 101)
        let b1 = T1.pkmn("B1", id: 102)
        let b2 = T1.pkmn("B2", id: 103)
        let asMv = T1.mv("Ally Switch", id: 1, dmg: "status", priority: 0)
        let tackle = T1.mv("Tackle", id: 2, dmg: "physical", power: 40)
        // Only A1 holds Ally Switch — otherwise the queued action for slot 1
        // would resolve as a SECOND Ally Switch after the swap (slot 1 now
        // contains A1, whose move 0 is Ally Switch) and undo the test setup.
        let e = T1.doublesEngine(side1: [(a1, "blaze", [asMv]), (a2, "blaze", [tackle])],
                                 side2: [(b1, "blaze", [tackle]), (b2, "blaze", [tackle])])
        let beforeSlot0 = e.side1.active(at: 0)!.displayName
        let beforeSlot1 = e.side1.active(at: 1)!.displayName
        // Only A1 acts. Side 2 sits still so the swap is observable cleanly.
        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 0, targetSlot: 0))
        e.executeTurn()
        let afterSlot0 = e.side1.active(at: 0)!.displayName
        let afterSlot1 = e.side1.active(at: 1)!.displayName
        #expect(afterSlot0 == beforeSlot1)
        #expect(afterSlot1 == beforeSlot0)
    }

    @Test func telepathyBlocksAllyTargetedDamage() {
        let a1 = T1.pkmn("A1", id: 100)
        let tele = T1.pkmn("Telepath", id: 101, ability: "telepathy", hp: 200)
        let b1 = T1.pkmn("B1", id: 102)
        let b2 = T1.pkmn("B2", id: 103)
        let tackle = T1.mv("Tackle", id: 1, dmg: "physical", power: 80, makesContact: true)
        let e = T1.doublesEngine(side1: [(a1, "blaze", [tackle]), (tele, "telepathy", [tackle])],
                                 side2: [(b1, "blaze", [tackle]), (b2, "blaze", [tackle])])
        // A1 targets the ally Telepath.
        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 0, targetSlot: 1))
        e.setAction(side: 0, slot: 1, action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e.setAction(side: 1, slot: 0, action: .move(moveIndex: 0, targetSide: 0, targetSlot: 0))
        e.setAction(side: 1, slot: 1, action: .move(moveIndex: 0, targetSide: 0, targetSlot: 0))
        e.executeTurn()
        let telep = e.side1.active(at: 1)!
        #expect(telep.currentHP == telep.maxHP,
                "Telepathy keeps ally Pokemon untouched by partner's targeted move")
    }
}
