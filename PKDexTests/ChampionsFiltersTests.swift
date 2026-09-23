//
//  ChampionsFiltersTests.swift
//  PKDexTests
//
//  Covers the `ChampionsFilters` predicate that drives the Mon Index filter
//  chip strip. Type matching is exercised against synthetic `PKMNStats`
//  fixtures so the suite stays hermetic. Ability and move matching go through
//  `ChampionsLearnsetStore`, which reads `champions-m-a-learnsets.json` from
//  the bundle — the suite skips with a printed note when that JSON isn't
//  bundled (matching the convention in `PokiiParityTests`).
//

import Testing
import Foundation
@testable import PKDex

@MainActor
@Suite("Champions Mon Index — Filter Predicate")
struct ChampionsFiltersTests {

    // MARK: - Synthetic Fixtures

    /// Convenience for a `PKMNStats` that only fills in the fields the type
    /// filter looks at. Other fields take harmless defaults so we don't have
    /// to maintain wide call sites for unrelated stats.
    private static func makeForm(id: Int, speciesID: Int, name: String,
                                 type1: String, type2: String? = nil,
                                 isForm: Bool = false) -> PKMNStats {
        PKMNStats(
            id: id, speciesID: speciesID,
            name: name,
            formName: isForm ? "mega" : nil,
            type1: type1, type2: type2,
            baseHP: 1, baseAtk: 1, baseDef: 1,
            baseSpAtk: 1, baseSpDef: 1, baseSpeed: 1
        )
    }

    /// Base Charizard plus Mega-X (Fire/Dragon) and Mega-Y (Fire/Flying) so
    /// tests can verify the "any form satisfies" rule across megas without
    /// touching SwiftData or the live PKMNStats query.
    private static func charizardForms() -> [PKMNStats] {
        [
            makeForm(id: 6,     speciesID: 6, name: "Charizard",        type1: "Fire", type2: "Flying"),
            makeForm(id: 10034, speciesID: 6, name: "Charizard-Mega-X", type1: "Fire", type2: "Dragon", isForm: true),
            makeForm(id: 10035, speciesID: 6, name: "Charizard-Mega-Y", type1: "Fire", type2: "Flying", isForm: true),
        ]
    }

    /// Single base form, no megas. Used as the "no-form-satisfies" foil.
    private static func bulbasaurForms() -> [PKMNStats] {
        [makeForm(id: 1, speciesID: 1, name: "Bulbasaur", type1: "Grass", type2: "Poison")]
    }

    // MARK: - State

    @Test func emptyFilters_isInactive_andCountsZero() {
        let f = ChampionsFilters.none
        #expect(!f.isActive)
        #expect(f.activeCount == 0)
        #expect(f.requiredTypes.isEmpty)
    }

    @Test func singleTypeSet_isActiveAndCountsOne() {
        var f = ChampionsFilters.none
        f.type1 = "Fire"
        #expect(f.isActive)
        #expect(f.activeCount == 1)
        #expect(f.requiredTypes == ["Fire"])
    }

    @Test func dualTypeSet_isActiveAndCountsTwo() {
        var f = ChampionsFilters.none
        f.type1 = "Grass"
        f.type2 = "Fire"
        #expect(f.isActive)
        #expect(f.activeCount == 2)
        #expect(f.requiredTypes == ["Grass", "Fire"])
    }

    @Test func duplicateTypeSlots_collapseToOneRequirement() {
        // If the user accidentally picks Fire in both slots, the predicate
        // should behave like a single-type Fire filter, not require "Fire +
        // Fire" (which would still work, but it's nicer to dedupe explicitly).
        var f = ChampionsFilters.none
        f.type1 = "Fire"
        f.type2 = "Fire"
        #expect(f.requiredTypes == ["Fire"])
    }

    @Test func mixedFilters_countActiveSlots() {
        var f = ChampionsFilters.none
        f.type1 = "Fire"
        f.type2 = "Dragon"
        f.ability = "Blaze"
        f.move = "Flamethrower"
        #expect(f.activeCount == 4)
    }

    // MARK: - Type Matching

    @Test func noFilter_matchesEverything() {
        let f = ChampionsFilters.none
        #expect(f.matches(speciesName: "Charizard", formStats: Self.charizardForms()))
        #expect(f.matches(speciesName: "Bulbasaur", formStats: Self.bulbasaurForms()))
        // Empty form stats should also pass when the filter is inactive.
        #expect(f.matches(speciesName: "Mystery", formStats: []))
    }

    @Test func singleType_matchesFirstSlotType() {
        var f = ChampionsFilters.none
        f.type1 = "Fire"
        #expect(f.matches(speciesName: "Charizard", formStats: Self.charizardForms()))
    }

    @Test func singleType_matchesSecondSlotType() {
        // Bulbasaur's Poison lives in `type2`. The filter must check both
        // slots, otherwise this would silently miss every Pokémon whose
        // secondary type the user filters on.
        var f = ChampionsFilters.none
        f.type1 = "Poison"
        #expect(f.matches(speciesName: "Bulbasaur", formStats: Self.bulbasaurForms()))
    }

    @Test func singleType_failsWhenTypeAbsent() {
        var f = ChampionsFilters.none
        f.type1 = "Ghost"
        #expect(!f.matches(speciesName: "Charizard", formStats: Self.charizardForms()))
    }

    @Test func dualType_matchesWhenBothPresentOnSameForm() {
        // Mega Charizard X is Fire/Dragon — picking Fire + Dragon must surface
        // Charizard because of that mega, even though the *base* form is
        // Fire/Flying.
        var f = ChampionsFilters.none
        f.type1 = "Fire"
        f.type2 = "Dragon"
        #expect(f.matches(speciesName: "Charizard", formStats: Self.charizardForms()))
    }

    @Test func dualType_orderIndependent() {
        var firstThenSecond = ChampionsFilters.none
        firstThenSecond.type1 = "Fire"
        firstThenSecond.type2 = "Dragon"

        var secondThenFirst = ChampionsFilters.none
        secondThenFirst.type1 = "Dragon"
        secondThenFirst.type2 = "Fire"

        let forms = Self.charizardForms()
        #expect(firstThenSecond.matches(speciesName: "Charizard", formStats: forms))
        #expect(secondThenFirst.matches(speciesName: "Charizard", formStats: forms))
    }

    @Test func dualType_failsWhenOnlyOneTypePresent() {
        // Bulbasaur is Grass/Poison. Filtering Grass + Fire requires *both*
        // on the same form — Grass alone isn't enough.
        var f = ChampionsFilters.none
        f.type1 = "Grass"
        f.type2 = "Fire"
        #expect(!f.matches(speciesName: "Bulbasaur", formStats: Self.bulbasaurForms()))
    }

    @Test func dualType_failsWhenNeitherFormSatisfies() {
        // None of Charizard's three forms is Fire/Ghost.
        var f = ChampionsFilters.none
        f.type1 = "Fire"
        f.type2 = "Ghost"
        #expect(!f.matches(speciesName: "Charizard", formStats: Self.charizardForms()))
    }

    @Test func dualType_eachTypeOnDifferentFormStillFails() {
        // Form A is Fire/Water, Form B is Grass/Ice. Filter is Fire + Grass:
        // both types exist on the species across forms, but no *single* form
        // has both. The predicate must reject — otherwise we'd surface a
        // species the user can't actually run with that typing.
        let forms = [
            Self.makeForm(id: 1, speciesID: 1, name: "Synthetic", type1: "Fire",  type2: "Water"),
            Self.makeForm(id: 2, speciesID: 1, name: "Synthetic-Mega", type1: "Grass", type2: "Ice", isForm: true),
        ]
        var f = ChampionsFilters.none
        f.type1 = "Fire"
        f.type2 = "Grass"
        #expect(!f.matches(speciesName: "Synthetic", formStats: forms))
    }

    @Test func type_failsWithNoFormStats() {
        // When the lookup has no PKMNStats for the species (e.g. the entry
        // hasn't synced yet), a type filter must reject rather than letting
        // the row through — otherwise the chip lies about what it shows.
        var f = ChampionsFilters.none
        f.type1 = "Fire"
        #expect(!f.matches(speciesName: "Charizard", formStats: []))
    }

    // MARK: - Ability / Move Matching (uses bundled Champions JSON)

    @Test func ability_matchesBaseAbilityFromJSON() {
        // Verify against the live store so the test moves in lockstep with
        // the bundled regulation data — no hardcoded ability list to drift.
        guard let species = ChampionsLearnsetStore.shared.data(for: "Charizard"),
              let firstAbility = species.abilities.first else {
            print("[Filters] Champions JSON not bundled — skipping ability test.")
            return
        }
        var f = ChampionsFilters.none
        f.ability = firstAbility
        #expect(f.matches(speciesName: "Charizard", formStats: Self.charizardForms()))
    }

    @Test func ability_matchesMegaAbilityNotOnBaseForm() {
        // Tough Claws lives on Mega Charizard X, not on base Charizard. The
        // filter has to inspect mega abilities too — this was the explicit
        // contract behind "match across forms".
        guard let species = ChampionsLearnsetStore.shared.data(for: "Charizard"),
              let megaAbility = species.megas.first?.abilities.first else {
            print("[Filters] Champions JSON not bundled — skipping mega-ability test.")
            return
        }
        var f = ChampionsFilters.none
        f.ability = megaAbility
        #expect(f.matches(speciesName: "Charizard", formStats: Self.charizardForms()),
                "Mega ability '\(megaAbility)' must be reachable through the base species filter.")
    }

    @Test func ability_failsWhenAbsent() {
        // Pick a synthetic placeholder that no species would carry, sourced
        // from the same string-pool so it's never a stale name.
        var f = ChampionsFilters.none
        f.ability = "NotAnAbility-\(UUID().uuidString)"
        #expect(!f.matches(speciesName: "Charizard", formStats: Self.charizardForms()))
    }

    @Test func ability_failsWhenSpeciesNotInChampionsJSON() {
        // ChampionsLearnsetStore returns nil for off-regulation species, so
        // any ability filter on them must fail closed.
        var f = ChampionsFilters.none
        f.ability = "Blaze"
        #expect(!f.matches(speciesName: "SpeciesThatDoesNotExistInChampionsJSON",
                           formStats: []))
    }

    @Test func move_matchesBaseLearnsetEntry() {
        guard let species = ChampionsLearnsetStore.shared.data(for: "Charizard"),
              let firstMove = species.moves.first else {
            print("[Filters] Champions JSON not bundled — skipping move test.")
            return
        }
        var f = ChampionsFilters.none
        f.move = firstMove
        #expect(f.matches(speciesName: "Charizard", formStats: Self.charizardForms()))
    }

    @Test func move_failsWhenAbsent() {
        var f = ChampionsFilters.none
        f.move = "NotAMove-\(UUID().uuidString)"
        #expect(!f.matches(speciesName: "Charizard", formStats: Self.charizardForms()))
    }

    @Test func move_failsWhenSpeciesNotInChampionsJSON() {
        var f = ChampionsFilters.none
        f.move = "Flamethrower"
        #expect(!f.matches(speciesName: "SpeciesThatDoesNotExistInChampionsJSON",
                           formStats: []))
    }

    // MARK: - Combined Filters

    @Test func combinedFilters_allMustPass() {
        // Pull a known-good ability/move pair from the live store, then add a
        // type filter that the synthetic Charizard forms satisfy. All three
        // need to agree before the predicate accepts.
        guard let species = ChampionsLearnsetStore.shared.data(for: "Charizard"),
              let ability = species.abilities.first,
              let move = species.moves.first else {
            print("[Filters] Champions JSON not bundled — skipping combined test.")
            return
        }
        var f = ChampionsFilters.none
        f.type1 = "Fire"
        f.ability = ability
        f.move = move
        #expect(f.matches(speciesName: "Charizard", formStats: Self.charizardForms()))
    }

    @Test func combinedFilters_oneFailingClauseRejects() {
        // Same set-up, but flip the type to something Charizard never gets.
        // A single failure must reject the row even when ability and move
        // would both have matched on their own.
        guard let species = ChampionsLearnsetStore.shared.data(for: "Charizard"),
              let ability = species.abilities.first,
              let move = species.moves.first else {
            print("[Filters] Champions JSON not bundled — skipping rejection test.")
            return
        }
        var f = ChampionsFilters.none
        f.type1 = "Ghost"
        f.ability = ability
        f.move = move
        #expect(!f.matches(speciesName: "Charizard", formStats: Self.charizardForms()))
    }

    // MARK: - Filter Option Sourcing

    @Test func availableAbilities_isNonEmptyWhenBundleHasJSON() {
        let abilities = ChampionsFilterOptions.availableAbilities()
        // We can't assert against a specific count (the regulation can
        // shrink/grow), but we can demand the list isn't empty when the
        // store has data, and that it's sorted by display name.
        guard !abilities.isEmpty else {
            print("[Filters] Champions JSON not bundled — skipping availableAbilities test.")
            return
        }
        let displayNames = abilities.map { formatAbilityName($0) }
        #expect(displayNames == displayNames.sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        })
    }

    @Test func availableMoves_isNonEmptyWhenBundleHasJSON() {
        let moves = ChampionsFilterOptions.availableMoves()
        guard !moves.isEmpty else {
            print("[Filters] Champions JSON not bundled — skipping availableMoves test.")
            return
        }
        #expect(moves == moves.sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        })
    }
}
