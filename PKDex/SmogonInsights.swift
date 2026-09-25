//
//  SmogonInsights.swift
//  PKDex
//
//  Team Search's view of Smogon's ladder usage stats: which teammates pair
//  well with the Pokémon a description names ("often paired with"), and how
//  widely each Pokémon is used. Smogon's species names are mapped to Team
//  Search's species terms once, so Megas and forms line up with queries:
//  "Mega Charizard Y" reads Smogon's Charizard-Mega-Y entry, and a plain
//  "Charizard" reads all of Charizard's entries, weighted by usage.
//

import Foundation

nonisolated struct SmogonInsights: Sendable {

    struct Suggestion: Sendable, Identifiable, Equatable {
        let term: SpeciesTerm
        /// For one requested species, the share of its teams that also run
        /// this teammate. For several, the lowest such share across them.
        let share: Double

        var id: String { term.displayName }
    }

    private struct Entry: Sendable {
        let term: SpeciesTerm
        let usage: Double
        let teammates: [(term: SpeciesTerm, share: Double)]
    }

    let usage: SmogonUsage
    private let entries: [Entry]

    init(usage: SmogonUsage, vocabulary: TeamSearchVocabulary) {
        self.usage = usage
        var terms: [String: SpeciesTerm?] = [:]
        func term(_ name: String) -> SpeciesTerm? {
            if let known = terms[name] { return known }
            let mapped = vocabulary.term(showdownName: name)
            terms[name] = .some(mapped)
            return mapped
        }
        entries = usage.species.compactMap { species in
            guard let entryTerm = term(species.name) else { return nil }
            return Entry(term: entryTerm, usage: species.usage,
                         teammates: species.teammates.compactMap { mate in
                             term(mate.name).map { ($0, mate.share) }
                         })
        }
    }

    /// Teammates for the species a query asks for, most-paired first. A
    /// teammate must pair with every requested species, and is scored by
    /// its lowest share across them. Species the query already names, or
    /// excludes, aren't suggested. Empty when a requested species isn't in
    /// the stats.
    func suggestions(for query: TeamQuery, limit: Int = 8) -> [Suggestion] {
        guard !query.species.isEmpty else { return [] }
        var lowest: [SpeciesTerm: Double]?
        for requested in query.species {
            let shares = teammateShares(for: requested)
            guard !shares.isEmpty else { return [] }
            lowest = lowest.map { current in
                current.reduce(into: [:]) { result, pair in
                    if let share = shares[pair.key] { result[pair.key] = min(pair.value, share) }
                }
            } ?? shares
        }
        let taken = Set((query.species + query.excludedSpecies).map(\.speciesID))
        return (lowest ?? [:])
            .filter { !taken.contains($0.key.speciesID) }
            .map { Suggestion(term: $0.key, share: $0.value) }
            .sorted { $0.share != $1.share ? $0.share > $1.share : $0.id < $1.id }
            .prefix(limit)
            .map { $0 }
    }

    /// Share of ladder teams that run the species in any form or as a Mega.
    /// Its entries never share a team (species clause), so the shares add.
    /// nil when the stats don't include it.
    func usage(ofSpecies speciesID: String) -> Double? {
        let matching = entries.filter { $0.term.speciesID == speciesID }
        return matching.isEmpty ? nil : matching.reduce(0) { $0 + $1.usage }
    }

    /// A requested species' teammate shares, averaged over the entries it
    /// covers and weighted by their usage.
    private func teammateShares(for requested: SpeciesTerm) -> [SpeciesTerm: Double] {
        let matching = entries.filter { covers(requested, $0.term) }
        let total = matching.reduce(0) { $0 + $1.usage }
        guard total > 0 else { return [:] }
        var shares: [SpeciesTerm: Double] = [:]
        for entry in matching {
            for (mate, share) in entry.teammates {
                shares[mate, default: 0] += share * entry.usage / total
            }
        }
        return shares
    }

    /// Whether a requested species includes a Smogon entry, with the same
    /// form and Mega rules as the search engine.
    private func covers(_ requested: SpeciesTerm, _ entry: SpeciesTerm) -> Bool {
        guard requested.speciesID == entry.speciesID else { return false }
        var forms = Set(requested.formWords)
        if forms.remove("male") != nil, entry.formWords.contains("female") { return false }
        guard forms.isSubset(of: entry.formWords) else { return false }
        switch requested.mega {
        case nil: return true
        case .any?: return entry.mega != nil
        case .variant(let variant)?: return entry.mega == .variant(variant)
        }
    }
}
