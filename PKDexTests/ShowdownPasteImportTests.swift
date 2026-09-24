//
//  ShowdownPasteImportTests.swift
//  PKDexTests
//
//  Covers the bridge in `ShowdownPasteImport.swift`: name resolution across
//  the app's three naming conventions, EV scale conversion into the target
//  scale, issue reporting, and the mappings out to `PokemonSet` /
//  `SavedSpread` / `TeamSlotInfo`.
//
//  Hermetic: synthetic `PKMNStats` / `MoveData` fixtures (the same approach
//  as `ChampionsFiltersTests`) and `validator: nil`, so nothing depends on
//  SwiftData or the bundled legality JSON. Validator wiring is exercised
//  separately in the suite at the bottom, which skips when the JSON isn't
//  bundled.
//

import Testing
import Foundation
@testable import PKDex

@MainActor
@Suite("Showdown Paste — Import Bridge")
struct ShowdownPasteImportTests {

    // MARK: - Fixtures

    /// `PKMNStats.name` follows PokeAPI slugs run through `formatPokemonName`:
    /// hyphen-joined and capitalized. That's why these read "Mr-Rime" and
    /// "Charizard-Mega-X" rather than the prettier forms a paste would use.
    private static func makePokemon(
        id: Int, name: String, type1: String, type2: String? = nil,
        ability1: String? = nil, ability2: String? = nil, hidden: String? = nil
    ) -> PKMNStats {
        PKMNStats(
            id: id, speciesID: id, name: name, formName: nil,
            type1: type1, type2: type2,
            baseHP: 80, baseAtk: 100, baseDef: 90,
            baseSpAtk: 110, baseSpDef: 95, baseSpeed: 120,
            ability1: ability1, ability2: ability2, hiddenAbility: hidden
        )
    }

    /// `MoveData.name` is space-joined capitalized ("Fake Out", "U Turn").
    private static func makeMove(
        id: Int, name: String, type: String, damageClass: String = "physical",
        power: Int? = 80
    ) -> MoveData {
        MoveData(
            id: id, name: name, type: type, damageClass: damageClass,
            power: power, accuracy: 100, pp: 15, priority: 0,
            minHits: nil, maxHits: nil, drain: 0, healing: 0, critRate: 0,
            makesContact: true, generationId: 9
        )
    }

    private static var pokedex: [PKMNStats] {
        [
            makePokemon(id: 727, name: "Incineroar", type1: "Fire", type2: "Dark",
                        ability1: "blaze", hidden: "intimidate"),
            makePokemon(id: 866, name: "Mr-Rime", type1: "Ice", type2: "Psychic",
                        ability1: "tangled-feet", hidden: "ice-body"),
            makePokemon(id: 10034, name: "Charizard-Mega-X", type1: "Fire",
                        type2: "Dragon", ability1: "tough-claws"),
            makePokemon(id: 892, name: "Urshifu-Rapid-Strike", type1: "Fighting",
                        type2: "Water", ability1: "unseen-fist"),
            makePokemon(id: 670, name: "Floette-Eternal", type1: "Fairy",
                        ability1: "flower-veil"),
        ]
    }

    private static var moves: [MoveData] {
        [
            makeMove(id: 252, name: "Fake Out", type: "Normal", power: 40),
            makeMove(id: 369, name: "U Turn", type: "Bug", power: 70),
            makeMove(id: 182, name: "Protect", type: "Normal",
                     damageClass: "status", power: nil),
            makeMove(id: 394, name: "Flare Blitz", type: "Fire", power: 120),
        ]
    }

    private static func importer(
        targetScale: StatScale = .champions
    ) -> PasteImporter {
        PasteImporter(allPokemon: pokedex, allMoves: moves,
                      validator: nil, targetScale: targetScale)
    }

    private static func preview(
        _ paste: String, targetScale: StatScale = .champions,
        forcedScale: StatScale? = nil
    ) -> ImportPreview {
        importer(targetScale: targetScale)
            .preview(ShowdownPaste.parse(paste, forcedScale: forcedScale))
    }

    // MARK: - Species resolution

    @Test("A plain species resolves to its Pokedex row")
    func resolvesSpecies() throws {
        let preview = Self.preview("Incineroar @ Safety Goggles\nAbility: Intimidate")
        let slot = try #require(preview.slots.first)
        #expect(slot.pokemon?.id == 727)
        #expect(slot.isBlocked == false)
    }

    @Test("Punctuation differences don't matter")
    func resolvesAcrossPunctuation() throws {
        // Paste says "Mr. Rime"; the Pokedex row is "Mr-Rime".
        let slot = try #require(Self.preview("Mr. Rime @ Leftovers").slots.first)
        #expect(slot.pokemon?.name == "Mr-Rime")
    }

    @Test("Word order doesn't matter for Mega forms")
    func resolvesMegaWordOrder() throws {
        // The token-set fallback is what makes these equivalent.
        for written in ["Charizard-Mega-X", "Mega Charizard X", "charizard mega x"] {
            let slot = try #require(Self.preview("\(written) @ Charizardite X").slots.first)
            #expect(slot.pokemon?.id == 10034, "failed for \"\(written)\"")
        }
    }

    @Test("Form aliases resolve through the tournament alias table")
    func resolvesViaAliasTable() throws {
        // "Floette" alone means the Eternal Flower form in Champions.
        let slot = try #require(Self.preview("Floette @ Life Orb").slots.first)
        #expect(slot.pokemon?.name == "Floette-Eternal")
    }

    @Test("An unknown species blocks just that slot and suggests a fix")
    func unknownSpeciesBlocksOneSlot() throws {
        let preview = Self.preview("""
        Incinroar @ Safety Goggles

        Incineroar @ Sitrus Berry
        """)
        #expect(preview.slots.count == 2)

        let bad = try #require(preview.slots.first)
        #expect(bad.isBlocked)
        #expect(bad.issues.contains { $0.isBlocking })
        // One transposed character should still suggest the real name.
        #expect(bad.issues.contains {
            if case .speciesUnresolved(_, let suggestion) = $0 {
                return suggestion == "Incineroar"
            }
            return false
        })

        #expect(preview.slots[1].isBlocked == false)
        #expect(preview.importableSlots.count == 1)
        #expect(preview.blockedCount == 1)
        #expect(preview.isImportable)
    }

    @Test("A species too far from anything gets no suggestion")
    func noSuggestionWhenFarOff() throws {
        let slot = try #require(Self.preview("Qwilfishzzz").slots.first)
        #expect(slot.issues.contains {
            if case .speciesUnresolved(_, let suggestion) = $0 { return suggestion == nil }
            return false
        })
    }

    // MARK: - Moves, items, abilities, natures

    @Test("Move names resolve across spelling conventions")
    func resolvesMoves() throws {
        // "U-turn" in the paste, "U Turn" in the Pokedex.
        let slot = try #require(Self.preview("""
        Incineroar @ Safety Goggles
        - Fake Out
        - U-turn
        - Protect
        """).slots.first)
        #expect(slot.moves[0]?.id == 252)
        #expect(slot.moves[1]?.id == 369)
        #expect(slot.moves[2]?.id == 182)
        #expect(slot.moves[3] == nil)      // always padded to four slots
        #expect(slot.issues.isEmpty == false)  // level + nature defaults
        #expect(slot.issues.contains { if case .moveUnresolved = $0 { return true }; return false } == false)
    }

    @Test("An unknown move is reported with its slot index and a suggestion")
    func unknownMove() throws {
        let slot = try #require(Self.preview("""
        Incineroar
        - Fake Out
        - Flare Blits
        """).slots.first)
        #expect(slot.moves[1] == nil)
        #expect(slot.isBlocked == false)   // a bad move never blocks import
        #expect(slot.issues.contains {
            if case .moveUnresolved(let index, _, let suggestion) = $0 {
                return index == 1 && suggestion == "Flare Blitz"
            }
            return false
        })
    }

    @Test("A modelled item maps onto HeldItem")
    func resolvesItem() throws {
        let slot = try #require(Self.preview("Incineroar @ Choice Band").slots.first)
        #expect(slot.item == .choiceBand)
    }

    @Test("An unmodelled item is flagged but kept in the source text")
    func unmodelledItem() throws {
        // `HeldItem` covers every Champions-legal item, but not the wider
        // mainline pool — and a mainline VGC paste (the common import case)
        // is full of items like this one. The text has to survive so export
        // round-trips even though the calc can't model the effect.
        let slot = try #require(Self.preview("Incineroar @ Covert Cloak").slots.first)
        #expect(slot.item == .none)
        #expect(slot.issues.contains { $0 == .itemUnrecognized(raw: "Covert Cloak") })
        #expect(slot.source.item == "Covert Cloak")
    }

    @Test("An unmodelled item still round-trips on export")
    func unmodelledItemSurvivesExport() throws {
        let slot = try #require(Self.preview("Incineroar @ Covert Cloak").slots.first)
        let text = slot.exportSet(evsAreIn: .champions).showdownText()
        #expect(text.contains("Incineroar @ Covert Cloak"))
    }

    @Test("An unmodelled item is saved as text on the spread and team slot")
    func unmodelledItemIsSaved() throws {
        // Air Balloon is Champions-legal but not a `HeldItem`. It used to be
        // dropped on save, despite the issue saying "kept as text".
        let importer = Self.importer()
        let preview = importer.preview(ShowdownPaste.parse("Incineroar @ Air Balloon"))
        let slot = try #require(preview.slots.first)
        #expect(slot.itemText == "Air Balloon")
        #expect(importer.savedSpread(for: slot, name: "x")?.itemRawValue == "Air Balloon")
        #expect(importer.teamSlot(for: slot, spreadName: "x")?.itemRawValue == "Air Balloon")
    }

    @Test("No item saves as no item")
    func noItemSavesNil() throws {
        let importer = Self.importer()
        let slot = try #require(importer.preview(ShowdownPaste.parse("Incineroar")).slots.first)
        #expect(slot.itemText == nil)
        #expect(importer.savedSpread(for: slot, name: "x")?.itemRawValue == nil)
    }

    @Test("The synthetic type-boost bucket never wins a lookup")
    func typeBoostIsNotMatchable() throws {
        let slot = try #require(Self.preview("Incineroar @ Type-Boost (1.2x)").slots.first)
        #expect(slot.item == .none)
    }

    @Test("Abilities resolve to the app's hyphenated convention")
    func resolvesAbility() throws {
        let slot = try #require(Self.preview("""
        Incineroar @ Sitrus Berry
        Ability: Intimidate
        """).slots.first)
        #expect(slot.ability == "intimidate")
    }

    @Test("A missing nature defaults to neutral, not Adamant")
    func natureDefaultsToNeutral() throws {
        // SavedSpread's own default is "adamant", which would silently hand
        // the set a +Atk/-SpA spread it never asked for.
        let slot = try #require(Self.preview("Incineroar @ Sitrus Berry").slots.first)
        #expect(slot.nature.id == "serious")
        #expect(slot.nature.boosted == nil)
        #expect(slot.issues.contains { $0 == .natureDefaulted })
    }

    @Test("A stated nature is used")
    func natureIsParsed() throws {
        let slot = try #require(Self.preview("Incineroar\nAdamant Nature").slots.first)
        #expect(slot.nature.id == "adamant")
        #expect(slot.issues.contains { $0 == .natureDefaulted } == false)
    }

    @Test("A missing level defaults to 50 and says so")
    func levelDefaults() throws {
        let slot = try #require(Self.preview("Incineroar").slots.first)
        #expect(slot.level == 50)
        #expect(slot.issues.contains { $0 == .levelDefaulted(50) })
    }

    @Test("A stated level is used")
    func levelIsParsed() throws {
        let slot = try #require(Self.preview("Incineroar\nLevel: 100").slots.first)
        #expect(slot.level == 100)
        #expect(slot.issues.contains { $0 == .levelDefaulted(50) } == false)
    }

    // MARK: - EV scale handling

    @Test("Mainline EVs convert into Champions points")
    func convertsMainlineToChampions() throws {
        let slot = try #require(Self.preview("""
        Incineroar @ Sitrus Berry
        EVs: 252 HP / 252 Atk / 4 Def
        Adamant Nature
        """).slots.first)
        #expect(slot.evs.hp == 32)
        #expect(slot.evs.atk == 32)
        #expect(slot.evs.def == 1)
        #expect(slot.issues.contains {
            $0 == .evScaleConverted(from: .mainline, to: .champions)
        })
    }

    @Test("Champions points pass through untouched")
    func championsPointsPassThrough() throws {
        let slot = try #require(Self.preview("""
        Incineroar @ Sitrus Berry
        EVs: 30 HP / 20 Atk / 16 Def
        Adamant Nature
        """).slots.first)
        #expect(slot.evs == ShowdownStats(hp: 30, atk: 20, def: 16, spa: 0, spd: 0, spe: 0))
        #expect(slot.issues.contains {
            if case .evScaleConverted = $0 { return true }; return false
        } == false)
    }

    @Test("A mainline target leaves EVs on the mainline scale")
    func mainlineTargetKeepsEVs() throws {
        let slot = try #require(Self.preview("""
        Incineroar
        EVs: 252 Atk / 252 Spe
        """, targetScale: .mainline).slots.first)
        #expect(slot.evs.atk == 252)
        #expect(slot.evs.spe == 252)
    }

    @Test("Over-cap values are clamped and reported")
    func clampsOverCap() throws {
        // Forcing the Champions scale on a mainline-looking number is the
        // realistic path here: the user overrode the units toggle.
        let slot = try #require(Self.preview("""
        Incineroar
        EVs: 252 Atk
        """, forcedScale: .champions).slots.first)
        #expect(slot.evs.atk == 32)
        #expect(slot.issues.contains {
            $0 == .evClamped(stat: .atk, from: 252, to: 32)
        })
    }

    @Test("IVs survive import unchanged")
    func ivsPassThrough() throws {
        let slot = try #require(Self.preview("Incineroar\nIVs: 0 Atk").slots.first)
        #expect(slot.ivs.atk == 0)
        #expect(slot.ivs.hp == 31)
    }

    // MARK: - Mapping out

    @Test("PokemonSet carries the validator's spellings and Champions points")
    func mapsToPokemonSet() throws {
        let importer = Self.importer()
        let preview = importer.preview(ShowdownPaste.parse("""
        Incineroar @ Sitrus Berry
        Ability: Intimidate
        EVs: 252 HP / 252 Atk
        Adamant Nature
        - Fake Out
        - Flare Blitz
        """))
        let slot = try #require(preview.slots.first)
        let set = importer.pokemonSet(for: slot)

        #expect(set.species == "Incineroar")
        #expect(set.nature == "Adamant")
        #expect(set.item == "Sitrus Berry")
        #expect(set.moves == ["Fake Out", "Flare Blitz"])
        #expect(set.statPoints.hp == 32)
        #expect(set.statPoints.atk == 32)
        #expect(set.usedEVFormat == false)
    }

    @Test("SavedSpread round-trips the resolved set")
    func mapsToSavedSpread() throws {
        let importer = Self.importer()
        let preview = importer.preview(ShowdownPaste.parse("""
        Incineroar @ Choice Band
        Ability: Intimidate
        Level: 50
        EVs: 252 Atk / 4 HP
        Adamant Nature
        IVs: 0 SpA
        - Fake Out
        - Flare Blitz
        - U-turn
        - Protect
        """))
        let slot = try #require(preview.slots.first)
        let spread = try #require(importer.savedSpread(for: slot, name: "Imported"))

        #expect(spread.name == "Imported")
        #expect(spread.pokemonID == 727)
        #expect(spread.pokemonName == "Incineroar")
        #expect(spread.abilityName == "intimidate")
        #expect(spread.itemRawValue == "Choice Band")
        #expect(spread.championsMode == true)
        #expect(spread.natureID == "adamant")
        #expect(spread.level == 50)
        #expect(spread.evAtk == 32)
        #expect(spread.evHP == 1)
        #expect(spread.ivSpAtk == 0)
        #expect([spread.moveID1, spread.moveID2, spread.moveID3, spread.moveID4]
                == [252, 394, 369, 182])
    }

    @Test("A blocked slot produces no spread and no team slot")
    func blockedSlotMapsToNil() throws {
        let importer = Self.importer()
        let preview = importer.preview(ShowdownPaste.parse("Notamon @ Life Orb"))
        let slot = try #require(preview.slots.first)
        #expect(importer.savedSpread(for: slot, name: "x") == nil)
        #expect(importer.teamSlot(for: slot, spreadName: "x") == nil)
    }

    @Test("TeamSlotInfo carries types, STAB flags and only resolved moves")
    func mapsToTeamSlot() throws {
        let importer = Self.importer()
        let preview = importer.preview(ShowdownPaste.parse("""
        Incineroar @ Sitrus Berry
        - Flare Blitz
        - U-turn
        - Nonexistent Move
        """))
        let slot = try #require(preview.slots.first)
        let teamSlot = try #require(importer.teamSlot(for: slot, spreadName: "Imported"))

        #expect(teamSlot.pokemonName == "Incineroar")
        #expect(teamSlot.type1 == "Fire")
        #expect(teamSlot.type2 == "Dark")
        // The unresolved move is dropped rather than carried as a blank.
        #expect(teamSlot.moveSlots.count == 2)
        // Flare Blitz is Fire on a Fire/Dark attacker.
        #expect(teamSlot.moveSlots[0].isSTAB == true)
        #expect(teamSlot.moveSlots[1].isSTAB == false)
    }

    @Test("Status moves are never marked STAB")
    func statusMovesAreNotSTAB() throws {
        let importer = Self.importer()
        let preview = importer.preview(ShowdownPaste.parse("Incineroar\n- Protect"))
        let slot = try #require(preview.slots.first)
        let teamSlot = try #require(importer.teamSlot(for: slot, spreadName: "x"))
        #expect(teamSlot.moveSlots[0].isSTAB == false)
    }

    // MARK: - Export round trip

    @Test("Import then export normalizes spelling and keeps unresolved text")
    func exportRoundTrip() throws {
        let importer = Self.importer()
        let preview = importer.preview(ShowdownPaste.parse("""
        Mr. Rime @ Choice Band
        Level: 50
        EVs: 252 Atk
        Adamant Nature
        - U-turn
        - Nonexistent Move
        """))
        let slot = try #require(preview.slots.first)
        let text = slot.exportSet(evsAreIn: importer.targetScale)
            .showdownText(scale: .mainline)

        // Species and move names come back in the app's spelling…
        #expect(text.contains("Mr-Rime @ Choice Band"))
        #expect(text.contains("- U Turn"))
        // …and anything that didn't resolve is preserved verbatim.
        #expect(text.contains("- Nonexistent Move"))
        // 252 -> 32 points -> 252 again, so the trip is stable at the cap.
        #expect(text.contains("EVs: 252 Atk"))
    }

    @Test("Export converts Champions points back to mainline EVs")
    func exportConvertsPointsOut() throws {
        let importer = Self.importer()
        let preview = importer.preview(ShowdownPaste.parse("""
        Incineroar
        EVs: 16 HP / 8 Atk
        """, forcedScale: .champions))
        let slot = try #require(preview.slots.first)
        let text = slot.exportSet(evsAreIn: .champions).showdownText(scale: .mainline)
        #expect(text.contains("EVs: 126 HP / 63 Atk"))
    }

    // MARK: - Preview plumbing

    @Test("Parse diagnostics are carried into the preview")
    func carriesParseDiagnostics() {
        let preview = Self.preview("""
        Incineroar @ Sitrus Berry
        garbage line
        """)
        #expect(preview.parseDiagnostics.count == 1)
        #expect(preview.parseDiagnostics.first?.kind == .unrecognizedLine)
    }

    @Test("The ambiguous-scale flag reaches the preview")
    func carriesAmbiguousScaleFlag() {
        let preview = Self.preview("Incineroar\nEVs: 4 HP / 8 Atk")
        #expect(preview.scaleWasAmbiguous)
    }

    @Test("An empty paste is not importable")
    func emptyPasteIsNotImportable() {
        let preview = Self.preview("")
        #expect(preview.slots.isEmpty)
        #expect(preview.isImportable == false)
    }

    @Test("Without a validator there are no violations")
    func noValidatorMeansNoViolations() throws {
        let slot = try #require(Self.preview("Incineroar @ Choice Band").slots.first)
        #expect(slot.violations.isEmpty)
    }
}

// MARK: - Validator wiring

/// Exercises the real `ChampionsValidator`, so it needs the bundled legality
/// JSON. Skips with a note when that isn't present, matching the convention
/// in `PokiiParityTests` / `ChampionsFiltersTests`.
@MainActor
@Suite("Showdown Paste — Import Legality")
struct ShowdownPasteImportLegalityTests {

    private static func makePokemon(id: Int, name: String, type1: String,
                                    ability1: String?) -> PKMNStats {
        PKMNStats(id: id, speciesID: id, name: name, formName: nil,
                  type1: type1, type2: nil,
                  baseHP: 80, baseAtk: 100, baseDef: 90,
                  baseSpAtk: 110, baseSpDef: 95, baseSpeed: 120,
                  ability1: ability1)
    }

    @Test("A legal Champions set imports with no legality violations")
    func legalSetHasNoViolations() throws {
        guard let validator = ChampionsValidator() else {
            print("[ShowdownPasteImportLegalityTests] legality JSON not bundled; skipping")
            return
        }
        // Pick a species the active regulation actually allows, and build its
        // set from the validator's own vocabulary so the test tracks the
        // bundled data instead of hardcoding a roster that changes per reg.
        guard let species = validator.speciesWhitelist.sorted().first,
              let legalMoves = validator.learnsets[species]?.sorted().prefix(4),
              legalMoves.count == 4,
              let legalAbility = validator.speciesAbilities[species]?.sorted().first
        else {
            print("[ShowdownPasteImportLegalityTests] unexpected legality data shape; skipping")
            return
        }

        let pokemon = Self.makePokemon(id: 1, name: species, type1: "Normal",
                                       ability1: toID(legalAbility))
        let importer = PasteImporter(allPokemon: [pokemon], allMoves: [],
                                     validator: validator)
        let paste = """
        \(species)
        Ability: \(legalAbility)
        Level: 50
        EVs: 32 HP / 32 Atk
        Serious Nature
        \(legalMoves.map { "- \($0)" }.joined(separator: "\n"))
        """
        let preview = importer.preview(ShowdownPaste.parse(paste, forcedScale: .champions))
        let slot = try #require(preview.slots.first)

        // Explicit closure rather than a key path: inside `#expect`'s macro
        // expansion the key-path root can't be inferred.
        let messages = slot.legalityViolations.map { $0.message }
        #expect(slot.legalityViolations.isEmpty, "unexpected: \(messages)")
    }

    @Test("An over-budget spread is reported as a legality violation")
    func overBudgetIsFlagged() throws {
        guard let validator = ChampionsValidator() else {
            print("[ShowdownPasteImportLegalityTests] legality JSON not bundled; skipping")
            return
        }
        guard let species = validator.speciesWhitelist.sorted().first else { return }

        let pokemon = Self.makePokemon(id: 1, name: species, type1: "Normal", ability1: nil)
        let importer = PasteImporter(allPokemon: [pokemon], allMoves: [],
                                     validator: validator)
        // 32 per stat across six stats is 192 points against a 66 cap. Each
        // value is individually legal, so only the total can catch this.
        let paste = """
        \(species)
        EVs: 32 HP / 32 Atk / 32 Def / 32 SpA / 32 SpD / 32 Spe
        Serious Nature
        """
        let preview = importer.preview(ShowdownPaste.parse(paste, forcedScale: .champions))
        let slot = try #require(preview.slots.first)

        // Fully-qualified case: `#expect`'s expansion loses the contextual base.
        #expect(slot.violations.contains {
            $0.category == Violation.Category.statPointsOverCap
        })
    }
}
