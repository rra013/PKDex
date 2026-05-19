//
//  BattleEngineAbilityTests.swift
//  PKDexTests
//

import Testing
import Foundation
@testable import PKDex

@MainActor
@Suite("Battle Engine — On-Entry Abilities")
struct BattleEngineAbilityTests {

    // MARK: - Fixtures

    private func gyarados(ability: String) -> PKMNStats {
        PKMNStats(id: 130, speciesID: 130, name: "Gyarados",
                  type1: "Water", type2: "Flying",
                  baseHP: 95, baseAtk: 125, baseDef: 79,
                  baseSpAtk: 60, baseSpDef: 100, baseSpeed: 81,
                  ability1: ability)
    }

    private func bisharp(ability: String) -> PKMNStats {
        PKMNStats(id: 625, speciesID: 625, name: "Bisharp",
                  type1: "Dark", type2: "Steel",
                  baseHP: 65, baseAtk: 125, baseDef: 100,
                  baseSpAtk: 60, baseSpDef: 70, baseSpeed: 70,
                  ability1: ability)
    }

    private func milotic(ability: String) -> PKMNStats {
        PKMNStats(id: 350, speciesID: 350, name: "Milotic",
                  type1: "Water", type2: nil,
                  baseHP: 95, baseAtk: 60, baseDef: 79,
                  baseSpAtk: 100, baseSpDef: 125, baseSpeed: 81,
                  ability1: ability)
    }

    private func metagross(ability: String) -> PKMNStats {
        PKMNStats(id: 376, speciesID: 376, name: "Metagross",
                  type1: "Steel", type2: "Psychic",
                  baseHP: 80, baseAtk: 135, baseDef: 130,
                  baseSpAtk: 95, baseSpDef: 90, baseSpeed: 70,
                  ability1: ability)
    }

    private func krabby(ability: String) -> PKMNStats {
        // Hyper Cutter user.
        PKMNStats(id: 98, speciesID: 98, name: "Krabby",
                  type1: "Water", type2: nil,
                  baseHP: 30, baseAtk: 105, baseDef: 90,
                  baseSpAtk: 25, baseSpDef: 25, baseSpeed: 50,
                  ability1: ability)
    }

    private func slot(for p: PKMNStats, ability: String) -> TeamSlotInfo {
        TeamSlotInfo(
            spreadName: "fixture-\(p.name)",
            pokemonID: p.id, pokemonName: p.name,
            type1: p.type1, type2: p.type2,
            abilityName: ability, itemRawValue: nil,
            championsMode: false, natureID: "hardy", level: 50,
            evHP: 0, evAtk: 0, evDef: 0, evSpAtk: 0, evSpDef: 0, evSpeed: 0,
            moveSlots: []
        )
    }

    /// Builds a singles engine with one Pokemon on each side. The engine init fires
    /// initial send-outs and their on-entry abilities — exactly what we want to assert.
    private func makeEngine(side1: PKMNStats, side1Ability: String,
                            side2: PKMNStats, side2Ability: String) -> BattleEngine {
        let s1Slot = slot(for: side1, ability: side1Ability)
        let s2Slot = slot(for: side2, ability: side2Ability)
        let pokemon = [side1, side2]
        let bs1 = BattleSide(label: "Side 1", slots: [s1Slot], format: .singles,
                             allPokemon: pokemon, allMoves: [])
        let bs2 = BattleSide(label: "Side 2", slots: [s2Slot], format: .singles,
                             allPokemon: pokemon, allMoves: [])
        return BattleEngine(format: .singles, side1: bs1, side2: bs2,
                            allPokemon: pokemon, allMoves: [])
    }

    // MARK: - Intimidate

    @Test func intimidateLowersOpponentAttackOnSwitchIn() {
        let engine = makeEngine(
            side1: gyarados(ability: "intimidate"), side1Ability: "intimidate",
            side2: bisharp(ability: "pressure"),    side2Ability: "pressure")
        #expect(engine.side2.active(at: 0)?.atkStage == -1)
    }

    @Test func intimidateUnaffectedSideKeepsAttack() {
        let engine = makeEngine(
            side1: gyarados(ability: "intimidate"), side1Ability: "intimidate",
            side2: bisharp(ability: "pressure"),    side2Ability: "pressure")
        #expect(engine.side1.active(at: 0)?.atkStage == 0)
    }

    // MARK: - Reactive abilities

    @Test func defiantCountersIntimidate() {
        // -1 Atk from Intimidate, then +2 Atk from Defiant = net +1.
        let engine = makeEngine(
            side1: gyarados(ability: "intimidate"), side1Ability: "intimidate",
            side2: bisharp(ability: "defiant"),     side2Ability: "defiant")
        #expect(engine.side2.active(at: 0)?.atkStage == 1)
    }

    @Test func competitiveRaisesSpAtkAfterDrop() {
        // -1 Atk from Intimidate, then +2 SpA from Competitive (Atk stays -1).
        let engine = makeEngine(
            side1: gyarados(ability: "intimidate"), side1Ability: "intimidate",
            side2: milotic(ability: "competitive"), side2Ability: "competitive")
        #expect(engine.side2.active(at: 0)?.atkStage == -1)
        #expect(engine.side2.active(at: 0)?.spAtkStage == 2)
    }

    // MARK: - Stat-drop guards

    @Test func clearBodyBlocksIntimidate() {
        let engine = makeEngine(
            side1: gyarados(ability: "intimidate"),  side1Ability: "intimidate",
            side2: metagross(ability: "clear-body"), side2Ability: "clear-body")
        #expect(engine.side2.active(at: 0)?.atkStage == 0)
    }

    @Test func whiteSmokeBlocksIntimidate() {
        let engine = makeEngine(
            side1: gyarados(ability: "intimidate"),    side1Ability: "intimidate",
            side2: metagross(ability: "white-smoke"),  side2Ability: "white-smoke")
        #expect(engine.side2.active(at: 0)?.atkStage == 0)
    }

    @Test func hyperCutterBlocksAttackDrop() {
        let engine = makeEngine(
            side1: gyarados(ability: "intimidate"),  side1Ability: "intimidate",
            side2: krabby(ability: "hyper-cutter"),  side2Ability: "hyper-cutter")
        #expect(engine.side2.active(at: 0)?.atkStage == 0)
    }

    @Test func innerFocusShrugsOffIntimidate() {
        // Gen 8+ behavior: Inner Focus blocks Intimidate's Atk drop.
        let engine = makeEngine(
            side1: gyarados(ability: "intimidate"),   side1Ability: "intimidate",
            side2: bisharp(ability: "inner-focus"),   side2Ability: "inner-focus")
        #expect(engine.side2.active(at: 0)?.atkStage == 0)
    }
}
