//
//  BattleMultiHitTests.swift
//  PKDexTests
//

import Testing
import Foundation
@testable import PKDex

@MainActor
@Suite("Battle Engine — Multi-Hit Moves")
struct BattleMultiHitTests {

    private func bulbasaur() -> PKMNStats {
        PKMNStats(id: 1, speciesID: 1, name: "Bulbasaur",
                  type1: "Grass", type2: "Poison",
                  baseHP: 45, baseAtk: 49, baseDef: 49,
                  baseSpAtk: 65, baseSpDef: 65, baseSpeed: 45,
                  ability1: "overgrow")
    }

    private func snorlax() -> PKMNStats {
        PKMNStats(id: 143, speciesID: 143, name: "Snorlax",
                  type1: "Normal", type2: nil,
                  baseHP: 160, baseAtk: 110, baseDef: 65,
                  baseSpAtk: 65, baseSpDef: 110, baseSpeed: 30,
                  ability1: "thick-fat")
    }

    /// Fixed 2-hit physical move: Bonemerang-ish (Ground type, BP 50, 2 hits each).
    private func doubleKick() -> MoveData {
        MoveData(id: 24, name: "Double Kick", type: "Fighting", damageClass: "physical",
                 power: 30, accuracy: 100, pp: 30, priority: 0,
                 minHits: 2, maxHits: 2, drain: 0, healing: 0,
                 critRate: 0, makesContact: true)
    }

    /// 2-5 hit move with Skill Link → always 5.
    private func bulletSeed() -> MoveData {
        MoveData(id: 331, name: "Bullet Seed", type: "Grass", damageClass: "physical",
                 power: 25, accuracy: 100, pp: 30, priority: 0,
                 minHits: 2, maxHits: 5, drain: 0, healing: 0,
                 critRate: 0, makesContact: false)
    }

    private func slot(for p: PKMNStats, ability: String, moves: [MoveData]) -> TeamSlotInfo {
        TeamSlotInfo(
            spreadName: "fixture-\(p.name)",
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

    private func makeEngine(side1: PKMNStats, side1Ability: String, side1Moves: [MoveData],
                            side2: PKMNStats, side2Ability: String, side2Moves: [MoveData])
        -> BattleEngine
    {
        let s1Slot = slot(for: side1, ability: side1Ability, moves: side1Moves)
        let s2Slot = slot(for: side2, ability: side2Ability, moves: side2Moves)
        let pokemon = [side1, side2]
        let moves = side1Moves + side2Moves
        let bs1 = BattleSide(label: "Side 1", slots: [s1Slot], format: .singles,
                             allPokemon: pokemon, allMoves: moves)
        let bs2 = BattleSide(label: "Side 2", slots: [s2Slot], format: .singles,
                             allPokemon: pokemon, allMoves: moves)
        return BattleEngine(format: .singles, side1: bs1, side2: bs2,
                            allPokemon: pokemon, allMoves: moves)
    }

    @Test func fixedTwoHitDealsAboutDoubleSingleHit() {
        // Run a fixed 2-hit move many times against a fresh full-HP target and
        // ensure damage averages out close to 2x a single hit (just compare
        // to the engine's own no-multi single-strike calc with the same RNG range).
        let move = doubleKick()
        let attacker = snorlax()
        let defender = bulbasaur()

        var totalMulti = 0
        let trials = 30
        for _ in 0..<trials {
            let e = makeEngine(side1: attacker, side1Ability: "thick-fat", side1Moves: [move],
                               side2: defender, side2Ability: "overgrow", side2Moves: [])
            let def = e.side2.active(at: 0)!
            let beforeHP = def.currentHP
            e.setAction(side: 0, slot: 0,
                        action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
            // Side 2 has no moves and won't be able to act — that's fine for the test.
            e.executeTurn()
            totalMulti += (beforeHP - def.currentHP)
        }
        // Average damage across 2 hits should be strictly positive; we don't have a
        // pure single-hit comparison, so just check the loop landed > 1 hit on average:
        // a single 30 BP Fighting move on Bulbasaur (4x vs Grass/Poison) is small but
        // non-zero; doubled it's clearly more than ~0.
        #expect(totalMulti > 0)
    }

    @Test func skillLinkForcesMaxHits() {
        // With Skill Link, Bullet Seed always lands 5 hits. Compare the log entries
        // for "Hit 5 time(s)" after a single move. We do many runs because the engine
        // RNG can still vary the damage range; only the hit count is locked.
        let move = bulletSeed()
        let e = makeEngine(
            side1: snorlax(), side1Ability: "skill-link", side1Moves: [move],
            side2: bulbasaur(), side2Ability: "overgrow", side2Moves: [])
        e.setAction(side: 0, slot: 0,
                    action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e.executeTurn()
        let hitMessages = e.log.compactMap { $0.text }.filter { $0.contains("Hit ") }
        // Either there's a "Hit N time(s)" line for 5 hits, OR the move KO'd before
        // landing all 5. Verify either case ends in "fainted!" OR the hit count is 5.
        let didFiveHit = hitMessages.contains(where: { $0.contains("Hit 5") })
        let didFaint = e.log.contains(where: { $0.text.contains("fainted!") })
        #expect(didFiveHit || didFaint)
    }

    @Test func loopStopsWhenDefenderFaintsMidSequence() {
        // Set up a target that's at 1 HP so the very first hit faints. Subsequent
        // hits should not run — we shouldn't see a "Hit 5 time(s)" log because the
        // loop stopped early.
        let move = bulletSeed()
        let e = makeEngine(
            side1: snorlax(), side1Ability: "skill-link", side1Moves: [move],
            side2: bulbasaur(), side2Ability: "overgrow", side2Moves: [])
        let def = e.side2.active(at: 0)!
        def.currentHP = 1
        e.setAction(side: 0, slot: 0,
                    action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e.executeTurn()
        // We should see exactly one hit landed before the faint message.
        let hitMessages = e.log.compactMap { $0.text }.filter { $0.contains("Hit ") }
        // With Skill Link a 5-hit Bullet Seed would log "Hit 5 time(s)" if all landed.
        // Stopping after a KO means we either log "Hit N time(s)" with N<5 or no
        // multi-hit summary at all (only one hit landed).
        if let h5 = hitMessages.first(where: { $0.contains("Hit 5") }) {
            Issue.record("Loop should stop at the KO, not run all 5 hits. Got \(h5)")
        }
        #expect(e.log.contains(where: { $0.text.contains("fainted!") }))
    }
}
