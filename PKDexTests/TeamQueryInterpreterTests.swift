//
//  TeamQueryInterpreterTests.swift
//  PKDexTests
//
//  Covers the deterministic side of reading descriptions with Apple
//  Intelligence: the phrases the parser hands over, reading the text again
//  with their meanings in place (only clean meanings count, and negations
//  still apply), adding what's new to a query without undoing chip edits,
//  and the prompt, schema and answer cleanup. The model itself isn't
//  called: its answers are given by hand.
//

import Testing
import Foundation
import FoundationModels
@testable import PKDex

@Suite("Team Query Interpreter")
struct TeamQueryInterpreterTests {

    private typealias F = TeamSearchFixtures

    private func labels(_ query: TeamQuery) -> [String] {
        query.species.map(\.displayName) + query.archetypes.map(\.label) + query.moves.map(\.name)
            + query.excludedSpecies.map { "No " + $0.displayName }
            + query.excludedArchetypes.map { "No " + $0.label }
            + query.excludedMoves.map { "No " + $0.name }
    }

    // MARK: Phrases

    @Test("Runs of adjacent unrecognized words become phrases")
    func phrases() {
        #expect(F.parser.unplacedPhrases(in: "sun team without the big fire cat") == ["big fire cat"])
        // "Hisuian" waits for a species that never comes, so it joins the run.
        #expect(F.parser.unplacedPhrases(in: "slow team with the hisuian fire dog")
                == ["slow", "hisui fire dog"])
        // Stop words and commas split runs.
        #expect(F.parser.unplacedPhrases(in: "the ghost with the trapping move, bulky")
                == ["ghost", "trapping move", "bulky"])
        // A "mega" on a species without one.
        #expect(F.parser.unplacedPhrases(in: "mega pelipper") == ["mega"])
        #expect(F.parser.unplacedPhrases(in: "trick room with incineroar").isEmpty)
    }

    // MARK: Reading again

    @Test("Meanings replace their phrases, and negations still apply")
    func meanings() {
        let text = "sun team without the big fire cat"
        let query = F.parser.parse(text, meanings: ["big fire cat": "Incineroar"])
        #expect(labels(query) == ["Sun", "No Incineroar"])
        #expect(query.unrecognized.isEmpty)

        let slow = F.parser.parse("slow team with the hisuian fire dog",
                                  meanings: ["slow": "Trick Room", "hisui fire dog": "Hisuian Arcanine"])
        #expect(labels(slow) == ["Arcanine (Hisui)", "Trick Room"])

        let move = F.parser.parse("incineroar with the pivot move", meanings: ["pivot move": "Parting Shot"])
        #expect(labels(move) == ["Incineroar", "Parting Shot"])
    }

    @Test("Meanings that don't read cleanly are ignored")
    func uncleanMeanings() {
        let text = "sun team without the big fire cat"
        for meaning in ["none", "", "Fairies", "Big Cat", "Incinaroar", "Incineroar, the Fire Cat Pokémon"] {
            let query = F.parser.parse(text, meanings: ["big fire cat": meaning])
            #expect(labels(query) == ["Sun"], "\(meaning)")
            #expect(query.unrecognized == ["big", "fire", "cat"], "\(meaning)")
        }
        // Only some phrases answered: the rest stay unrecognized.
        let partial = F.parser.parse("slow team with the hisuian fire dog", meanings: ["slow": "Trick Room"])
        #expect(labels(partial) == ["Trick Room"])
        #expect(partial.unrecognized == ["fire", "dog", "hisui"])
    }

    // MARK: Adding

    @Test("Only what neither the query nor the text's own parse mentions is added")
    func adding() {
        let baseline = F.parser.parse("trick room with charizard, no whimsicott")
        var query = baseline
        query.archetypes = []                                 // the user removed the Trick Room chip
        let other = F.parser.parse("trick room with mega charizard y, garchomp and encore, no whimsicott or tailwind")

        let added = query.add(other, beyond: baseline)

        #expect(labels(added) == ["Garchomp", "Encore", "No Tailwind"])
        #expect(labels(query) == ["Charizard", "Garchomp", "Encore", "No Whimsicott", "No Tailwind"])
    }

    @Test("At most six species are included")
    func sixSpecies() {
        var query = F.parser.parse("incineroar garchomp gardevoir charizard arcanine")
        let other = F.parser.parse("rillaboom pelipper farigiraf, no kingambit")
        let added = query.add(other, beyond: TeamQuery())
        #expect(labels(added) == ["Rillaboom", "No Kingambit"])
        #expect(query.species.count == 6)
    }

    // MARK: Apple Intelligence

    @Test("Answers are trimmed to their first line, without quotes or bold")
    func cleaning() {
        #expect(AppleIntelligenceInterpreter.cleaned("\"Incineroar\"") == "Incineroar")
        #expect(AppleIntelligenceInterpreter.cleaned("**Garchomp**.") == "Garchomp")
        #expect(AppleIntelligenceInterpreter.cleaned("Rillaboom\n\nIt's a grass monkey.") == "Rillaboom")
        #expect(AppleIntelligenceInterpreter.cleaned("  Mega Charizard Y ") == "Mega Charizard Y")
    }

    @Test("The prompt numbers the phrases, and the instructions list the styles")
    func promptAndInstructions() throws {
        #expect(AppleIntelligenceInterpreter.prompt(["slow", "big fire cat"], in: "slow, no big fire cat") == """
            Description: slow, no big fire cat
            Phrases:
            phrase1: "slow"
            phrase2: "big fire cat"
            """)
        let instructions = AppleIntelligenceInterpreter.instructions(F.vocabulary)
        #expect(instructions.contains("- Trick Room: slow Pokémon move first"))
        #expect(instructions.contains("- Perish Trap\n") || instructions.hasSuffix("- Perish Trap"))
        _ = try AppleIntelligenceInterpreter.schema(["slow"])
        _ = try AppleIntelligenceInterpreter.schema((1...AppleIntelligenceInterpreter.maxPhrases).map { "p\($0)" })
    }

    @Test("Errors become messages to show")
    func messages() {
        let context = LanguageModelSession.GenerationError.Context(debugDescription: "test")
        #expect(AppleIntelligenceInterpreter.message(for: LanguageModelSession.GenerationError
            .exceededContextWindowSize(context)).contains("too long"))
        #expect(AppleIntelligenceInterpreter.message(for: LanguageModelSession.GenerationError
            .unsupportedLanguageOrLocale(context)).contains("language"))
        #expect(AppleIntelligenceInterpreter.message(for: URLError(.unknown))
                == "Apple Intelligence couldn't read this description.")
    }

    @Test("Every bundled style has a hint for the instructions")
    func bundledHints() throws {
        for regulation in ChampionsRegulation.allCases {
            let vocabulary = try TeamSearchVocabulary.bundled(for: regulation)
            #expect(vocabulary.archetypes.allSatisfy { $0.hint?.isEmpty == false })
        }
    }
}
