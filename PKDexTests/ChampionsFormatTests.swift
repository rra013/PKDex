//
//  ChampionsFormatTests.swift
//  PKDexTests
//

import Testing
import Foundation
@testable import PKDex

@Suite("Champions Format — Slot Normalization")
struct ChampionsFormatNormalizerTests {

    private func mainSeriesSlot() -> TeamSlotInfo {
        TeamSlotInfo(
            spreadName: "test",
            pokemonID: 1, pokemonName: "Garchomp",
            type1: "Dragon", type2: "Ground",
            abilityName: "rough-skin", itemRawValue: "Life Orb",
            championsMode: false, natureID: "jolly", level: 100,
            evHP: 0, evAtk: 252, evDef: 4, evSpAtk: 0, evSpDef: 0, evSpeed: 252,
            moveSlots: []
        )
    }

    private func championsSlot() -> TeamSlotInfo {
        TeamSlotInfo(
            spreadName: "test",
            pokemonID: 1, pokemonName: "Garchomp",
            type1: "Dragon", type2: "Ground",
            abilityName: "rough-skin", itemRawValue: "Life Orb",
            championsMode: true, natureID: "jolly", level: 50,
            evHP: 0, evAtk: 32, evDef: 0, evSpAtk: 0, evSpDef: 2, evSpeed: 32,
            moveSlots: []
        )
    }

    @Test func normalizeForcesLevel50AndChampionsMode() {
        let n = ChampionsFormat.normalize(mainSeriesSlot())
        #expect(n.level == 50)
        #expect(n.championsMode == true)
    }

    @Test func normalizeConvertsMainSeriesEVsToChampionsScale() {
        let n = ChampionsFormat.normalize(mainSeriesSlot())
        // 252 → 32 (252*32/252), 4 → 0 (4*32/252 == 0 by floor division).
        #expect(n.evAtk == 32)
        #expect(n.evSpeed == 32)
        #expect(n.evHP == 0)
    }

    @Test func normalizedTotalNeverExceedsCap() {
        let n = ChampionsFormat.normalize(mainSeriesSlot())
        let total = n.evHP + n.evAtk + n.evDef + n.evSpAtk + n.evSpDef + n.evSpeed
        #expect(total <= championsMaxTotalEVs)
    }

    @Test func normalizeChampionsSlotLeavesEVsAlone() {
        let original = championsSlot()
        let n = ChampionsFormat.normalize(original)
        #expect(n.evAtk == original.evAtk)
        #expect(n.evSpeed == original.evSpeed)
        #expect(n.evSpDef == original.evSpDef)
        #expect(n.level == 50)
    }

    @Test func normalizeOverridesAlreadyLevel100MainSlotTo50() {
        var s = mainSeriesSlot()
        s.level = 100
        let n = ChampionsFormat.normalize(s)
        #expect(n.level == 50)
    }
}

@Suite("Champions Format — Validator Mapping")
struct ChampionsFormatMappingTests {

    private func slot(species: String, ability: String, item: String?,
                      moves: [String], nature: String = "jolly",
                      ev: (Int, Int, Int, Int, Int, Int) = (0, 32, 0, 0, 2, 32),
                      championsMode: Bool = true) -> TeamSlotInfo {
        TeamSlotInfo(
            spreadName: "test",
            pokemonID: 1, pokemonName: species,
            type1: "Normal", type2: nil,
            abilityName: ability, itemRawValue: item,
            championsMode: championsMode, natureID: nature, level: 50,
            evHP: ev.0, evAtk: ev.1, evDef: ev.2,
            evSpAtk: ev.3, evSpDef: ev.4, evSpeed: ev.5,
            moveSlots: moves.map {
                TeamMoveInfo(moveID: 0, moveName: $0, moveType: "Normal",
                             damageClass: "physical", power: 80, isSTAB: false)
            }
        )
    }

    @Test func pokemonSetMapsAbilityIdToDisplayName() {
        let s = slot(species: "Whatever", ability: "snow-warning",
                     item: "Leftovers", moves: [])
        let set = ChampionsFormat.pokemonSet(from: s)
        #expect(set.ability == "Snow Warning")
        #expect(set.item == "Leftovers")
    }

    @Test func pokemonSetMapsHyphenatedAbility() {
        let s = slot(species: "Whatever", ability: "rough-skin",
                     item: nil, moves: [])
        let set = ChampionsFormat.pokemonSet(from: s)
        #expect(set.ability == "Rough Skin")
    }

    @Test func pokemonSetCopiesMoveNamesAsDisplay() {
        let s = slot(species: "Whatever", ability: "rough-skin", item: nil,
                     moves: ["Earthquake", "Dragon Claw"])
        let set = ChampionsFormat.pokemonSet(from: s)
        #expect(set.moves == ["Earthquake", "Dragon Claw"])
    }

    @Test func pokemonSetReadsChampionsStatPointsDirectly() {
        // statPoints come straight from the slot when championsMode = true.
        let s = slot(species: "Whatever", ability: "rough-skin", item: nil,
                     moves: [], ev: (0, 32, 0, 0, 2, 32))
        let set = ChampionsFormat.pokemonSet(from: s)
        #expect(set.statPoints.atk == 32)
        #expect(set.statPoints.spd == 2)
        #expect(set.statPoints.spe == 32)
    }

    @Test func pokemonSetConvertsMainSeriesEVsToStatPoints() {
        // Main-series 252 → Champions 32 via the converter.
        let s = slot(species: "Whatever", ability: "rough-skin", item: nil,
                     moves: [], ev: (0, 252, 0, 0, 4, 252), championsMode: false)
        let set = ChampionsFormat.pokemonSet(from: s)
        #expect(set.statPoints.atk == 32)
        #expect(set.statPoints.spe == 32)
    }
}

@Suite("Champions Format — Validator Integration")
struct ChampionsFormatValidatorTests {

    private func legalGarchomp() -> TeamSlotInfo {
        TeamSlotInfo(
            spreadName: "test",
            pokemonID: 1, pokemonName: "Garchomp",
            type1: "Dragon", type2: "Ground",
            abilityName: "rough-skin", itemRawValue: nil,
            championsMode: true, natureID: "jolly", level: 50,
            evHP: 0, evAtk: 32, evDef: 0, evSpAtk: 0, evSpDef: 0, evSpeed: 32,
            moveSlots: []
        )
    }

    /// Skip the suite if the JSON resources aren't bundled in the test target.
    private func validatorOrSkip() -> ChampionsValidator? {
        ChampionsValidator()
    }

    @Test func overCapStatPointsTripStatPointsOverCap() {
        guard let v = validatorOrSkip() else { return }
        var legal = legalGarchomp()
        // Total = 68 > 66 cap.
        legal.evHP = 4; legal.evDef = 0; legal.evAtk = 32; legal.evSpDef = 0; legal.evSpeed = 32
        // Above is 68 total.
        let violations = ChampionsFormat.validate(slots: [legal, legal, legal, legal, legal, legal],
                                                  validator: v)
        let hits = violations.filter { $0.category == .statPointsOverCap }
        #expect(!hits.isEmpty,
                "Stat-point total over 66 must trigger statPointsOverCap")
    }

    @Test func wrongTeamSizeFires() {
        guard let v = validatorOrSkip() else { return }
        let one = legalGarchomp()
        let violations = ChampionsFormat.validate(slots: [one], validator: v)
        let hits = violations.filter { $0.category == .wrongTeamSize }
        #expect(!hits.isEmpty, "Validator must flag teams with size != 6")
    }
}
