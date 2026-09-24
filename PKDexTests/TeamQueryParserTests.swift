//
//  TeamQueryParserTests.swift
//  PKDexTests
//
//  Covers `TeamQueryParser`: species, forms and Megas; negation scope; which
//  phrases win (styles over moves, longest match); typo correction; and
//  that words it can't place are reported rather than dropped. Uses the
//  fixture vocabulary.
//

import Testing
@testable import PKDex

@Suite("Team Query Parser")
struct TeamQueryParserTests {

    private func parse(_ text: String) -> TeamQuery {
        TeamSearchFixtures.parser.parse(text)
    }

    private func names(_ terms: [SpeciesTerm]) -> [String] { terms.map(\.displayName) }

    // MARK: Whole descriptions

    @Test("A typical description")
    func typical() {
        let query = parse("Trick Room with Mega Gardevoir, no Incineroar")
        #expect(query.archetypes.map(\.id) == ["trick-room"])
        #expect(names(query.species) == ["Mega Gardevoir"])
        #expect(names(query.excludedSpecies) == ["Incineroar"])
        #expect(query.unrecognized.isEmpty)
        #expect(query.hasConstraints)
    }

    @Test("Blank text has no constraints")
    func blank() {
        #expect(!parse("   ").hasConstraints)
        #expect(!parse("build me a team").hasConstraints)
    }

    // MARK: Negation

    @Test("A negation covers the next item only")
    func negationScope() {
        let query = parse("no incineroar but trick room")
        #expect(names(query.excludedSpecies) == ["Incineroar"])
        #expect(query.archetypes.map(\.id) == ["trick-room"])

        let and = parse("no incineroar and garchomp")
        #expect(names(and.excludedSpecies) == ["Incineroar"])
        #expect(names(and.species) == ["Garchomp"])
    }

    @Test("A negation carries across or, nor and commas")
    func negationCarries() {
        let query = parse("without incineroar or garchomp, charizard")
        #expect(names(query.excludedSpecies) == ["Incineroar", "Garchomp", "Charizard"])
        #expect(query.species.isEmpty)
    }

    @Test("A passed-on negation ends at a contrast word or an unknown word, not at an article")
    func carryEnds() {
        #expect(names(parse("no incineroar or the garchomp").excludedSpecies) == ["Incineroar", "Garchomp"])
        #expect(names(parse("no incineroar, but garchomp").species) == ["Garchomp"])
        #expect(names(parse("no incineroar, maybe garchomp").species) == ["Garchomp"])
    }

    @Test("The later mention wins")
    func laterMentionWins() {
        let query = parse("incineroar, no incineroar")
        #expect(query.species.isEmpty)
        #expect(names(query.excludedSpecies) == ["Incineroar"])

        let styles = parse("no tr, actually trick room")
        #expect(styles.archetypes.map(\.id) == ["trick-room"])
        #expect(styles.excludedArchetypes.isEmpty)
    }

    // MARK: Forms

    @Test("Forms attach from either side, in several spellings")
    func forms() {
        for text in ["hisuian arcanine", "arcanine-h", "Arcanine Hisui", "Arcanine-Hisui"] {
            #expect(names(parse(text).species) == ["Arcanine (Hisui)"], "\(text)")
        }
        for text in ["indeedee ♀", "female indeedee", "Indeedee-F"] {
            #expect(names(parse(text).species) == ["Indeedee (Female)"], "\(text)")
        }
        #expect(names(parse("indeedee male").species) == ["Indeedee (Male)"])
        #expect(names(parse("paldean tauros blaze breed").species) == ["Tauros (Paldea Blaze)"])
    }

    @Test("A form a species doesn't have is reported, not applied")
    func unknownForm() {
        let query = parse("hisuian garchomp")
        #expect(names(query.species) == ["Garchomp"])
        #expect(query.unrecognized == ["hisui"])
    }

    // MARK: Megas

    @Test("Mega wording, stones and variants")
    func megas() {
        #expect(names(parse("mega charizard y").species) == ["Mega Charizard Y"])
        #expect(names(parse("charizard y").species) == ["Mega Charizard Y"])
        #expect(names(parse("zard y").species) == ["Mega Charizard Y"])
        #expect(names(parse("charizardite x").species) == ["Mega Charizard X"])
        #expect(names(parse("mega charizard").species) == ["Mega Charizard"])
        #expect(names(parse("gardevoir mega").species) == ["Mega Gardevoir"])
        #expect(names(parse("gardevoirite").species) == ["Mega Gardevoir"])
    }

    @Test("Mega on a species without one is reported")
    func megaWithoutMega() {
        let query = parse("mega incineroar")
        #expect(names(query.species) == ["Incineroar"])
        #expect(query.unrecognized == ["mega"])
    }

    // MARK: Phrases

    @Test("Styles win over moves with the same name; moves otherwise")
    func stylesAndMoves() {
        #expect(parse("trick room").archetypes.map(\.id) == ["trick-room"])
        #expect(parse("trick room").moves.isEmpty)
        #expect(parse("psychic terrain").archetypes.map(\.id) == ["psychic-terrain"])
        #expect(parse("follow me").moves.map(\.name) == ["Follow Me"])
        #expect(parse("redirection").archetypes.map(\.id) == ["redirection"])
        #expect(parse("fake out incineroar").moves.map(\.name) == ["Fake Out"])
    }

    @Test("Only allowlisted single words are moves")
    func singleWordMoves() {
        #expect(parse("encore").moves.map(\.name) == ["Encore"])
        #expect(parse("protect").moves.isEmpty)
        #expect(parse("protect").unrecognized == ["protect"])
        #expect(parse("psychic").unrecognized == ["psychic"])
    }

    @Test("Nicknames and punctuated names")
    func nicknamesAndPunctuation() {
        #expect(names(parse("chomp and incin").species) == ["Garchomp", "Incineroar"])
        for text in ["kommo-o", "kommoo", "mr. rime", "Mr Rime"] {
            #expect(parse(text).species.count == 1, "\(text)")
        }
    }

    // MARK: Typos and unknown words

    @Test("Close typos of species names are corrected and reported")
    func typos() {
        let query = parse("incinaroar and garchmp")
        #expect(names(query.species) == ["Incineroar", "Garchomp"])
        #expect(query.corrections == [.init(typed: "incinaroar", interpreted: "Incineroar"),
                                      .init(typed: "garchmp", interpreted: "Garchomp")])
    }

    @Test("Short or distant words aren't guessed; unknown words are kept")
    func unknownWords() {
        #expect(parse("incn").species.isEmpty)
        #expect(parse("incn").unrecognized == ["incn"])
        let query = parse("bulky rain team")
        #expect(query.unrecognized == ["bulky", "rain"])
        #expect(!query.hasConstraints)
    }
}
