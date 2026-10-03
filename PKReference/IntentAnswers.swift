//
//  IntentAnswers.swift
//  PKReference
//
//  What the App Intents say, built apart from the intents so tests can
//  check it: how a Pokémon is named aloud and matched from what someone
//  said, a Pokémon's type matchups, the damage calc's and Team Search's
//  answers, speed comparisons, whether a Pokémon is legal in a regulation,
//  and saved sets and teams.
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

    /// The investments Siri offers, as players say them.
    enum Investment: Equatable, Sendable {
        case uninvested, full, fullWithNature
    }

    /// The investment in what someone said: "uninvested" or "no EVs";
    /// "max", "max def" or "252 Atk"; or one of those with a nature, "max
    /// Adamant", "max plus nature" or "252+ SpA". Nil when it's none of
    /// these, such as a saved set's name.
    static func investment(said text: String) -> Investment? {
        let said = key(text)
        guard !said.isEmpty else { return nil }
        if ["noinvest", "uninvest", "noev", "nostat", "zero"].contains(where: said.contains) || said == "none" {
            return .uninvested
        }
        guard ["max", "full", "252", "32"].contains(where: said.contains) else { return nil }
        let natures = ["nature", "plus", "positive", "boost",
                       "adamant", "modest", "bold", "calm", "jolly", "timid"]
        return natures.contains(where: said.contains) || text.contains("+") ? .fullWithNature : .full
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
    /// What lets the defender live through the hit: Focus Sash or Sturdy
    /// from full HP, or Disguise.
    var survival: SurvivalEffect? = nil

    /// "a guaranteed one-hit KO", "a two- to three-hit KO", or nil when it
    /// does no damage. When Sturdy or the like takes the first hit: "a
    /// guaranteed two-hit KO, since Sturdy leaves it at 1 HP from full HP".
    var knockOut: String? {
        guard maxPercent > 0 else { return nil }
        var fewest = Int((100 / maxPercent).rounded(.up))
        var most = minPercent > 0 ? Int((100 / minPercent).rounded(.up)) : 0
        var reason = ""
        if let survival, fewest == 1 {
            fewest = 2
            if most > 0 { most = max(most, 2) }
            reason = ", since \(survival.rawValue) \(survival.effect)"
        }
        if fewest == most { return "a guaranteed \(Self.spell(fewest))-hit KO\(reason)" }
        if most == 0 { return "a possible \(Self.spell(fewest))-hit KO\(reason)" }
        return "a \(Self.spell(fewest))- to \(Self.spell(most))-hit KO\(reason)"
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

// MARK: - Speed

nonisolated struct SpeedAnswer: Sendable {
    struct Side: Sendable {
        /// As it's said, and as its Mega when a saved set Mega Evolves.
        let name: String
        let speed: Int
        /// "full investment and a Speed nature", or "your set Scarf Koko,
        /// with Choice Scarf".
        let setup: String
        let championsRules: Bool
    }

    let first: Side
    let second: Side

    /// "Dragapult is faster: 213 Speed to Tapu Koko's 200." A tie says
    /// either could move first.
    var spoken: String {
        if first.speed == second.speed {
            return "\(first.name) and \(second.name) tie at \(first.speed) Speed, so either could move first."
        }
        let (faster, slower) = first.speed > second.speed ? (first, second) : (second, first)
        return "\(faster.name) is faster: \(faster.speed) Speed to \(slower.name)'s \(slower.speed)."
    }

    /// "Dragapult: full investment and a Speed nature. Tapu Koko: no
    /// investment. Champions rules, no field effects."
    var details: String {
        let rules: String
        switch (first.championsRules, second.championsRules) {
        case (true, true): rules = "Champions rules"
        case (false, false): rules = "Mainline rules"
        default:
            rules = "\(first.name) on \(first.championsRules ? "Champions" : "mainline") rules, "
                + "\(second.name) on \(second.championsRules ? "Champions" : "mainline") rules"
        }
        return "\(first.name): \(first.setup). \(second.name): \(second.setup). \(rules), no field effects."
    }
}

// MARK: - What beats a Pokémon

nonisolated struct CountersAnswer: Sendable {
    struct Pick: Sendable {
        /// As the results name it: "Mega Glimmora".
        let name: String
        let types: [String]
        let move: String
        let item: String
        /// "no investment", or "12 Special Attack and 20 Speed points".
        let investment: String
        let group: ProblemSolver.Group
        /// "107.9% – 127.7%".
        let damage: String
        /// Accuracy under 100% and drawbacks: "90% accurate".
        let notes: [String]

        /// "moving first", "using priority" or "moving second".
        var timing: String {
            switch group {
            case .outspeeds: "moving first"
            case .priority: "using priority"
            case .slower: "moving second"
            }
        }
    }

    /// As it's said, with the ability it was solved with: "Intimidate
    /// Incineroar", or "your set Bulky Roar".
    let target: String
    /// "Intimidate, full HP and Defense, a neutral nature".
    let setup: String
    /// "Regulation M-C".
    let regulation: String
    let pokemonCount: Int
    let wayCount: Int
    /// The best answer of each of the first three Pokémon.
    let top: [Pick]
    /// The target's Sturdy, Focus Sash or Disguise, which only some answers
    /// get past in one hit.
    var survival: SurvivalEffect? = nil

    /// "84 Pokémon in Regulation M-C can knock out Intimidate Incineroar in
    /// one hit. The best three: Empoleon's Surf, Milotic's Scald and
    /// Falinks's Close Combat, each with no investment, moving first."
    var spoken: String {
        guard pokemonCount > 0 else {
            let reason = survival.map { ": its \($0.rawValue) \($0.effect)" } ?? ""
            return "Nothing in \(regulation) knocks out \(target) in one hit, guaranteed\(reason)."
        }
        let count = pokemonCount == 1 ? "One Pokémon" : "\(pokemonCount) Pokémon"
        let past = survival.map { ", getting past its \($0.rawValue)" } ?? ""
        let lead = "\(count) in \(regulation) can knock out \(target) in one hit\(past)."
        let best = top.count == 1 ? "The best" : "The best \(Self.numbers[top.count] ?? "\(top.count)")"
        let tails = top.map { "with \($0.investment), \($0.timing)" }
        if Set(tails).count == 1, let tail = tails.first {
            let each = top.count == 1 ? "" : "each "
            return "\(lead) \(best): \(Self.list(top.map { "\($0.name)'s \($0.move)" })), \(each)\(tail)."
        }
        return "\(lead) \(best): \(Self.list(top.map { "\($0.name)'s \($0.move), with \($0.investment), \($0.timing)" }, separator: "; "))."
    }

    /// "Intimidate, full HP and Defense, a neutral nature. Regulation M-C,
    /// doubles, one hit from the lowest roll; 148 ways."
    var details: String {
        "\(setup). \(regulation), doubles, one hit from the lowest roll; \(wayCount) ways in all."
    }

    private static let numbers = [2: "two", 3: "three"]

    /// "A, B and C", or with `separator` "; ", "A; B; and C".
    private static func list(_ items: [String], separator: String = ", ") -> String {
        guard items.count > 1 else { return items.first ?? "" }
        let joiner = separator == ", " ? " and " : "; and "
        return items.dropLast().joined(separator: separator) + joiner + items.last!
    }
}

// MARK: - Legality

nonisolated struct LegalityAnswer: Sendable {
    enum Verdict: Equatable, Sendable {
        case legal
        /// Its species isn't in the regulation.
        case notInRegulation
        /// The regulation doesn't allow this kind of Mega: "Mega Evolution"
        /// or "Mega Rayquaza".
        case megaNotAllowed(String)
        /// Its species is in the regulation, but not this form or Mega.
        case formNotInRegulation(species: String)
    }

    /// As it's said: "Alolan Ninetales".
    let name: String
    /// "Regulation M-C".
    let regulation: String
    let verdict: Verdict
    /// "Regulation M-C runs from September 9, 2026 to December 2, 2026.",
    /// when its file has both dates.
    let schedule: String?

    var isLegal: Bool { verdict == .legal }

    /// "Yes, Incineroar is legal in Regulation M-C.", or no, and why.
    var spoken: String {
        switch verdict {
        case .legal:
            "Yes, \(name) is legal in \(regulation)."
        case .notInRegulation:
            "No, \(name) isn't in \(regulation)."
        case .megaNotAllowed(let what):
            "No, \(regulation) doesn't allow \(what)."
        case .formNotInRegulation(let species):
            "No, \(species) is in \(regulation), but not as \(name)."
        }
    }

    /// When a regulation runs, in the right tense for `now`. Its dates are
    /// days, stored as midnight UTC, so they're shown in UTC too.
    static func schedule(regulation: String, from: Date?, until: Date?, now: Date = .now) -> String? {
        guard let from, let until else { return nil }
        var style = Date.FormatStyle(date: .long, time: .omitted)
        style.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let start = from.formatted(style), end = until.formatted(style)
        if now < from { return "\(regulation) starts on \(start) and runs until \(end)." }
        // Its last day counts until that day is over.
        if now >= until.addingTimeInterval(24 * 60 * 60) { return "\(regulation) ran from \(start) to \(end)." }
        return "\(regulation) runs from \(start) to \(end)."
    }
}

/// Whether a Pokémon, or one of its forms, is in a regulation, from the
/// regulation's files: its list of species, and each species' Megas and
/// other forms.
nonisolated enum PokemonLegality {
    /// What a regulation lists for one species.
    struct Listing: Sendable {
        /// The Megas it allows, by name: "Mega Charizard X".
        let megas: [String]
        /// Its other forms, as the files name them: "Alola Form", "Hisuian
        /// Form", "White/Blue Plumage".
        let forms: [String]
    }

    /// - Parameters:
    ///   - formName: the Pokédex's form ("mega-x", "alola",
    ///     "paldea-combat-breed"), nil for the species itself.
    ///   - spokenName: the Pokémon as it's said, which is how Megas are
    ///     listed.
    ///   - listedSpecies: its species as the regulation lists it, or nil
    ///     when the regulation doesn't.
    ///   - speciesName: its species as it's said, for the answer.
    static func verdict(formName: String?, spokenName: String, listedSpecies: String?,
                        speciesName: String, rules: ChampionsRules, listing: Listing?) -> LegalityAnswer.Verdict {
        guard let listedSpecies else { return .notInRegulation }
        guard let form = formName?.lowercased(), !form.isEmpty else { return .legal }
        if form == "mega" || form.hasPrefix("mega-") {
            guard rules.megaEvolutionsAllowed else { return .megaNotAllowed("Mega Evolution") }
            if IntentNames.key(listedSpecies) == "rayquaza" && !rules.megaRayquazaAllowed {
                return .megaNotAllowed("Mega Rayquaza")
            }
            let megas = Set((listing?.megas ?? []).map(IntentNames.key))
            return megas.contains(IntentNames.key(spokenName)) ? .legal : .formNotInRegulation(species: speciesName)
        }
        let wanted = IntentNames.key(form)
        let listed = (listing?.forms ?? []).flatMap(formKeys)
        return listed.contains { wanted.hasPrefix($0) } ? .legal : .formNotInRegulation(species: speciesName)
    }

    /// The regional adjectives the files use, as the Pokédex's form names
    /// start.
    private static let regions = ["alolan": "alola", "galarian": "galar", "hisuian": "hisui", "paldean": "paldea"]

    /// A listed form as the start of the Pokédex's form names: "Hisuian
    /// Form" is "hisui", "Low Key Form" is "lowkey", and "White/Blue
    /// Plumage" is both "whiteplumage" and "blueplumage".
    static func formKeys(_ listed: String) -> [String] {
        var words = listed.split(separator: " ").map(String.init)
        if words.last?.lowercased() == "form" { words.removeLast() }
        guard let first = words.first else { return [] }
        let rest = words.dropFirst().joined()
        return first.split(separator: "/").map { alternative in
            let key = IntentNames.key(String(alternative) + rest)
            return regions[key] ?? key
        }
    }
}

// MARK: - Saved sets and teams

nonisolated struct SetAnswer: Sendable {
    let name: String
    /// As it's said.
    let pokemon: String
    let types: [String]
    let ability: String?
    let item: String?
    let nature: String?
    let level: Int
    let championsMode: Bool
    /// The stats it invests in, most first: "32 Atk", or "252 Atk".
    let investment: [String]
    let moves: [String]

    /// "Sample: Garchomp is Garchomp with Rough Skin and Choice Scarf, and a
    /// Jolly nature. Its moves are Earthquake, Dragon Claw, Rock Slide, and
    /// Protect."
    var spoken: String {
        var text = "\(name) is \(pokemon)"
        let held = [ability, item].compactMap { $0 }
        if !held.isEmpty { text += " with " + ListFormatter.localizedString(byJoining: held) }
        if let nature { text += (held.isEmpty ? " with" : ", and") + " a \(nature) nature" }
        text += "."
        text += moves.isEmpty ? " It has no moves yet."
            : " Its moves are \(ListFormatter.localizedString(byJoining: moves))."
        return text
    }

    /// "Level 50 · Champions · 32 Atk / 32 Spe / 2 HP".
    var details: String {
        var parts = ["Level \(level)", championsMode ? "Champions" : "Mainline"]
        parts.append(investment.isEmpty ? (championsMode ? "No stat points" : "No EVs")
                                        : investment.joined(separator: " / "))
        return parts.joined(separator: " · ")
    }

    /// Each stat with any EVs or stat points, most first, as "32 Atk".
    static func investment(hp: Int, atk: Int, def: Int, spAtk: Int, spDef: Int, speed: Int) -> [String] {
        let stats = [("HP", hp), ("Atk", atk), ("Def", def), ("SpA", spAtk), ("SpD", spDef), ("Spe", speed)]
        return stats.enumerated()
            .filter { $0.element.1 > 0 }
            .sorted { ($0.element.1, -$0.offset) > ($1.element.1, -$1.offset) }
            .map { "\($0.element.1) \($0.element.0)" }
    }
}

nonisolated struct TeamAnswer: Sendable {
    struct Member: Sendable {
        let name: String
        let types: [String]
        let item: String?
    }

    let name: String
    let members: [Member]
    /// "Regulation M-C" for a Champions team, which is checked against it;
    /// nil for a mainline team, which isn't.
    let regulation: String?
    /// What makes it illegal there, empty when it's legal.
    let problems: [String]
    /// What's legal but contradictory, such as a nature that lowers a stat
    /// its moves use.
    let warnings: [String]

    /// "Sand Offense: Tyranitar, Excadrill and Garchomp. It's legal in
    /// Regulation M-C."
    var spoken: String {
        guard !members.isEmpty else { return "\(name) has no Pokémon yet." }
        var text = "\(name): \(ListFormatter.localizedString(byJoining: members.map(\.name)))."
        guard let regulation else { return text }
        if let first = problems.first {
            text += " It isn't legal in \(regulation): \(first)"
            let more = problems.count - 1
            text += more == 0 ? "." : ", and \(more) more \(more == 1 ? "problem" : "problems")."
        } else {
            text += " It's legal in \(regulation)."
        }
        return text
    }
}
