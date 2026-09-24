//
//  TeamSearchVocabularyTests.swift
//  PKDexTests
//
//  Covers `TeamSearchVocabulary`: species identity from Limitless names and
//  slugs, Mega Stones and their abilities, which moves a query can name, and
//  nickname loading. One suite loads the real bundled M-C files, as a
//  guard against typos in team_search_vocab.json.
//

import Testing
import Foundation
@testable import PKDex

@Suite("Team Search Vocabulary")
struct TeamSearchVocabularyTests {

    private let vocabulary = TeamSearchFixtures.vocabulary

    private func key(_ name: String, _ slug: String? = nil) -> String {
        vocabulary.identity(name: name, slug: slug).key
    }

    // MARK: Identity

    @Test("Regional and gendered forms keep their form words")
    func formIdentity() {
        #expect(key("Hisuian Arcanine", "arcanine-hisui") == "arcanine:hisui")
        #expect(key("Hisuian Arcanine") == "arcanine:hisui")     // no slug: from the name
        #expect(key("Arcanine", "arcanine") == "arcanine")
        #expect(key("Indeedee ♀", "indeedee-f") == "indeedee:female")
        #expect(key("Indeedee", "indeedee") == "indeedee")
        #expect(key("Paldean Tauros Blaze Breed", "tauros-paldea-blaze") == "tauros:blaze-paldea")
    }

    @Test("Forms the regulation doesn't list are dropped, so Champions Floette has one identity")
    func unlistedFormsDropped() {
        #expect(key("Eternal Flower Floette", "floette-eternal") == "floette")
        #expect(key("Floette", "floette") == "floette")
    }

    @Test("Punctuated names and unknown species")
    func punctuationAndUnknown() {
        #expect(key("Kommo-o", "kommo-o") == "kommoo")
        #expect(key("Mr. Rime", "mr-rime") == "mrrime")
        #expect(key("Pikachu", "pikachu") == "pikachu")           // not in the regulation
    }

    // MARK: Megas

    @Test("A Mega Stone counts only on its own species, with its Mega's abilities")
    func megas() throws {
        let y = try #require(vocabulary.mega(heldItem: "Charizardite Y", speciesID: "charizard"))
        #expect(y.variant == "y")
        #expect(y.abilities == ["drought"])
        #expect(vocabulary.mega(heldItem: "Charizardite Y", speciesID: "gardevoir") == nil)
        #expect(vocabulary.mega(heldItem: "Life Orb", speciesID: "charizard") == nil)
        #expect(vocabulary.mega(heldItem: nil, speciesID: "charizard") == nil)
        let floette = try #require(vocabulary.mega(heldItem: "Floettite", speciesID: "floette"))
        #expect(floette.variant == nil)
        #expect(floette.abilities == ["fairyaura"])
    }

    // MARK: Moves and nicknames

    @Test("Queries can name multi-word moves and allowlisted single-word moves only")
    func queryMoves() {
        #expect(vocabulary.queryMoves["fakeout"] == "Fake Out")
        #expect(vocabulary.queryMoves["headsmash"] == "Head Smash")   // from a form's pool
        #expect(vocabulary.queryMoves["encore"] == "Encore")
        #expect(vocabulary.queryMoves["protect"] == nil)
        #expect(vocabulary.queryMoves["psychic"] == nil)
    }

    @Test("A nickname for a species outside the regulation is dropped")
    func nicknames() {
        #expect(vocabulary.nicknames["chomp"] == "garchomp")
        #expect(vocabulary.nicknames["ghost"] == nil)
    }
}

@Suite("Team Search Vocabulary — Bundled M-C")
struct BundledTeamSearchVocabularyTests {

    @Test("The bundled vocabulary loads and every entry in it resolves")
    func bundledVocabulary() throws {
        let vocabulary = try TeamSearchVocabulary.bundled(for: .mC)
        #expect(vocabulary.species.count == 231)
        #expect(vocabulary.speciesByID["arcanine"]?.formWords.contains("hisui") == true)
        #expect(vocabulary.speciesByID["tauros"]?.formWords
                    .isSuperset(of: ["paldea", "combat", "blaze", "aqua"]) == true)

        // Every nickname in team_search_vocab.json names an M-C species.
        let file = try #require(Bundle.main.url(forResource: "team_search_vocab", withExtension: "json"))
        let raw = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any]
        let nicknames = try #require(raw?["species_nicknames"] as? [String: String])
        #expect(vocabulary.nicknames.count == nicknames.count,
                "unknown nickname targets: \(nicknames.filter { vocabulary.nicknames[$0.key] == nil })")

        // Every style has a keyword and a signal, and its keywords parse to it.
        let parser = TeamQueryParser(vocabulary: vocabulary)
        for rule in vocabulary.archetypes {
            #expect(!rule.keywords.isEmpty)
            #expect(!(rule.signals.moves.isEmpty && rule.signals.abilities.isEmpty
                      && rule.signals.items.isEmpty))
            for keyword in rule.keywords {
                #expect(parser.parse(keyword).archetypes == [rule.archetype],
                        "\"\(keyword)\" didn't parse to \(rule.archetype.label)")
            }
        }
    }

    @Test("A typical description parses end to end")
    func typicalDescription() throws {
        let parser = TeamQueryParser(vocabulary: try TeamSearchVocabulary.bundled(for: .mC))
        let query = parser.parse("I want a Trick Room team with Mega Gardevoir and Hisuian Arcanine, no Incineroar")
        #expect(query.archetypes.map(\.id) == ["trick-room"])
        #expect(query.species.map(\.displayName) == ["Mega Gardevoir", "Arcanine (Hisui)"])
        #expect(query.excludedSpecies.map(\.name) == ["Incineroar"])
        #expect(query.unrecognized.isEmpty)
    }
}
