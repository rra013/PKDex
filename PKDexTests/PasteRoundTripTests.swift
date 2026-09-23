//
//  PasteRoundTripTests.swift
//  PKDexTests
//
//  Phase 1.3: a calc side exported to paste text and imported into an empty
//  side must come back identical. This runs the same pipeline as
//  `PasteImportSheet` (showdownPasteSet → showdownText → parse with the
//  side's scale as the ambiguous default → PasteImporter → savedSpread →
//  loadSpread), so it covers the export code and its join with the existing
//  importer.
//
//  Hermetic, like `ShowdownPasteImportTests`: synthetic fixtures and
//  `validator: nil`.
//

import Testing
import Foundation
@testable import PKDex

@MainActor
@Suite("Showdown Paste — Calc Round Trip")
struct PasteRoundTripTests {

    // MARK: - Fixtures

    private static let incineroar = PKMNStats(
        id: 727, speciesID: 727, name: "Incineroar", formName: nil,
        type1: "Fire", type2: "Dark",
        baseHP: 95, baseAtk: 115, baseDef: 90,
        baseSpAtk: 80, baseSpDef: 90, baseSpeed: 60,
        ability1: "blaze", ability2: nil, hiddenAbility: "intimidate")

    private static func move(_ id: Int, _ name: String, _ type: String,
                             _ cls: String = "physical", _ power: Int? = 80) -> MoveData {
        MoveData(id: id, name: name, type: type, damageClass: cls,
                 power: power, accuracy: 100, pp: 15, priority: 0,
                 minHits: nil, maxHits: nil, drain: 0, healing: 0, critRate: 0,
                 makesContact: true, generationId: 9)
    }

    private static let moves = [
        move(252, "Fake Out", "Normal", "physical", 40),
        move(369, "U Turn", "Bug", "physical", 70),
        move(394, "Flare Blitz", "Fire", "physical", 120),
        move(182, "Protect", "Normal", "status", nil),
    ]

    private static func loadedSide(champions: Bool) -> CalcSide {
        let side = CalcSide()
        side.pokemon = incineroar
        side.championsMode = champions
        side.selectedAbility = "intimidate"
        side.heldItem = .assaultVest
        side.nature = allNatures.first { $0.id == "brave" }!
        side.level = 50
        side.moves = moves
        return side
    }

    /// Export, then import into a fresh side — the sheet's pipeline.
    private static func roundTrip(_ side: CalcSide) throws -> (CalcSide, ImportPreview) {
        let set = try #require(side.showdownPasteSet())
        let scale: StatScale = side.championsMode ? .champions : .mainline
        let parsed = ShowdownPaste.parse(set.showdownText(), ambiguousDefault: scale)
        let importer = PasteImporter(allPokemon: [incineroar], allMoves: moves,
                                     validator: nil, targetScale: scale)
        let preview = importer.preview(parsed)
        let slot = try #require(preview.slots.first)
        let spread = try #require(importer.savedSpread(for: slot, name: "test"))
        let out = CalcSide()
        out.loadSpread(spread, allPokemon: [incineroar], allMoves: moves)
        return (out, preview)
    }

    private static func evs(_ s: CalcSide) -> [Int] {
        [s.evHP, s.evAtk, s.evDef, s.evSpAtk, s.evSpDef, s.evSpeed]
    }

    private static func ivs(_ s: CalcSide) -> [Int] {
        [s.ivHP, s.ivAtk, s.ivDef, s.ivSpAtk, s.ivSpDef, s.ivSpeed]
    }

    private static func expectSameSet(_ a: CalcSide, _ b: CalcSide) {
        #expect(a.pokemon?.id == b.pokemon?.id)
        #expect(a.selectedAbility == b.selectedAbility)
        #expect(a.heldItem == b.heldItem)
        #expect(a.nature.id == b.nature.id)
        #expect(a.level == b.level)
        #expect(a.championsMode == b.championsMode)
        #expect(evs(a) == evs(b))
        #expect(ivs(a) == ivs(b))
        #expect(a.moves.map { $0?.id } == b.moves.map { $0?.id })
    }

    // MARK: - Round trips

    @Test("Mainline set round-trips, including non-31 IVs")
    func mainline() throws {
        let side = Self.loadedSide(champions: false)
        side.evHP = 252; side.evAtk = 252; side.evSpDef = 4
        side.ivSpeed = 0   // Trick Room set
        let (back, preview) = try Self.roundTrip(side)
        Self.expectSameSet(side, back)
        #expect(!preview.scaleWasAmbiguous)
    }

    @Test("Champions set round-trips when its points aren't multiples of 4")
    func championsUnambiguous() throws {
        let side = Self.loadedSide(champions: true)
        side.evHP = 32; side.evAtk = 32; side.evSpDef = 2
        let (back, preview) = try Self.roundTrip(side)
        Self.expectSameSet(side, back)
        #expect(!preview.scaleWasAmbiguous)
    }

    @Test("Champions set round-trips when every point is a multiple of 4")
    func championsAmbiguous() throws {
        // 32 / 32 / 0 also reads as a (tiny) mainline spread. Before the
        // ambiguous default, this re-imported as mainline EVs and landed as
        // 4 / 4 points on a Champions side.
        let side = Self.loadedSide(champions: true)
        side.evHP = 32; side.evAtk = 32
        let (back, preview) = try Self.roundTrip(side)
        #expect(preview.scaleWasAmbiguous, "premise: these numbers fit both scales")
        Self.expectSameSet(side, back)
    }

    @Test("A side with no Pokemon exports nothing")
    func emptySide() {
        #expect(CalcSide().showdownPasteSet() == nil)
    }

    @Test("Export uses Showdown's ability spelling")
    func abilitySpelling() throws {
        let text = try #require(Self.loadedSide(champions: false).showdownPasteSet()).showdownText()
        #expect(text.contains("Ability: Intimidate"))
        #expect(text.contains("Brave Nature"))
        #expect(text.contains("Incineroar @ Assault Vest"))
    }

    // MARK: - Ambiguous default

    @Test("Ambiguous numbers take the caller's default and stay flagged")
    func ambiguousDefault() {
        let paste = "Incineroar\nEVs: 32 HP / 32 Atk\n- Fake Out"
        let plain = ShowdownPaste.parse(paste)
        #expect(plain.scaleWasAmbiguous && plain.detectedScale == .mainline)

        let champions = ShowdownPaste.parse(paste, ambiguousDefault: .champions)
        #expect(champions.detectedScale == .champions)
        #expect(champions.scaleWasAmbiguous)
        #expect(champions.sets.first?.evScale == .champions)
    }

    @Test("Unambiguous numbers ignore the default", arguments: [
        ("EVs: 252 HP / 252 Atk", StatScale.mainline),   // over the Champions cap
        ("EVs: 32 HP / 2 Atk", StatScale.champions),     // not a multiple of 4
    ])
    func unambiguousIgnoresDefault(evLine: String, expected: StatScale) {
        let other: StatScale = expected == .mainline ? .champions : .mainline
        let parsed = ShowdownPaste.parse("Incineroar\n\(evLine)", ambiguousDefault: other)
        #expect(parsed.detectedScale == expected)
        #expect(!parsed.scaleWasAmbiguous)
    }
}
