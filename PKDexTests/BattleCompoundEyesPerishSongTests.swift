//
//  BattleCompoundEyesPerishSongTests.swift
//  PKDexTests
//
//  Compound Eyes accuracy multiplier and Perish Song countdown.
//

import Testing
import Foundation
@testable import PKDex

@MainActor
@Suite("Battle Engine — Compound Eyes Accuracy")
struct BattleCompoundEyesTests {

    private func butterfree(ability: String = "compound-eyes") -> PKMNStats {
        PKMNStats(id: 12, speciesID: 12, name: "Butterfree",
                  type1: "Bug", type2: "Flying",
                  baseHP: 60, baseAtk: 45, baseDef: 50,
                  baseSpAtk: 90, baseSpDef: 80, baseSpeed: 70,
                  ability1: ability)
    }

    private func chansey() -> PKMNStats {
        PKMNStats(id: 113, speciesID: 113, name: "Chansey",
                  type1: "Normal", type2: nil,
                  baseHP: 250, baseAtk: 5, baseDef: 5,
                  baseSpAtk: 35, baseSpDef: 105, baseSpeed: 50,
                  ability1: "natural-cure")
    }

    /// 50% accuracy move so the boost is testable — without Compound Eyes it
    /// resolves to 50 (misses ~half), with Compound Eyes 50 * 1.3 = 65.
    private func halfHitMove() -> MoveData {
        MoveData(id: 9000, name: "ProbeAcc", type: "Bug", damageClass: "special",
                 power: 40, accuracy: 50, pp: 30, priority: 0,
                 minHits: nil, maxHits: nil, drain: 0, healing: 0,
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

    private func engine(side1: PKMNStats, ab1: String, moves1: [MoveData],
                        side2: PKMNStats, ab2: String, moves2: [MoveData]) -> BattleEngine {
        let s1Slot = slot(for: side1, ability: ab1, moves: moves1)
        let s2Slot = slot(for: side2, ability: ab2, moves: moves2)
        let pokemon = [side1, side2]
        let moves = moves1 + moves2
        let bs1 = BattleSide(label: "Side 1", slots: [s1Slot], format: .singles,
                             allPokemon: pokemon, allMoves: moves)
        let bs2 = BattleSide(label: "Side 2", slots: [s2Slot], format: .singles,
                             allPokemon: pokemon, allMoves: moves)
        return BattleEngine(format: .singles, side1: bs1, side2: bs2,
                            allPokemon: pokemon, allMoves: moves)
    }

    /// Runs `trials` turns and reports the hit rate against a fresh defender on
    /// each turn (so misses don't accumulate). Resilient to RNG noise across
    /// runs — we sample enough to make the boost statistically observable.
    private func hitRate(attackerAbility: String, trials: Int = 400) -> Double {
        var hits = 0
        let move = halfHitMove()
        for _ in 0..<trials {
            let e = engine(side1: butterfree(ability: attackerAbility),
                           ab1: attackerAbility, moves1: [move],
                           side2: chansey(), ab2: "natural-cure", moves2: [])
            let def = e.side2.active(at: 0)!
            let before = def.currentHP
            e.setAction(side: 0, slot: 0,
                        action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
            e.executeTurn()
            if def.currentHP < before { hits += 1 }
        }
        return Double(hits) / Double(trials)
    }

    @Test func compoundEyesLandsMoreThanBaseline() {
        // Sanity: with Compound Eyes the hit rate should be visibly higher than
        // without. Expected: ~50% without, ~65% with. Allow generous slack so
        // RNG noise doesn't flake the suite.
        let withCE = hitRate(attackerAbility: "compound-eyes", trials: 200)
        let withoutCE = hitRate(attackerAbility: "shield-dust", trials: 200)
        #expect(withCE > withoutCE + 0.05,
                "Compound Eyes (\(withCE)) should beat baseline (\(withoutCE)) by >5pp")
    }

    @Test func compoundEyesTurns100AccuracyEffectivelyPerfect() {
        // 100-acc move + 1.3x = 130, capped only by the random roll's 100 max
        // — so every shot should land. Run many turns to be sure.
        let perfect = MoveData(id: 9001, name: "ProbeSure", type: "Bug",
                               damageClass: "special",
                               power: 40, accuracy: 100, pp: 30, priority: 0,
                               minHits: nil, maxHits: nil, drain: 0, healing: 0,
                               critRate: 0, makesContact: false)
        for _ in 0..<50 {
            let e = engine(side1: butterfree(), ab1: "compound-eyes", moves1: [perfect],
                           side2: chansey(), ab2: "natural-cure", moves2: [])
            let def = e.side2.active(at: 0)!
            let before = def.currentHP
            e.setAction(side: 0, slot: 0,
                        action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
            e.executeTurn()
            #expect(def.currentHP < before, "100-acc move with Compound Eyes must always hit")
        }
    }
}

@MainActor
@Suite("Battle Engine — Perish Song")
struct BattlePerishSongTests {

    private func clefable() -> PKMNStats {
        PKMNStats(id: 36, speciesID: 36, name: "Clefable",
                  type1: "Fairy", type2: nil,
                  baseHP: 95, baseAtk: 70, baseDef: 73,
                  baseSpAtk: 95, baseSpDef: 90, baseSpeed: 60,
                  ability1: "magic-guard")
    }

    private func snorlax(ability: String = "thick-fat") -> PKMNStats {
        PKMNStats(id: 143, speciesID: 143, name: "Snorlax",
                  type1: "Normal", type2: nil,
                  baseHP: 160, baseAtk: 110, baseDef: 65,
                  baseSpAtk: 65, baseSpDef: 110, baseSpeed: 30,
                  ability1: ability)
    }

    private func perishSong() -> MoveData {
        MoveData(id: 195, name: "Perish Song", type: "Normal", damageClass: "status",
                 power: nil, accuracy: nil, pp: 5, priority: 0,
                 minHits: nil, maxHits: nil, drain: 0, healing: 0,
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

    private func engine(side1: PKMNStats, ab1: String, moves1: [MoveData],
                        side2: PKMNStats, ab2: String, moves2: [MoveData]) -> BattleEngine {
        let s1Slot = slot(for: side1, ability: ab1, moves: moves1)
        let s2Slot = slot(for: side2, ability: ab2, moves: moves2)
        let pokemon = [side1, side2]
        let moves = moves1 + moves2
        let bs1 = BattleSide(label: "Side 1", slots: [s1Slot], format: .singles,
                             allPokemon: pokemon, allMoves: moves)
        let bs2 = BattleSide(label: "Side 2", slots: [s2Slot], format: .singles,
                             allPokemon: pokemon, allMoves: moves)
        return BattleEngine(format: .singles, side1: bs1, side2: bs2,
                            allPokemon: pokemon, allMoves: moves)
    }

    @Test func perishSongSetsCounterOnEveryActive() {
        let e = engine(side1: clefable(), ab1: "magic-guard", moves1: [perishSong()],
                       side2: snorlax(), ab2: "thick-fat", moves2: [])
        e.setAction(side: 0, slot: 0,
                    action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e.executeTurn()
        // After the move + end-of-turn tick: both sides should have counter 2.
        // (Set to 3 by the move, ticked down to 2 at end of turn.)
        #expect(e.side1.active(at: 0)?.perishCounter == 2)
        #expect(e.side2.active(at: 0)?.perishCounter == 2)
    }

    @Test func perishSongFaintsBothSidesOnThirdEndOfTurn() {
        let e = engine(side1: clefable(), ab1: "magic-guard", moves1: [perishSong()],
                       side2: snorlax(), ab2: "thick-fat", moves2: [])
        e.setAction(side: 0, slot: 0,
                    action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e.executeTurn()  // counter 3 → 2
        e.executeTurn()  // counter 2 → 1
        e.executeTurn()  // counter 1 → 0, both should faint
        #expect(e.side1.active(at: 0)?.fainted == true)
        #expect(e.side2.active(at: 0)?.fainted == true)
    }

    @Test func soundproofBlocksPerishSong() {
        let e = engine(side1: clefable(), ab1: "magic-guard", moves1: [perishSong()],
                       side2: snorlax(ability: "soundproof"), ab2: "soundproof", moves2: [])
        e.setAction(side: 0, slot: 0,
                    action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e.executeTurn()
        // Clefable still gets perished (it hears its own song); Snorlax doesn't.
        #expect(e.side1.active(at: 0)?.perishCounter == 2)
        #expect(e.side2.active(at: 0)?.perishCounter == 0)
    }

    @Test func switchOutClearsPerishCounter() {
        let e = engine(side1: clefable(), ab1: "magic-guard", moves1: [perishSong()],
                       side2: snorlax(), ab2: "thick-fat", moves2: [])
        let target = e.side2.active(at: 0)!
        target.perishCounter = 1
        target.resetVolatile()
        #expect(target.perishCounter == 0, "Switching must clear the perish counter")
    }
}
