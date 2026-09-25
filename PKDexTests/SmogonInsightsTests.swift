//
//  SmogonInsightsTests.swift
//  PKDexTests
//
//  Covers `SmogonInsights` and the name mapping behind it: Smogon species
//  names as Team Search terms, "often paired with" suggestions for one or
//  several requested species, and usage by species. Uses the fixture
//  vocabulary and hand-made stats.
//

import Testing
import Foundation
@testable import PKDex

@Suite("Smogon Insights")
struct SmogonInsightsTests {

    private typealias F = TeamSearchFixtures

    private static let usage = SmogonUsage(
        format: "gen9championsvgc2026regmb", month: "2026-08", rating: 1760, battles: 100,
        species: [
            .init(name: "Incineroar", usage: 0.4, teammates: [
                .init(name: "Garchomp", share: 0.5), .init(name: "Sinistcha", share: 0.45),
                .init(name: "Charizard-Mega-Y", share: 0.3), .init(name: "Pikachu", share: 0.9)]),
            .init(name: "Garchomp", usage: 0.3, teammates: [
                .init(name: "Incineroar", share: 0.6), .init(name: "Charizard-Mega-Y", share: 0.5),
                .init(name: "Whimsicott", share: 0.4)]),
            .init(name: "Charizard", usage: 0.1, teammates: [.init(name: "Torkoal", share: 0.8)]),
            .init(name: "Charizard-Mega-Y", usage: 0.3, teammates: [
                .init(name: "Garchomp", share: 0.7), .init(name: "Whimsicott", share: 0.5)]),
            .init(name: "Indeedee", usage: 0.05, teammates: [.init(name: "Farigiraf", share: 0.6)]),
            .init(name: "Indeedee-F", usage: 0.15, teammates: [
                .init(name: "Farigiraf", share: 0.2), .init(name: "Gardevoir", share: 0.5)]),
        ])

    private static let insights = SmogonInsights(usage: usage, vocabulary: F.vocabulary)

    /// (name, rounded share) pairs, for comparing without float noise.
    private func suggest(_ text: String) -> [String] {
        Self.insights.suggestions(for: F.parser.parse(text)).map {
            "\($0.term.displayName) \(Int(($0.share * 1000).rounded()))"
        }
    }

    // MARK: Names

    @Test("Smogon names map to terms with their Megas and forms")
    func names() {
        func name(_ showdown: String) -> String? {
            F.vocabulary.term(showdownName: showdown)?.displayName
        }
        #expect(name("Charizard-Mega-Y") == "Mega Charizard Y")
        #expect(name("Charizard-Mega-X") == "Mega Charizard X")
        #expect(name("Charizard") == "Charizard")
        #expect(name("Floette-Mega") == "Mega Floette")
        #expect(name("Floette-Eternal") == "Floette")
        #expect(name("Gengar-Mega") == "Mega Gengar")
        #expect(name("Arcanine-Hisui") == "Arcanine (Hisui)")
        #expect(name("Indeedee-F") == "Indeedee (Female)")
        #expect(name("Kommo-o") == "Kommo-o")
        #expect(name("Mr. Rime") == "Mr. Rime")
        #expect(name("Pikachu") == nil)
    }

    // MARK: Suggestions

    @Test("One species: its teammates, most paired first; unknown species dropped")
    func oneSpecies() {
        #expect(suggest("incineroar") == ["Garchomp 500", "Sinistcha 450", "Mega Charizard Y 300"])
    }

    @Test("Several species: teammates of all of them, by the lowest share")
    func severalSpecies() {
        #expect(suggest("incineroar and garchomp") == ["Mega Charizard Y 300"])
    }

    @Test("Species already named or excluded aren't suggested")
    func skipsTaken() {
        #expect(suggest("incineroar, no garchomp") == ["Sinistcha 450", "Mega Charizard Y 300"])
    }

    @Test("A Mega request reads the Mega's stats; a plain species reads all of its entries")
    func megasAndPlainSpecies() {
        #expect(suggest("mega charizard y") == ["Garchomp 700", "Whimsicott 500"])
        // Charizard 0.1 + Mega Charizard Y 0.3, weighted by usage.
        #expect(suggest("charizard") == ["Garchomp 525", "Whimsicott 375", "Torkoal 200"])
    }

    @Test("Forms: female, male (not female), or both")
    func forms() {
        #expect(suggest("indeedee female") == ["Gardevoir 500", "Farigiraf 200"])
        #expect(suggest("indeedee male") == ["Farigiraf 600"])
        #expect(suggest("indeedee") == ["Gardevoir 375", "Farigiraf 300"])
    }

    @Test("No suggestions when a requested species isn't in the stats, or none is named")
    func noData() {
        #expect(suggest("kingambit").isEmpty)
        #expect(suggest("incineroar and kingambit").isEmpty)
        #expect(suggest("trick room").isEmpty)
    }

    // MARK: Usage

    @Test("Usage adds up a species' forms and Megas")
    func usageBySpecies() throws {
        #expect(abs(try #require(Self.insights.usage(ofSpecies: "charizard")) - 0.4) < 1e-9)
        #expect(abs(try #require(Self.insights.usage(ofSpecies: "indeedee")) - 0.2) < 1e-9)
        #expect(Self.insights.usage(ofSpecies: "kingambit") == nil)
    }
}
