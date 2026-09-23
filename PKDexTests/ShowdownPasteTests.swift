//
//  ShowdownPasteTests.swift
//  PKDexTests
//
//  Covers the text <-> struct layer in `ShowdownPaste.swift`. Everything here
//  is hermetic: the parse layer resolves nothing against SwiftData or the
//  bundled JSON, so there's no fixture or bundle dependency.
//
//  The two properties that matter most:
//   1. A paste that came out of Showdown round-trips byte-for-byte.
//   2. One bad line degrades to a diagnostic instead of losing the paste.
//

import Testing
import Foundation
@testable import PKDex

/// Deliberately **not** `@MainActor`, unlike `ShowdownPasteImportTests` (which
/// touches SwiftData models and has to be). The parse layer is pure, and
/// `ShowdownPaste.swift` marks its types `nonisolated` so it stays usable off
/// the main actor. Keeping this suite nonisolated makes that a compile-time
/// guarantee: if one of those types loses its annotation and picks up the
/// module's default main-actor isolation, the isolated-conformance warnings
/// reappear here immediately.
@Suite("Showdown Paste — Parse & Serialize")
struct ShowdownPasteTests {

    // MARK: - Fixtures

    /// Canonical two-set VGC paste in Showdown's exact field order.
    static let vgcTeam = """
    Calyrex-Shadow @ Life Orb
    Ability: As One (Unnerve)
    Level: 50
    Tera Type: Ghost
    EVs: 4 HP / 252 SpA / 252 Spe
    Timid Nature
    IVs: 0 Atk
    - Astral Barrage
    - Psyshock
    - Nasty Plot
    - Protect

    Chi-Yu @ Choice Specs
    Ability: Beads of Ruin
    Level: 50
    Shiny: Yes
    Tera Type: Fire
    EVs: 4 HP / 252 SpA / 252 Spe
    Modest Nature
    IVs: 0 Atk
    - Heat Wave
    - Dark Pulse
    - Overheat
    - Snarl
    """

    // MARK: - Round trip

    @Test("A Showdown paste round-trips byte-for-byte")
    func roundTripIsByteStable() throws {
        let parsed = ShowdownPaste.parse(Self.vgcTeam)
        #expect(parsed.diagnostics.isEmpty)
        #expect(parsed.sets.count == 2)
        #expect(parsed.sets.showdownText() == Self.vgcTeam)
    }

    @Test("Fields land in the right properties")
    func fieldsAreParsed() throws {
        let parsed = ShowdownPaste.parse(Self.vgcTeam)
        let calyrex = try #require(parsed.sets.first)

        #expect(calyrex.species == "Calyrex-Shadow")
        #expect(calyrex.nickname == nil)
        #expect(calyrex.item == "Life Orb")
        // Ability values can contain parentheses; only the header treats them
        // as structure.
        #expect(calyrex.ability == "As One (Unnerve)")
        #expect(calyrex.level == 50)
        #expect(calyrex.shiny == false)
        #expect(calyrex.teraType == "Ghost")
        #expect(calyrex.nature == "Timid")
        #expect(calyrex.evs == ShowdownStats(hp: 4, atk: 0, def: 0, spa: 252, spd: 0, spe: 252))
        #expect(calyrex.ivs == ShowdownStats(hp: 31, atk: 0, def: 31, spa: 31, spd: 31, spe: 31))
        #expect(calyrex.moves == ["Astral Barrage", "Psyshock", "Nasty Plot", "Protect"])

        let chiYu = try #require(parsed.sets.last)
        #expect(chiYu.shiny == true)
    }

    // MARK: - Header forms

    /// One header line and everything it should decompose into.
    struct HeaderCase: Sendable, CustomTestStringConvertible {
        var line: String
        var species: String
        var nickname: String? = nil
        var gender: Character? = nil
        var item: String? = nil

        var testDescription: String { line }
    }

    @Test("Header permutations", arguments: [
        HeaderCase(line: "Iron Hands", species: "Iron Hands"),
        HeaderCase(line: "Iron Hands @ Assault Vest", species: "Iron Hands",
                   item: "Assault Vest"),
        HeaderCase(line: "Iron Hands (M)", species: "Iron Hands", gender: "M"),
        HeaderCase(line: "Iron Hands (M) @ Assault Vest", species: "Iron Hands",
                   gender: "M", item: "Assault Vest"),
        HeaderCase(line: "Sun Dog (Torkoal) @ Charcoal", species: "Torkoal",
                   nickname: "Sun Dog", item: "Charcoal"),
        HeaderCase(line: "Sun Dog (Torkoal) (F) @ Charcoal", species: "Torkoal",
                   nickname: "Sun Dog", gender: "F", item: "Charcoal"),
        HeaderCase(line: "Urshifu-Rapid-Strike @ Mystic Water",
                   species: "Urshifu-Rapid-Strike", item: "Mystic Water"),
    ])
    func headerForms(_ testCase: HeaderCase) throws {
        let parsed = ShowdownPaste.parse(testCase.line)
        let set = try #require(parsed.sets.first)
        #expect(set.species == testCase.species)
        #expect(set.nickname == testCase.nickname)
        #expect(set.gender == testCase.gender)
        #expect(set.item == testCase.item)
        #expect(parsed.diagnostics.isEmpty)
    }

    @Test("Species names with dots survive verbatim")
    func speciesWithDots() throws {
        // The app keys on `PKMN.name` (slug.capitalized), so resolving
        // "Mr. Mime" to "Mr-Mime" is the importer's job, not the parser's —
        // the parser must hand it over unchanged.
        let parsed = ShowdownPaste.parse("Mr. Mime @ Focus Sash")
        let set = try #require(parsed.sets.first)
        #expect(set.species == "Mr. Mime")
    }

    // MARK: - Tolerances

    @Test("CRLF line endings parse")
    func crlfEndings() throws {
        let paste = "Incineroar @ Sitrus Berry\r\nAbility: Intimidate\r\n- Fake Out"
        let parsed = ShowdownPaste.parse(paste)
        let set = try #require(parsed.sets.first)
        #expect(set.ability == "Intimidate")
        #expect(set.moves == ["Fake Out"])
        #expect(parsed.diagnostics.isEmpty)
    }

    @Test("En/em dash move bullets parse")
    func smartDashBullets() throws {
        let paste = "Incineroar\n\u{2013} Fake Out\n\u{2014} Parting Shot"
        let parsed = ShowdownPaste.parse(paste)
        let set = try #require(parsed.sets.first)
        #expect(set.moves == ["Fake Out", "Parting Shot"])
        #expect(parsed.diagnostics.isEmpty)
    }

    @Test("Folder headers from a folder export are skipped")
    func folderHeaderIgnored() throws {
        let paste = """
        === [gen9vgc2024regh] My Folder ===

        Incineroar @ Safety Goggles
        Ability: Intimidate
        - Fake Out
        """
        let parsed = ShowdownPaste.parse(paste)
        #expect(parsed.sets.count == 1)
        #expect(parsed.sets.first?.species == "Incineroar")
        #expect(parsed.diagnostics.isEmpty)
    }

    @Test("Extra blank lines between sets don't create empty sets")
    func extraBlankLines() {
        let parsed = ShowdownPaste.parse("Koraidon\n\n\n\nMiraidon\n\n")
        #expect(parsed.sets.count == 2)
    }

    @Test("Dynamax and ball fields are accepted and dropped")
    func toleratedFields() throws {
        let paste = """
        Rillaboom @ Assault Vest
        Ability: Grassy Surge
        Dynamax Level: 10
        Gigantamax: Yes
        Pokeball: Cherish Ball
        - Grassy Glide
        """
        let parsed = ShowdownPaste.parse(paste)
        #expect(parsed.diagnostics.isEmpty)
        #expect(parsed.sets.first?.moves == ["Grassy Glide"])
    }

    // MARK: - Stat lists

    @Test("Stat abbreviations and long forms", arguments: [
        ("EVs: 252 HP", ShowdownStat.hp),
        ("EVs: 252 Atk", .atk),
        ("EVs: 252 Attack", .atk),
        ("EVs: 252 Def", .def),
        ("EVs: 252 Defence", .def),
        ("EVs: 252 SpA", .spa),
        ("EVs: 252 Special Attack", .spa),
        ("EVs: 252 SpD", .spd),
        ("EVs: 252 SpDef", .spd),
        ("EVs: 252 Spe", .spe),
        ("EVs: 252 Speed", .spe),
    ])
    func statKeyAliases(line: String, expected: ShowdownStat) throws {
        let parsed = ShowdownPaste.parse("Koraidon\n\(line)")
        let set = try #require(parsed.sets.first)
        #expect(set.evs[expected] == 252)
        #expect(parsed.diagnostics.isEmpty)
        // Every other stat stays at zero.
        for stat in ShowdownStat.allCases where stat != expected {
            #expect(set.evs[stat] == 0)
        }
    }

    @Test("Reversed stat entries are accepted")
    func reversedStatEntry() throws {
        let parsed = ShowdownPaste.parse("Koraidon\nEVs: Atk 252 / HP 4")
        let set = try #require(parsed.sets.first)
        #expect(set.evs.atk == 252)
        #expect(set.evs.hp == 4)
        #expect(parsed.diagnostics.isEmpty)
    }

    @Test("Unlisted IVs default to 31, unlisted EVs to 0")
    func statDefaults() throws {
        let parsed = ShowdownPaste.parse("Koraidon\nEVs: 4 HP\nIVs: 0 Spe")
        let set = try #require(parsed.sets.first)
        #expect(set.evs == ShowdownStats(hp: 4, atk: 0, def: 0, spa: 0, spd: 0, spe: 0))
        #expect(set.ivs == ShowdownStats(hp: 31, atk: 31, def: 31, spa: 31, spd: 31, spe: 0))
    }

    // MARK: - Scale detection

    @Test("Mainline EVs are detected unambiguously")
    func detectsMainline() {
        let parsed = ShowdownPaste.parse("Koraidon\nEVs: 4 HP / 252 Atk / 252 Spe")
        #expect(parsed.detectedScale == .mainline)
        #expect(parsed.scaleWasAmbiguous == false)
        #expect(parsed.sets.first?.evScale == .mainline)
    }

    @Test("A stat point that isn't a multiple of 4 means Champions")
    func detectsChampions() {
        // 30 is unreachable on the mainline scale below the cap; only the
        // Champions 0–32 model produces it.
        let parsed = ShowdownPaste.parse("Koraidon\nEVs: 30 Atk / 20 Spe")
        #expect(parsed.detectedScale == .champions)
        #expect(parsed.scaleWasAmbiguous == false)
    }

    @Test("A Champions total over 66 can only be mainline")
    func detectsMainlineByTotal() {
        // Each value is under 32 and a multiple of 4, but they sum past the
        // Champions budget.
        let parsed = ShowdownPaste.parse("Koraidon\nEVs: 32 HP / 32 Atk / 32 Def / 32 Spe")
        #expect(parsed.detectedScale == .mainline)
        #expect(parsed.scaleWasAmbiguous == false)
    }

    @Test("Low-investment spreads are ambiguous and default to mainline")
    func ambiguousScale() {
        let parsed = ShowdownPaste.parse("Koraidon\nEVs: 4 HP / 8 Atk")
        #expect(parsed.detectedScale == .mainline)
        #expect(parsed.scaleWasAmbiguous == true)
        #expect(parsed.diagnostics.contains { $0.kind == .ambiguousEVScale })
    }

    @Test("No EVs at all isn't flagged as ambiguous")
    func noEVsIsNotAmbiguous() {
        let parsed = ShowdownPaste.parse("Koraidon\nAbility: Orichalcum Pulse")
        #expect(parsed.scaleWasAmbiguous == false)
        #expect(parsed.diagnostics.isEmpty)
    }

    @Test("A forced scale overrides detection")
    func forcedScale() {
        let parsed = ShowdownPaste.parse("Koraidon\nEVs: 4 HP / 8 Atk",
                                        forcedScale: .champions)
        #expect(parsed.detectedScale == .champions)
        #expect(parsed.scaleWasAmbiguous == false)
        #expect(parsed.sets.first?.evScale == .champions)
    }

    // MARK: - Scale conversion

    @Test("Champions points convert up to mainline EVs", arguments: [
        (0, 0),
        (1, 7),      // 1 * 252 / 32 == 7.875, truncated
        (4, 31),
        (16, 126),
        (32, 252),   // the cap maps exactly onto the mainline cap
    ])
    func championsToMainline(champions: Int, mainline: Int) {
        #expect(StatScale.convert(champions, from: .champions, to: .mainline) == mainline)
    }

    @Test("Mainline 252 converts back to the Champions cap")
    func mainlineToChampions() {
        #expect(StatScale.convert(252, from: .mainline, to: .champions) == 32)
        #expect(StatScale.convert(0, from: .mainline, to: .champions) == 0)
        // Rounds to nearest rather than truncating, so a 4-EV nudge survives.
        #expect(StatScale.convert(4, from: .mainline, to: .champions) == 1)
    }

    @Test("Converting to the same scale is identity")
    func sameScaleConversion() {
        #expect(StatScale.convert(123, from: .mainline, to: .mainline) == 123)
    }

    @Test("Export converts Champions points into mainline EVs")
    func exportConvertsScale() throws {
        let parsed = ShowdownPaste.parse("Koraidon\nEVs: 32 Atk / 30 Spe")
        #expect(parsed.detectedScale == .champions)
        let text = parsed.sets.showdownText(scale: .mainline)
        #expect(text.contains("EVs: 252 Atk / 236 Spe"))
    }

    // MARK: - Serialization details

    @Test("Default-valued lines are omitted")
    func omitsDefaultLines() {
        var set = ShowdownPasteSet(species: "Koraidon")
        set.moves = ["Collision Course"]
        #expect(set.showdownText() == "Koraidon\n- Collision Course")
    }

    @Test("Serialized field order matches Showdown")
    func fieldOrder() {
        var set = ShowdownPasteSet(species: "Chi-Yu")
        set.item = "Choice Specs"
        set.ability = "Beads of Ruin"
        set.level = 50
        set.shiny = true
        set.happiness = 160
        set.teraType = "Fire"
        set.nature = "Modest"
        set.evs = ShowdownStats(hp: 4, atk: 0, def: 0, spa: 252, spd: 0, spe: 252)
        set.ivs = ShowdownStats(hp: 31, atk: 0, def: 31, spa: 31, spd: 31, spe: 31)
        set.moves = ["Heat Wave"]

        #expect(set.showdownText() == """
        Chi-Yu @ Choice Specs
        Ability: Beads of Ruin
        Level: 50
        Shiny: Yes
        Happiness: 160
        Tera Type: Fire
        EVs: 4 HP / 252 SpA / 252 Spe
        Modest Nature
        IVs: 0 Atk
        - Heat Wave
        """)
    }

    // MARK: - Diagnostics

    @Test("A bad line doesn't cost the rest of the paste")
    func partialFailureIsContained() throws {
        let paste = """
        Koraidon @ Clear Amulet
        Ability: Orichalcum Pulse
        Nonsense line with no colon and no bullet
        - Collision Course

        Miraidon @ Life Orb
        Ability: Hadron Engine
        - Electro Drift
        """
        let parsed = ShowdownPaste.parse(paste)
        #expect(parsed.sets.count == 2)
        #expect(parsed.sets[0].moves == ["Collision Course"])
        #expect(parsed.sets[1].species == "Miraidon")

        #expect(parsed.diagnostics.count == 1)
        let diagnostic = try #require(parsed.diagnostics.first)
        #expect(diagnostic.kind == .unrecognizedLine)
        #expect(diagnostic.line == 3)
        #expect(diagnostic.setIndex == 0)
    }

    @Test("A fifth move is dropped with a diagnostic")
    func tooManyMoves() throws {
        let paste = """
        Incineroar
        - Fake Out
        - Parting Shot
        - Knock Off
        - Flare Blitz
        - U-turn
        """
        let parsed = ShowdownPaste.parse(paste)
        let set = try #require(parsed.sets.first)
        #expect(set.moves.count == 4)
        #expect(set.moves.last == "Flare Blitz")
        #expect(parsed.diagnostics.contains { $0.kind == .tooManyMoves(kept: 4, dropped: 1) })
    }

    @Test("An unknown stat key is reported with its line number")
    func unknownStatKey() throws {
        let parsed = ShowdownPaste.parse("Koraidon\nEVs: 252 Atk / 4 Bulk")
        let set = try #require(parsed.sets.first)
        #expect(set.evs.atk == 252)
        let diagnostic = try #require(parsed.diagnostics.first)
        #expect(diagnostic.kind == .unknownStatKey("Bulk"))
        #expect(diagnostic.line == 2)
    }

    @Test("A malformed stat entry is reported")
    func malformedStatEntry() throws {
        let parsed = ShowdownPaste.parse("Koraidon\nEVs: 252")
        #expect(parsed.diagnostics.contains { $0.kind == .malformedStatEntry("252") })
    }

    @Test("A non-numeric level is reported and left unset")
    func invalidLevel() throws {
        let parsed = ShowdownPaste.parse("Koraidon\nLevel: fifty")
        // Require the set first: `sets.first?.level == nil` is an `Int??`
        // comparison that would also pass if nothing parsed at all.
        let set = try #require(parsed.sets.first)
        #expect(set.level == nil)
        #expect(parsed.diagnostics.contains {
            $0.kind == .invalidNumber(field: "Level", value: "fifty")
        })
    }

    @Test("A duplicated field keeps the last value and warns")
    func duplicateField() throws {
        let parsed = ShowdownPaste.parse("Koraidon\nEVs: 252 Atk\nEVs: 252 Spe")
        let set = try #require(parsed.sets.first)
        #expect(set.evs.spe == 252)
        #expect(set.evs.atk == 0)
        #expect(parsed.diagnostics.contains { $0.kind == .duplicateField("EVs") })
    }

    @Test("Empty and whitespace-only input yields nothing, not a crash")
    func emptyInput() {
        #expect(ShowdownPaste.parse("").isEmpty)
        #expect(ShowdownPaste.parse("   \n\n \t \n").isEmpty)
    }
}
