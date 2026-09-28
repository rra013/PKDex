//
//  ChampionsRegulation.swift
//  PKDex
//
//  Single source of truth for which species + items + rules are legal in each
//  Champions battle regulation. Each case maps to the pair of bundled JSONs
//  that already shipped with the app:
//
//      champions-<id>.json            — format definition + species whitelist
//      champions-<id>-learnsets.json  — per-species legal move pool
//
//  When a new regulation drops (e.g. Reg M-B):
//      1. Add the two new JSONs to the app bundle.
//      2. Add a `case mB` here.
//      3. Bump `current` so downstream code (Mon Index filter, validator,
//         AI opponent, set predictor) picks the new format up automatically.
//
//  Why an enum instead of three hand-curated Sets:
//  - Before this refactor, the species list lived in THREE places —
//    `champsDex.swift`, `pokedbPopulator.swift`, and `champions-m-a.json` —
//    and had drifted apart (Mon Index showed Ursaluna but not Scovillain).
//    Consolidating onto the JSON eliminates that whole class of bug.
//

import Foundation

enum ChampionsRegulation: String, CaseIterable, Identifiable, Sendable {
    case mA = "m-a"
    case mB = "m-b"
    case mC = "m-c"

    var id: String { rawValue }

    // MARK: Bundle wiring

    /// Filename (without extension) of the regulation definition JSON.
    /// Must match the file shipped under `PKDex/champions-<id>.json`.
    nonisolated var bundleResourceName: String { "champions-\(rawValue)" }

    /// Filename (without extension) of the per-species learnset JSON.
    nonisolated var learnsetBundleResourceName: String { "champions-\(rawValue)-learnsets" }

    // MARK: Display

    var displayName: String {
        switch self {
        case .mA: return "Regulation M-A"
        case .mB: return "Regulation M-B"
        case .mC: return "Regulation M-C"
        }
    }

    /// UserDefaults key the user-facing regulation picker writes to.
    nonisolated static let userDefaultsKey = "championsRegulationRaw"

    /// The "currently active" regulation, used wherever code reads from the
    /// regulation without an explicit override. Backed by `UserDefaults` so
    /// the user can switch between formats from Settings without re-launching
    /// the app — every read of `.current` returns whatever's stored. Defaults
    /// to `.latest` (whichever regulation has the most recent `valid_from`),
    /// so a fresh install always opens on the newest format and ships of M-C
    /// + future regulations get picked up automatically once their JSON lands.
    /// `nonisolated` because `UserDefaults.standard` is thread-safe and
    /// reachable from `@ModelActor` contexts (the Pokedex sync) without an
    /// `await` hop.
    nonisolated static var current: ChampionsRegulation {
        let raw = UserDefaults.standard.string(forKey: userDefaultsKey)
            ?? latest.rawValue
        return ChampionsRegulation(rawValue: raw) ?? latest
    }

    // MARK: Legal-period registry

    /// Window during which this regulation was/will be legal in
    /// Pokemon Champions ranked battle. Both bounds come from the bundled
    /// JSON (`valid_from`, `valid_until`). `nil` means the bound isn't
    /// recorded (e.g. a future regulation that's been data-mined but hasn't
    /// shipped — `valid_until` would be `nil` until the next regulation
    /// supersedes it).
    nonisolated struct LegalPeriod: Hashable, Sendable {
        let from: Date?
        let until: Date?

        func contains(_ date: Date) -> Bool {
            if let f = from, date < f { return false }
            if let u = until, date > u { return false }
            return true
        }
    }

    nonisolated var legalPeriod: LegalPeriod { Self.legalPeriods[self] ?? .init(from: nil, until: nil) }
    nonisolated var validFrom:  Date? { legalPeriod.from }
    nonisolated var validUntil: Date? { legalPeriod.until }

    /// The most recent regulation — the one with the latest `valid_from`.
    /// Cases without a `valid_from` are treated as oldest. Stable when ties
    /// exist (falls back to `allCases` order).
    nonisolated static var latest: ChampionsRegulation {
        allCases.max { (lhs, rhs) in
            let l = lhs.validFrom ?? .distantPast
            let r = rhs.validFrom ?? .distantPast
            return l < r
        } ?? .mA
    }

    /// Returns the regulation whose legal window contains `date`, or `nil`
    /// if `date` predates / postdates every shipped regulation. When two
    /// regulations' windows touch (e.g. M-A's last day == M-B's first day),
    /// the *newer* regulation wins — the changeover is always considered
    /// to have already happened by end-of-day.
    nonisolated static func legal(on date: Date) -> ChampionsRegulation? {
        // Search newest-first so changeover-day ties resolve to the new format.
        let sorted = allCases.sorted { ($0.validFrom ?? .distantPast) > ($1.validFrom ?? .distantPast) }
        return sorted.first { $0.legalPeriod.contains(date) }
    }

    /// Eagerly built dictionary of `regulation -> LegalPeriod`, populated
    /// once at first access by scanning the bundle for each case's JSON.
    /// Swift guarantees thread-safe initialization of `static let`.
    nonisolated private static let legalPeriods: [ChampionsRegulation: LegalPeriod] = {
        var out: [ChampionsRegulation: LegalPeriod] = [:]
        for reg in ChampionsRegulation.allCases {
            out[reg] = loadLegalPeriodFromBundle(reg) ?? .init(from: nil, until: nil)
        }
        return out
    }()

    nonisolated private static let legalPeriodDateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.calendar = Calendar(identifier: .gregorian)
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)
        df.dateFormat = "yyyy-MM-dd"
        return df
    }()

    nonisolated private static func loadLegalPeriodFromBundle(_ reg: ChampionsRegulation) -> LegalPeriod? {
        guard let url = Bundle.main.url(forResource: reg.bundleResourceName,
                                        withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let envelope = try? JSONDecoder().decode(ChampionsLegalPeriodEnvelope.self, from: data)
        else {
            return nil
        }
        return LegalPeriod(
            from:  envelope.valid_from.flatMap { legalPeriodDateFormatter.date(from: $0) },
            until: envelope.valid_until.flatMap { legalPeriodDateFormatter.date(from: $0) }
        )
    }

    // MARK: Species whitelist (cached)

    /// Title-cased base-species names allowed in this regulation. Mirrors
    /// `species_whitelist` from the bundled JSON. Lazily parsed and cached
    /// per case so the JSON only gets decoded once per process even if both
    /// the Mon Index and the validator hit it. `nonisolated` because the
    /// backing cache is itself thread-safe and the bundle access is read-only.
    nonisolated func speciesWhitelist() -> Set<String> {
        // A missing or malformed file gives an empty set: the validator and
        // Mon Index show nothing, so nothing slips through as "legal".
        Self.whitelistCache.value(for: self) { Self.loadWhitelistFromBundle($0) ?? [] }
    }

    // MARK: Rules (cached)

    /// The regulation's `rules` block: stat-point caps, team size, clauses
    /// and which battle gimmicks are allowed. Parsed once per case. A
    /// missing or malformed block gives `ChampionsRules.fallback`, the values
    /// every regulation so far has used; `RegulationRulesTests` checks each
    /// bundled file decodes, so the fallback shouldn't be reached.
    nonisolated func rules() -> ChampionsRules {
        Self.rulesCache.value(for: self) { Self.loadRulesFromBundle($0) ?? .fallback }
    }

    // MARK: Private cache

    /// Process-wide cache of values parsed from each regulation's JSON. The
    /// class is `@unchecked Sendable` because the internal NSLock makes it
    /// thread-safe — every method body brackets its access. The `nonisolated`
    /// annotations let callers in any actor context hit the cache without an
    /// `await`.
    private final class Cache<Value: Sendable>: @unchecked Sendable {
        nonisolated private let lock = NSLock()
        nonisolated(unsafe) private var values: [ChampionsRegulation: Value] = [:]

        /// The cached value for `reg`, loading it on first use.
        nonisolated func value(for reg: ChampionsRegulation,
                               load: (ChampionsRegulation) -> Value) -> Value {
            lock.lock(); defer { lock.unlock() }
            if let hit = values[reg] { return hit }
            let loaded = load(reg)
            values[reg] = loaded
            return loaded
        }
    }

    nonisolated private static let whitelistCache = Cache<Set<String>>()
    nonisolated private static let rulesCache = Cache<ChampionsRules>()

    /// Reads `species_whitelist` from the regulation's bundled JSON. Decoded
    /// with a minimal `Decodable` so future config fields (rules, item lists,
    /// mega stones…) don't break this loader — only the field we need has to
    /// be present.
    nonisolated private static func loadWhitelistFromBundle(_ reg: ChampionsRegulation) -> Set<String>? {
        guard let url = Bundle.main.url(forResource: reg.bundleResourceName,
                                        withExtension: "json") else {
            print("[ChampionsRegulation] missing bundle resource: \(reg.bundleResourceName).json")
            return nil
        }
        do {
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode(ChampionsWhitelistEnvelope.self, from: data)
            return Set(decoded.species_whitelist)
        } catch {
            print("[ChampionsRegulation] failed to decode \(reg.bundleResourceName).json: \(error)")
            return nil
        }
    }

    nonisolated private static func loadRulesFromBundle(_ reg: ChampionsRegulation) -> ChampionsRules? {
        guard let url = Bundle.main.url(forResource: reg.bundleResourceName,
                                        withExtension: "json") else { return nil }
        do {
            return try ChampionsRules.decode(fromRegulationJSON: Data(contentsOf: url))
        } catch {
            print("[ChampionsRegulation] failed to decode rules in \(reg.bundleResourceName).json: \(error)")
            return nil
        }
    }
}

// MARK: - Rules

/// A regulation's `rules` block, as its JSON spells it (snake case, decoded
/// by `convertFromSnakeCase`). The JSON is the source of truth: the app's
/// stat-point caps, the validator's team size and clauses, and whether Mega
/// Evolution is allowed all come from here.
///
/// Tera, Z-Moves and Dynamax are read but not yet used: the app has no UI
/// or battle support for them to switch off. `maxRestrictedPerTeam` waits
/// for a restricted-species list, which no regulation has yet.
nonisolated struct ChampionsRules: Decodable, Equatable, Sendable {
    let speciesClause: Bool
    let itemClause: Bool
    let statPointsMaxTotal: Int
    let statPointsMaxPerStat: Int
    let ivLockedAt: Int
    let teamSize: Int
    let maxRestrictedPerTeam: Int
    let megaEvolutionsAllowed: Bool
    let megaRayquazaAllowed: Bool
    let teraAllowed: Bool
    let zMovesAllowed: Bool
    let dynamaxAllowed: Bool

    /// The values every regulation so far (M-A to M-C) has used. Only for a
    /// file that can't be read.
    static let fallback = ChampionsRules(
        speciesClause: true, itemClause: false,
        statPointsMaxTotal: 66, statPointsMaxPerStat: 32, ivLockedAt: 31,
        teamSize: 6, maxRestrictedPerTeam: 0,
        megaEvolutionsAllowed: true, megaRayquazaAllowed: false,
        teraAllowed: false, zMovesAllowed: false, dynamaxAllowed: false)

    /// Whether `form` may be used: Mega Evolution must be allowed, and Mega
    /// Rayquaza, which needs no stone, has its own switch.
    func allowsMega(_ form: MegaForm) -> Bool {
        megaEvolutionsAllowed && (form.speciesKey != "rayquaza" || megaRayquazaAllowed)
    }

    /// The `rules` block of a whole regulation JSON file.
    static func decode(fromRegulationJSON data: Data) throws -> ChampionsRules {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(ChampionsRulesEnvelope.self, from: data).rules
    }
}

/// Just the `rules` block, so the rest of the file's fields don't matter.
nonisolated private struct ChampionsRulesEnvelope: Decodable, Sendable {
    let rules: ChampionsRules
}

/// File-scope decoder envelope. The project default is
/// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, which would otherwise pin
/// the Decodable conformance to MainActor and break the nonisolated loader.
/// Marking the type `nonisolated` keeps the conformance reachable from any
/// actor context.
nonisolated private struct ChampionsWhitelistEnvelope: Decodable, Sendable {
    let species_whitelist: [String]
}

/// Minimal envelope just for the legal-period fields. Both bounds are
/// optional so older JSONs without the field still parse.
nonisolated private struct ChampionsLegalPeriodEnvelope: Decodable, Sendable {
    let valid_from:  String?
    let valid_until: String?
}
