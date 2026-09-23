//
//  BattleFirstTurnOnlyMoveTests.swift
//  PKDexTests
//
//  Pins down Fake Out and First Impression behaviour in the Champions engine.
//  Contract per Pokémon Legends Z-A / Champions:
//    - The move can only be **selected** while the user is on their first
//      action since being sent in. Once they've moved, the UI grays out the
//      button (engine-side predicate `isFirstTurnOnlyMoveLockedOut`).
//    - There is no "But it failed!" outcome — if Encore (or any other
//      forced-action path) corners the holder into the now-illegal move,
//      the engine swaps the action for Struggle.
//    - Switching out (any path that runs `resetVolatile`) re-arms the move
//      for the holder's next switch-in cycle.
//

import Testing
import Foundation
@testable import PKDex

@MainActor
@Suite("Battle Engine — Fake Out / First Impression Restrictions")
struct BattleFirstTurnOnlyMoveTests {

    // MARK: - Fixtures

    private func incineroar(ability: String = "intimidate") -> PKMNStats {
        PKMNStats(id: 727, speciesID: 727, name: "Incineroar",
                  type1: "Fire", type2: "Dark",
                  baseHP: 95, baseAtk: 115, baseDef: 90,
                  baseSpAtk: 80, baseSpDef: 90, baseSpeed: 60,
                  ability1: ability)
    }

    private func rillaboom(ability: String = "grassy-surge") -> PKMNStats {
        PKMNStats(id: 812, speciesID: 812, name: "Rillaboom",
                  type1: "Grass",
                  baseHP: 100, baseAtk: 125, baseDef: 90,
                  baseSpAtk: 60, baseSpDef: 70, baseSpeed: 85,
                  ability1: ability)
    }

    private func chansey(ability: String = "natural-cure") -> PKMNStats {
        PKMNStats(id: 113, speciesID: 113, name: "Chansey",
                  type1: "Normal",
                  baseHP: 250, baseAtk: 5, baseDef: 5,
                  baseSpAtk: 35, baseSpDef: 105, baseSpeed: 50,
                  ability1: ability)
    }

    private func fakeOut() -> MoveData {
        MoveData(id: 252, name: "Fake Out", type: "Normal", damageClass: "physical",
                 power: 40, accuracy: 100, pp: 10, priority: 3,
                 minHits: nil, maxHits: nil, drain: 0, healing: 0,
                 critRate: 0, makesContact: true)
    }

    private func firstImpression() -> MoveData {
        MoveData(id: 660, name: "First Impression", type: "Bug", damageClass: "physical",
                 power: 90, accuracy: 100, pp: 10, priority: 2,
                 minHits: nil, maxHits: nil, drain: 0, healing: 0,
                 critRate: 0, makesContact: true)
    }

    private func tackle() -> MoveData {
        MoveData(id: 33, name: "Tackle", type: "Normal", damageClass: "physical",
                 power: 40, accuracy: 100, pp: 35, priority: 0,
                 minHits: nil, maxHits: nil, drain: 0, healing: 0,
                 critRate: 0, makesContact: true)
    }

    /// Earthquake — covers the spread-move dispatch path, which has its own
    /// counter bump separate from `performMove`.
    private func earthquake() -> MoveData {
        MoveData(id: 89, name: "Earthquake", type: "Ground", damageClass: "physical",
                 power: 100, accuracy: 100, pp: 10, priority: 0,
                 minHits: nil, maxHits: nil, drain: 0, healing: 0,
                 critRate: 0, makesContact: false)
    }

    private func slot(for p: PKMNStats, ability: String, moves: [MoveData]) -> TeamSlotInfo {
        TeamSlotInfo(
            spreadName: "fixture-\(p.name)",
            pokemonID: p.id, pokemonName: p.name,
            type1: p.type1, type2: p.type2,
            abilityName: ability,
            itemRawValue: nil,
            championsMode: false, natureID: "hardy", level: 50,
            evHP: 0, evAtk: 0, evDef: 0, evSpAtk: 0, evSpDef: 0, evSpeed: 0,
            moveSlots: moves.map {
                TeamMoveInfo(moveID: $0.id, moveName: $0.name, moveType: $0.type,
                             damageClass: $0.damageClass, power: $0.power, isSTAB: false)
            }
        )
    }

    private func engine(attacker: PKMNStats, attackerMoves: [MoveData],
                        attackerBench: [(PKMNStats, [MoveData])] = [],
                        defender: PKMNStats, defenderMoves: [MoveData])
        -> BattleEngine
    {
        let attackerSlots: [TeamSlotInfo] = [slot(for: attacker, ability: attacker.ability1!,
                                                  moves: attackerMoves)]
            + attackerBench.map { slot(for: $0.0, ability: $0.0.ability1!, moves: $0.1) }
        let defenderSlots = [slot(for: defender, ability: defender.ability1!,
                                  moves: defenderMoves)]
        let allPokemon = [attacker, defender] + attackerBench.map(\.0)
        let allMoves = attackerMoves + defenderMoves + attackerBench.flatMap(\.1)
        let s1 = BattleSide(label: "Side 1", slots: attackerSlots, format: .singles,
                            allPokemon: allPokemon, allMoves: allMoves)
        let s2 = BattleSide(label: "Side 2", slots: defenderSlots, format: .singles,
                            allPokemon: allPokemon, allMoves: allMoves)
        return BattleEngine(format: .singles, side1: s1, side2: s2,
                            allPokemon: allPokemon, allMoves: allMoves)
    }

    private func entryContains(_ log: [BattleLogEntry], _ substring: String) -> Bool {
        log.contains { $0.text.contains(substring) }
    }

    // MARK: - UI Predicate (`isFirstTurnOnlyMoveLockedOut`)

    @Test func firstTurnOnlyPredicateFalseOnFreshSwitchIn() {
        // The button must be enabled when the holder just walked in.
        let e = engine(attacker: incineroar(), attackerMoves: [fakeOut(), tackle()],
                       defender: chansey(), defenderMoves: [tackle()])
        let attacker = e.side1.active(at: 0)!
        #expect(attacker.movesUsedSinceSwitchIn == 0)
        #expect(!attacker.isFirstTurnOnlyMoveLockedOut(at: 0))
    }

    @Test func firstTurnOnlyPredicateFalseForNonRestrictedMoves() {
        // Tackle never locks out — the predicate is per-move, not per-Pokemon.
        let e = engine(attacker: incineroar(), attackerMoves: [fakeOut(), tackle()],
                       defender: chansey(), defenderMoves: [tackle()])
        let attacker = e.side1.active(at: 0)!
        attacker.movesUsedSinceSwitchIn = 5
        #expect(!attacker.isFirstTurnOnlyMoveLockedOut(at: 1),
                "Tackle should remain selectable regardless of how many moves the holder has used.")
    }

    @Test func firstTurnOnlyPredicateTrueAfterFirstMove() {
        // After the holder dispatches any move, Fake Out is locked.
        let e = engine(attacker: incineroar(), attackerMoves: [fakeOut(), tackle()],
                       defender: chansey(), defenderMoves: [tackle()])
        let attacker = e.side1.active(at: 0)!
        attacker.movesUsedSinceSwitchIn = 1
        #expect(attacker.isFirstTurnOnlyMoveLockedOut(at: 0),
                "Fake Out should be lockout-disabled once the holder has moved.")
    }

    @Test func firstImpressionUsesSamePredicate() {
        // First Impression follows the exact same restriction as Fake Out.
        let e = engine(attacker: incineroar(), attackerMoves: [firstImpression()],
                       defender: chansey(), defenderMoves: [tackle()])
        let attacker = e.side1.active(at: 0)!
        attacker.movesUsedSinceSwitchIn = 1
        #expect(attacker.isFirstTurnOnlyMoveLockedOut(at: 0))
    }

    // MARK: - First-Turn Success

    @Test func fakeOutSucceedsOnFirstTurnAndBumpsCounter() {
        let e = engine(attacker: incineroar(), attackerMoves: [fakeOut()],
                       defender: chansey(), defenderMoves: [tackle()])
        let attacker = e.side1.active(at: 0)!
        let defender = e.side2.active(at: 0)!
        let defenderStartHP = defender.currentHP

        e.setAction(side: 0, slot: 0,
                    action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e.setAction(side: 1, slot: 0,
                    action: .move(moveIndex: 0, targetSide: 0, targetSlot: 0))
        e.executeTurn()

        #expect(defender.currentHP < defenderStartHP,
                "Fake Out should have damaged Chansey on the first turn.")
        #expect(attacker.movesUsedSinceSwitchIn == 1)
        // Crucial: no "But it failed!" path exists anymore — neither success
        // nor block-via-Struggle should ever emit that string.
        #expect(!entryContains(e.log, "But it failed!"))
    }

    @Test func firstImpressionSucceedsOnFirstTurn() {
        let e = engine(attacker: incineroar(), attackerMoves: [firstImpression()],
                       defender: chansey(), defenderMoves: [tackle()])
        let defender = e.side2.active(at: 0)!
        let startHP = defender.currentHP

        e.setAction(side: 0, slot: 0,
                    action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e.setAction(side: 1, slot: 0,
                    action: .move(moveIndex: 0, targetSide: 0, targetSlot: 0))
        e.executeTurn()

        #expect(defender.currentHP < startHP)
        #expect(!entryContains(e.log, "But it failed!"))
    }

    // MARK: - Counter Sources

    @Test func spreadMoveBumpsCounter() {
        // Spread moves dispatch through a separate engine path. They must
        // still count as "the holder moved" — otherwise a Pokemon could
        // Earthquake on turn 1 and Fake Out on turn 2.
        let e = engine(attacker: incineroar(), attackerMoves: [earthquake(), fakeOut()],
                       defender: chansey(), defenderMoves: [tackle()])
        let attacker = e.side1.active(at: 0)!
        e.setAction(side: 0, slot: 0,
                    action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e.setAction(side: 1, slot: 0,
                    action: .move(moveIndex: 0, targetSide: 0, targetSlot: 0))
        e.executeTurn()

        #expect(attacker.movesUsedSinceSwitchIn >= 1,
                "Earthquake should still increment the first-turn-only counter.")
        #expect(attacker.isFirstTurnOnlyMoveLockedOut(at: 1),
                "Fake Out should be unselectable on turn 2 after a turn-1 Earthquake.")
    }

    // MARK: - Encore → Struggle Redirect

    @Test func encoreForcingLockedFakeOutStrugglesInstead() {
        // Set up the scenario: Incineroar has used Fake Out (counter ≥ 1),
        // and the defender has placed Encore on it — locking it into Fake
        // Out's index. Per canon, the engine swaps the forced Fake Out for
        // Struggle rather than logging "But it failed!".
        let e = engine(attacker: incineroar(),
                       attackerMoves: [fakeOut(), tackle()],
                       defender: chansey(), defenderMoves: [tackle()])
        let attacker = e.side1.active(at: 0)!
        // Simulate "already moved this stint" + Encore lock onto Fake Out.
        attacker.movesUsedSinceSwitchIn = 1
        attacker.encoreTurns = 3
        attacker.encoreLockedIndex = 0
        let ppBefore = attacker.pp[0]

        let logCountBefore = e.log.count
        e.setAction(side: 0, slot: 0,
                    action: .move(moveIndex: 1, targetSide: 1, targetSlot: 0))
        e.setAction(side: 1, slot: 0,
                    action: .move(moveIndex: 0, targetSide: 0, targetSlot: 0))
        e.executeTurn()

        let newEntries = Array(e.log[logCountBefore...])
        #expect(newEntries.contains(where: { $0.text.contains("can't use Fake Out") }),
                "Engine should announce that the locked move is unusable.")
        #expect(newEntries.contains(where: { $0.text.contains("used Struggle!") }),
                "Forced first-turn-only move should redirect to Struggle.")
        #expect(!newEntries.contains(where: { $0.text.contains("But it failed!") }),
                "No 'But it failed!' path should exist for first-turn-only moves anymore.")
        #expect(attacker.pp[0] == ppBefore,
                "Fake Out's PP must not be charged when the engine redirects to Struggle.")
    }

    // MARK: - Switch Cycle Re-Enables

    @Test func switchOutThroughResetVolatileClearsCounter() {
        let e = engine(attacker: incineroar(), attackerMoves: [fakeOut(), tackle()],
                       defender: chansey(), defenderMoves: [tackle()])
        let attacker = e.side1.active(at: 0)!
        attacker.movesUsedSinceSwitchIn = 5
        attacker.resetVolatile()
        #expect(attacker.movesUsedSinceSwitchIn == 0)
        #expect(!attacker.isFirstTurnOnlyMoveLockedOut(at: 0),
                "Predicate should track the counter — a 0 counter unlocks Fake Out.")
    }

    @Test func fakeOutReEnablesAfterFullSwitchCycle() {
        // Incineroar Fake Outs turn 1, pivots to Rillaboom turn 2, comes back
        // turn 3 — turn 4 Fake Out must work again. End-to-end coverage of
        // the switch-side counter reset.
        let e = engine(attacker: incineroar(),
                       attackerMoves: [fakeOut(), tackle()],
                       attackerBench: [(rillaboom(), [tackle()])],
                       defender: chansey(),
                       defenderMoves: [tackle()])
        let inci = e.side1.active(at: 0)!

        e.setAction(side: 0, slot: 0,
                    action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e.setAction(side: 1, slot: 0,
                    action: .move(moveIndex: 0, targetSide: 0, targetSlot: 0))
        e.executeTurn()
        #expect(inci.movesUsedSinceSwitchIn >= 1)
        #expect(inci.isFirstTurnOnlyMoveLockedOut(at: 0),
                "After turn 1 success, the predicate should report lockout.")

        // Switch out to Rillaboom.
        e.setAction(side: 0, slot: 0, action: .switchTo(benchIndex: 1))
        e.setAction(side: 1, slot: 0,
                    action: .move(moveIndex: 0, targetSide: 0, targetSlot: 0))
        e.executeTurn()
        #expect(inci.movesUsedSinceSwitchIn == 0,
                "Switching out should clear Incineroar's counter via resetVolatile.")

        // Switch back to Incineroar.
        e.setAction(side: 0, slot: 0, action: .switchTo(benchIndex: 0))
        e.setAction(side: 1, slot: 0,
                    action: .move(moveIndex: 0, targetSide: 0, targetSlot: 0))
        e.executeTurn()
        #expect(e.side1.active(at: 0)?.slot.pokemonName == "Incineroar")
        #expect(inci.movesUsedSinceSwitchIn == 0)
        #expect(!inci.isFirstTurnOnlyMoveLockedOut(at: 0),
                "Fresh switch-in means the predicate is false again.")

        // Turn 4 — Fake Out should land for real.
        let defender = e.side2.active(at: 0)!
        let hpBefore = defender.currentHP
        let logCountBefore = e.log.count
        e.setAction(side: 0, slot: 0,
                    action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e.setAction(side: 1, slot: 0,
                    action: .move(moveIndex: 0, targetSide: 0, targetSlot: 0))
        e.executeTurn()

        let newEntries = Array(e.log[logCountBefore...])
        #expect(!newEntries.contains(where: { $0.text.contains("can't use Fake Out") }))
        #expect(!newEntries.contains(where: { $0.text.contains("used Struggle!") }))
        #expect(defender.currentHP < hpBefore,
                "Re-armed Fake Out should damage Chansey again.")
    }
}
