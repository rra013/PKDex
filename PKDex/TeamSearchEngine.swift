//
//  TeamSearchEngine.swift
//  PKDex
//
//  Finds the tournament teams that match a `TeamQuery` and groups them into
//  popular compositions. Pure and `nonisolated`: it runs anywhere, and the
//  tests drive it with a fixed clock.
//
//  1. Index: each corpus team's members get a species identity, the Mega
//     they can become, and their moves. The team gets its style tags,
//     worked out from moves, abilities (after Mega Evolution, so Charizardite
//     Y counts as Drought) and items.
//  2. Filter: every requested species, move and style must be present, and
//     nothing excluded may be. When fewer than `minFullMatches` teams pass
//     and the query names two or more species, teams missing exactly one of
//     them come back as partial matches, weighted down.
//  3. Group: teams with the same six Pokémon form a group. Groups that share
//     all but one Pokémon with a more popular one fold into it as variants.
//     Most teams are unique at six (396 distinct sets in 622 M-C teams), so
//     the popularity is in near-identical teams.
//  4. Rank: each team weighs placement × recency. A composition scores the
//     sum of its teams' weights.
//

import Foundation

// MARK: - Index

nonisolated struct IndexedMember: Sendable {
    /// Limitless's display name: "Hisuian Arcanine".
    let name: String
    let identity: TeamSearchVocabulary.Identity
    /// The Mega it can become: it holds one of its own species' stones.
    let mega: TeamSearchVocabulary.Mega?
    let moves: Set<ShowdownID>
}

nonisolated struct IndexedTeam: Sendable, Identifiable {
    let team: CorpusTeam
    let members: [IndexedMember]
    /// Sorted identity keys: the exact-composition grouping key.
    let speciesKeys: [String]
    let moves: Set<ShowdownID>
    let tags: Set<TeamArchetype>
    /// The event's start, parsed once here: date parsing is slow enough to
    /// dominate a search if it's repeated per team.
    let eventDate: Date?

    var id: String { team.id }
}

nonisolated struct TeamSearchIndex: Sendable {
    let teams: [IndexedTeam]
    /// Styles in vocabulary order, for listing a composition's tags.
    let archetypes: [TeamArchetype]

    init(corpus: TeamCorpus, vocabulary: TeamSearchVocabulary) {
        var dates: [String: Date?] = [:]
        teams = corpus.teams.map { team in
            let id = team.tournament.id
            if dates[id] == nil { dates[id] = .some(team.tournament.parsedDate) }
            return Self.index(team, eventDate: dates[id] ?? nil, vocabulary: vocabulary)
        }
        archetypes = vocabulary.archetypes.map(\.archetype)
    }

    static func index(_ team: CorpusTeam, eventDate: Date?,
                      vocabulary: TeamSearchVocabulary) -> IndexedTeam {
        let members = team.members.map { member -> IndexedMember in
            let identity = vocabulary.identity(name: member.name, slug: member.limitlessID)
            return IndexedMember(
                name: member.name, identity: identity,
                mega: vocabulary.mega(heldItem: member.item, speciesID: identity.speciesID),
                moves: Set((member.attacks ?? []).map(toID)))
        }
        return IndexedTeam(
            team: team, members: members,
            speciesKeys: members.map(\.identity.key).sorted(),
            moves: members.reduce(into: Set()) { $0.formUnion($1.moves) },
            tags: tags(for: team.members, megas: members.map(\.mega), vocabulary: vocabulary),
            eventDate: eventDate)
    }

    /// The styles a team shows. Abilities include each Mega's, since a Mega
    /// Stone decides the ability once it Mega Evolves.
    static func tags(for members: [LimitlessStanding.TeamMember],
                     megas: [TeamSearchVocabulary.Mega?],
                     vocabulary: TeamSearchVocabulary) -> Set<TeamArchetype> {
        var moves = Set<ShowdownID>(), abilities = Set<ShowdownID>(), items = Set<ShowdownID>()
        for (member, mega) in zip(members, megas) {
            moves.formUnion((member.attacks ?? []).map(toID))
            if let ability = member.ability { abilities.insert(toID(ability)) }
            if let item = member.item { items.insert(toID(item)) }
            if let mega { abilities.formUnion(mega.abilities) }
        }
        return Set(vocabulary.archetypes.filter { rule in
            rule.signals.matches(moves: moves, abilities: abilities, items: items)
                && (rule.requires?.matches(moves: moves, abilities: abilities, items: items) ?? true)
        }.map(\.archetype))
    }
}

// MARK: - Results

nonisolated struct ScoredTeam: Sendable, Identifiable {
    let team: IndexedTeam
    /// Placement × recency, halved for a partial match.
    let weight: Double
    /// Requested species this team lacks. Empty for a full match.
    let missing: [SpeciesTerm]

    var isPartial: Bool { !missing.isEmpty }
    var id: String { team.id }
}

nonisolated struct TeamComposition: Sendable, Identifiable {
    /// A group folded in that differs from the core by one Pokémon.
    struct Variant: Sendable {
        let added: [String]
        let removed: [String]
        let teams: [ScoredTeam]
    }

    /// The core group's species key.
    let id: String
    /// The core's Pokémon, as Limitless names them, in its best team's order.
    let species: [String]
    /// Every matching team, core and variants, heaviest first.
    let teams: [ScoredTeam]
    let variants: [Variant]
    let score: Double
    /// No team in it has every requested species.
    let isPartial: Bool
    let missing: [SpeciesTerm]
    /// Styles on at least half its teams, in vocabulary order.
    let tags: [TeamArchetype]
    let eventCount: Int
    /// The best-placed team, if any team has a placing.
    let bestTeam: ScoredTeam?
    /// Why it matched: "Mega Gardevoir", "Trick Room", "No Incineroar",
    /// or "Missing Garchomp" for a partial match.
    let reasons: [String]
}

// MARK: - Engine

nonisolated enum TeamSearchEngine {

    struct Configuration: Sendable {
        /// Below this many full matches, partial matches are added.
        var minFullMatches = 10
        /// A partial match's weight is multiplied by this.
        var partialFactor = 0.5
        /// A team's weight halves every this many days after its event.
        var recencyHalfLifeDays = 14.0
    }

    static func search(_ query: TeamQuery, in index: TeamSearchIndex, now: Date,
                       configuration: Configuration = Configuration()) -> [TeamComposition] {
        var full: [ScoredTeam] = []
        var partial: [ScoredTeam] = []
        for team in index.teams where passesEverythingButSpecies(team, query) {
            let missing = query.species.filter { !contains(team, $0) }
            if missing.isEmpty {
                full.append(ScoredTeam(team: team, weight: teamWeight(team, now: now,
                                                                      configuration: configuration),
                                       missing: []))
            } else if missing.count == 1 && query.species.count >= 2 {
                let weight = teamWeight(team, now: now, configuration: configuration)
                partial.append(ScoredTeam(team: team, weight: weight * configuration.partialFactor,
                                          missing: missing))
            }
        }
        let matches = full.count >= configuration.minFullMatches ? full : full + partial
        return group(matches, query: query, archetypes: index.archetypes)
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                if lhs.teams.count != rhs.teams.count { return lhs.teams.count > rhs.teams.count }
                return lhs.id < rhs.id
            }
    }

    // MARK: Matching

    static func member(_ member: IndexedMember, matches term: SpeciesTerm) -> Bool {
        guard member.identity.speciesID == term.speciesID else { return false }
        var forms = Set(term.formWords)
        if forms.remove("male") != nil, member.identity.formWords.contains("female") {
            return false
        }
        guard forms.isSubset(of: member.identity.formWords) else { return false }
        switch term.mega {
        case nil: return true
        case .any?: return member.mega != nil
        case .variant(let variant)?: return member.mega?.variant == variant
        }
    }

    static func contains(_ team: IndexedTeam, _ term: SpeciesTerm) -> Bool {
        team.members.contains { member($0, matches: term) }
    }

    private static func passesEverythingButSpecies(_ team: IndexedTeam, _ query: TeamQuery) -> Bool {
        query.excludedSpecies.allSatisfy { !contains(team, $0) }
            && query.moves.allSatisfy { team.moves.contains($0.id) }
            && query.excludedMoves.allSatisfy { !team.moves.contains($0.id) }
            && query.archetypes.allSatisfy { team.tags.contains($0) }
            && query.excludedArchetypes.allSatisfy { !team.tags.contains($0) }
    }

    // MARK: Weights

    /// 1 for last place or no placing, rising by 1 for each halving of the
    /// field ahead of you: the winner of a 388-player event weighs about 9.6.
    static func placementWeight(placing: Int?, players: Int) -> Double {
        guard let placing, placing > 0, players > 0 else { return 1 }
        return 1 + max(0, log2(Double(players)) - log2(Double(placing)))
    }

    /// Halves every `halfLifeDays` after the event. An undated event isn't
    /// discounted.
    static func recencyWeight(eventDate: Date?, now: Date, halfLifeDays: Double) -> Double {
        guard let eventDate else { return 1 }
        let days = max(0, now.timeIntervalSince(eventDate) / 86_400)
        return pow(0.5, days / halfLifeDays)
    }

    private static func teamWeight(_ team: IndexedTeam, now: Date,
                                   configuration: Configuration) -> Double {
        placementWeight(placing: team.team.standing.placing, players: team.team.tournament.players)
            * recencyWeight(eventDate: team.eventDate, now: now,
                            halfLifeDays: configuration.recencyHalfLifeDays)
    }

    // MARK: Grouping

    /// Teams with exactly the same Pokémon.
    private struct ExactGroup {
        let key: String
        let keys: Set<String>
        let teams: [ScoredTeam]
        let weight: Double
    }

    /// A composition in the making: its core group and the groups folded in.
    private struct FoldedGroup {
        let core: ExactGroup
        var variants: [ExactGroup] = []
    }

    private static func group(_ teams: [ScoredTeam], query: TeamQuery,
                              archetypes: [TeamArchetype]) -> [TeamComposition] {
        // Exact compositions, heaviest first. Ties go to the key, so the
        // folding below is deterministic.
        let byKey = Dictionary(grouping: teams) { $0.team.speciesKeys.joined(separator: "|") }
        var exact: [ExactGroup] = []
        for (key, members) in byKey {
            let weight = members.reduce(0.0) { $0 + $1.weight }
            exact.append(ExactGroup(key: key, keys: Set(members[0].team.speciesKeys),
                                    teams: members.sorted(by: heavierFirst), weight: weight))
        }
        exact.sort { $0.weight != $1.weight ? $0.weight > $1.weight : $0.key < $1.key }

        // Fold each group into the first, heavier composition it shares all
        // but one Pokémon with. Comparing every group with every composition
        // is slow for a few hundred of each, so compositions are indexed by
        // their cores' "all but one" subsets: two sets sharing all but one
        // member have such a subset in common (or one set is a subset of the
        // other's).
        var folded: [FoldedGroup] = []
        var candidates: [String: [Int]] = [:]
        for group in exact {
            let probes = allButOneSubsets(group.keys) + [subsetKey(group.keys)]
            let match = probes.flatMap { candidates[$0] ?? [] }
                .sorted()
                .first { sharesAllButOne(group.keys, folded[$0].core.keys) }
            if let match {
                folded[match].variants.append(group)
            } else {
                folded.append(FoldedGroup(core: group))
                for key in allButOneSubsets(group.keys) + [subsetKey(group.keys)] {
                    candidates[key, default: []].append(folded.count - 1)
                }
            }
        }
        return folded.map { composition($0, query: query, archetypes: archetypes) }
    }

    /// The set with each member left out in turn, as keys. Empty sets are
    /// skipped: they'd match everything.
    private static func allButOneSubsets(_ keys: Set<String>) -> [String] {
        guard keys.count > 1 else { return [] }
        return keys.map { left in subsetKey(keys.subtracting([left])) }
    }

    private static func subsetKey(_ keys: Set<String>) -> String {
        keys.sorted().joined(separator: "|")
    }

    /// Five of six, for full teams. At least one must be shared, so tiny
    /// teams don't all fold together.
    private static func sharesAllButOne(_ a: Set<String>, _ b: Set<String>) -> Bool {
        let shared = a.intersection(b).count
        return shared > 0 && shared >= max(a.count, b.count) - 1
    }

    private static func heavierFirst(_ a: ScoredTeam, _ b: ScoredTeam) -> Bool {
        a.weight != b.weight ? a.weight > b.weight : a.id < b.id
    }

    private static func composition(_ group: FoldedGroup, query: TeamQuery,
                                    archetypes: [TeamArchetype]) -> TeamComposition {
        let core = group.core
        let teams = (core.teams + group.variants.flatMap(\.teams)).sorted(by: heavierFirst)

        // Each identity's most common Limitless name, for display.
        var nameCounts: [String: [String: Int]] = [:]
        for member in teams.flatMap(\.team.members) {
            nameCounts[member.identity.key, default: [:]][member.name, default: 0] += 1
        }
        func name(_ key: String) -> String {
            let counts = nameCounts[key] ?? [:]
            let top = counts.max { lhs, rhs in
                lhs.value != rhs.value ? lhs.value < rhs.value : lhs.key > rhs.key
            }
            return top?.key ?? key
        }

        var tagCounts: [TeamArchetype: Int] = [:]
        for team in teams {
            for tag in team.team.tags { tagCounts[tag, default: 0] += 1 }
        }
        let partial = teams.allSatisfy(\.isPartial)
        let missing = partial ? teams[0].missing : []
        let placed = teams.filter { $0.team.team.standing.placing != nil }
        let bestTeam = placed.min { lhs, rhs in
            let l = lhs.team.team, r = rhs.team.team
            if l.standing.placing != r.standing.placing {
                return (l.standing.placing ?? .max) < (r.standing.placing ?? .max)
            }
            return l.tournament.players > r.tournament.players
        }
        let variants = group.variants.map { variant in
            TeamComposition.Variant(
                added: variant.keys.subtracting(core.keys).sorted().map(name),
                removed: core.keys.subtracting(variant.keys).sorted().map(name),
                teams: variant.teams)
        }

        return TeamComposition(
            id: core.key,
            species: core.teams[0].team.members.map { name($0.identity.key) },
            teams: teams,
            variants: variants,
            score: teams.reduce(0.0) { $0 + $1.weight },
            isPartial: partial,
            missing: missing,
            tags: archetypes.filter { 2 * (tagCounts[$0] ?? 0) >= teams.count },
            eventCount: Set(teams.map(\.team.team.tournament.id)).count,
            bestTeam: bestTeam,
            reasons: reasons(for: query, missing: missing))
    }

    private static func reasons(for query: TeamQuery, missing: [SpeciesTerm]) -> [String] {
        var reasons: [String] = query.species.filter { !missing.contains($0) }.map(\.displayName)
        reasons += query.archetypes.map(\.label)
        reasons += query.moves.map(\.name)
        reasons += missing.map { "Missing \($0.displayName)" }
        reasons += query.excludedSpecies.map { "No \($0.displayName)" }
        reasons += query.excludedArchetypes.map { "No \($0.label)" }
        reasons += query.excludedMoves.map { "No \($0.name)" }
        return reasons
    }
}
