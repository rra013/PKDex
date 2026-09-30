//
//  IntentAnswers.swift
//  PKDex
//
//  What the App Intents say, built apart from the intents so tests can
//  check it: how a Pokémon is named aloud and matched from what someone
//  said, a Pokémon's type matchups, and the damage calc's and Team
//  Search's answers.
//

import Foundation

// MARK: - Names

nonisolated enum IntentNames {
    /// Regional forms, said as adjectives.
    private static let regional = ["alola": "Alolan", "galar": "Galarian",
                                   "hisui": "Hisuian", "paldea": "Paldean"]

    /// How a Pokémon is said: "Mega Charizard X", "Alolan Ninetales",
    /// "Mr Mime", "Rotom (Wash)".
    static func spoken(name: String, formName: String?) -> String {
        let base = baseName(name: name, formName: formName)
        guard let form = formName?.lowercased(), !form.isEmpty else { return base }
        if form == "mega" || form.hasPrefix("mega-") {
            let letter = form.dropFirst("mega".count).replacingOccurrences(of: "-", with: "").uppercased()
            return letter.isEmpty ? "Mega \(base)" : "Mega \(base) \(letter)"
        }
        if let adjective = regional[form] { return "\(adjective) \(base)" }
        let words = form.split(separator: "-").map { $0.capitalized }.joined(separator: " ")
        return "\(base) (\(words))"
    }

    /// The name without its form, with spaces for hyphens:
    /// "Charizard-Mega-X" is "Charizard", "Mr-Mime" is "Mr Mime".
    static func baseName(name: String, formName: String?) -> String {
        var base = name
        if let form = formName, !form.isEmpty, base.lowercased().hasSuffix("-" + form.lowercased()) {
            base.removeLast(form.count + 1)
        }
        return base.replacingOccurrences(of: "-", with: " ")
    }

    /// What matching compares: letters and digits, lowercased, accents
    /// dropped. "Mr. Mime" and "Flabébé" become "mrmime" and "flabebe".
    static func key(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .lowercased().filter { $0.isLetter || $0.isNumber }
    }

    /// The ways a Pokémon might be said, as keys: its stored and spoken
    /// names, and a form either side of the name ("Charizard Mega X",
    /// "Alola Ninetales").
    static func keys(name: String, formName: String?) -> Set<String> {
        var result: Set<String> = [key(name), key(spoken(name: name, formName: formName))]
        if let form = formName, !form.isEmpty {
            let base = baseName(name: name, formName: form)
            result.insert(key(base + form))
            result.insert(key(form + base))
        }
        return result
    }

    struct Candidate: Sendable {
        let id: Int
        let keys: Set<String>
        /// Shorter names rank first among partial matches.
        let length: Int
    }

    /// The candidates `query` names, best first: every exact match if there
    /// is one ("Garchomp" isn't also Mega Garchomp); otherwise up to ten
    /// whose keys start with it, then contain it.
    static func matches(_ query: String, in candidates: [Candidate]) -> [Int] {
        let wanted = key(query)
        guard !wanted.isEmpty else { return [] }
        let exact = candidates.filter { $0.keys.contains(wanted) }
        if !exact.isEmpty { return exact.map(\.id) }
        let ranked: [(rank: Int, candidate: Candidate)] = candidates.compactMap { candidate in
            if candidate.keys.contains(where: { $0.hasPrefix(wanted) }) { return (1, candidate) }
            if candidate.keys.contains(where: { $0.contains(wanted) }) { return (2, candidate) }
            return nil
        }
        return ranked
            .sorted { ($0.rank, $0.candidate.length, $0.candidate.id) < ($1.rank, $1.candidate.length, $1.candidate.id) }
            .prefix(10).map(\.candidate.id)
    }
}

// MARK: - Looking up a Pokémon

nonisolated struct PokemonLookupAnswer: Sendable {
    let name: String
    let types: [String]
    let baseStatTotal: Int
    /// Attacking types by how much they do, by type alone: 4, 2, ½, ¼ and
    /// 0. Types that do normal damage aren't listed.
    let matchups: [(multiplier: Double, types: [String])]

    static let multipliers: [Double] = [4, 2, 0.5, 0.25, 0]

    init(name: String, types: [String], baseStats: [Int], chart: TypeChart.Chart = TypeChart.bundled) {
        self.name = name
        self.types = types
        self.baseStatTotal = baseStats.reduce(0, +)
        matchups = Self.multipliers.compactMap { multiplier in
            let attacking = chart.types.filter { chart.multiplier($0, against: types) == multiplier }
            return attacking.isEmpty ? nil : (multiplier, attacking)
        }
    }

    /// "Garchomp is Dragon and Ground type, with a base stat total of 600.
    /// By type, it takes 4 times damage from Ice; 2 times from Dragon and
    /// Fairy; half from Fire, Poison and Rock; and none from Electric."
    var spoken: String {
        let typeList = ListFormatter.localizedString(byJoining: types)
        var text = "\(name) is \(typeList) type, with a base stat total of \(baseStatTotal)."
        let clauses = matchups.enumerated().map { index, matchup in
            let amount = Self.amount(matchup.multiplier)
            let from = ListFormatter.localizedString(byJoining: matchup.types)
            return index == 0 ? "\(amount) damage from \(from)" : "\(amount) from \(from)"
        }
        if let first = clauses.first {
            let rest = clauses.dropFirst()
            let joined = rest.isEmpty ? first
                : clauses.dropLast().joined(separator: "; ") + "; and " + clauses.last!
            text += " By type, it takes \(joined)."
        }
        return text
    }

    /// A multiplier as it's said.
    static func amount(_ multiplier: Double) -> String {
        switch multiplier {
        case 4: "4 times"
        case 2: "2 times"
        case 0.5: "half"
        case 0.25: "a quarter"
        default: "none"
        }
    }

    /// A multiplier as it's shown, as on a Pokémon's page.
    static func symbol(_ multiplier: Double) -> String {
        switch multiplier {
        case 4: "4×"
        case 2: "2×"
        case 0.5: "½×"
        case 0.25: "¼×"
        default: "Immune"
        }
    }
}

// MARK: - Damage

nonisolated struct DamageAnswer: Sendable {
    let attacker: String
    let defender: String
    let move: String
    let minPercent: Double
    let maxPercent: Double
    let minDamage: Int
    let maxDamage: Int
    /// Each side's ability and stats, as the answer says them:
    /// "Sand Veil, no investment".
    let attackerSetup: String
    let defenderSetup: String
    let championsRules: Bool

    /// "a guaranteed one-hit KO", "a two- to three-hit KO", or nil when it
    /// does no damage.
    var knockOut: String? {
        guard maxPercent > 0 else { return nil }
        let fewest = Int((100 / maxPercent).rounded(.up))
        let most = minPercent > 0 ? Int((100 / minPercent).rounded(.up)) : 0
        if fewest == most { return "a guaranteed \(Self.spell(fewest))-hit KO" }
        if most == 0 { return "a possible \(Self.spell(fewest))-hit KO" }
        return "a \(Self.spell(fewest))- to \(Self.spell(most))-hit KO"
    }

    /// "Garchomp's Earthquake does 161.4% to 195.2% to Heatran: a
    /// guaranteed one-hit KO."
    var spoken: String {
        guard let knockOut else { return "\(attacker)'s \(move) does no damage to \(defender)." }
        return "\(attacker)'s \(move) does \(Self.percent(minPercent)) to \(Self.percent(maxPercent)) to \(defender): \(knockOut)."
    }

    /// "Garchomp: Sand Veil, no investment. Heatran: Flash Fire, no
    /// investment. Champions rules, no field effects."
    var details: String {
        "\(attacker): \(attackerSetup). \(defender): \(defenderSetup). "
            + (championsRules ? "Champions rules" : "Mainline rules") + ", no field effects."
    }

    static func percent(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1))) + "%"
    }

    /// "one" to "ten", then digits.
    private static func spell(_ count: Int) -> String {
        guard count <= 10 else { return "\(count)" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .spellOut
        formatter.locale = Locale(identifier: "en")
        return formatter.string(from: NSNumber(value: count)) ?? "\(count)"
    }
}

// MARK: - Team Search

nonisolated struct TeamSearchAnswer: Sendable {
    struct Composition: Sendable {
        let species: [String]
        let teams: Int
    }

    let query: String
    let compositions: Int
    let teams: Int
    /// The best few, best first.
    let top: [Composition]

    /// "592 compositions, from 1,348 teams, match "Trick Room". The top one,
    /// from 64 teams: Charizard, Golisopod, …"
    var spoken: String {
        guard let best = top.first else { return "No tournament teams match \"\(query)\"." }
        let plural = compositions == 1 ? "composition" : "compositions"
        let names = ListFormatter.localizedString(byJoining: best.species)
        return "\(compositions.formatted()) \(plural), from \(teams.formatted()) teams, match \"\(query)\". "
            + "The top one, from \(best.teams.formatted()) teams: \(names)."
    }
}
