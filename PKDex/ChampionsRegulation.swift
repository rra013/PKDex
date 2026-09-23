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
    var learnsetBundleResourceName: String { "champions-\(rawValue)-learnsets" }

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
        Self.cache.read(self) ?? Self.cache.populate(self)
    }

    // MARK: Private cache

    /// Process-wide cache of parsed whitelists. The class is `@unchecked
    /// Sendable` because the internal NSLock makes it thread-safe — every
    /// method body brackets its access. The `nonisolated` annotations let
    /// callers in any actor context hit the cache without an `await`.
    private final class Cache: @unchecked Sendable {
        nonisolated private let lock = NSLock()
        nonisolated(unsafe) private var sets: [ChampionsRegulation: Set<String>] = [:]

        nonisolated func read(_ reg: ChampionsRegulation) -> Set<String>? {
            lock.lock(); defer { lock.unlock() }
            return sets[reg]
        }

        /// Decodes the JSON for `reg` and caches it. If the bundle resource is
        /// missing or malformed, returns an empty set (the validator and Mon
        /// Index will simply show nothing, which is the safest fallback —
        /// nothing slips through as "legal").
        @discardableResult
        nonisolated func populate(_ reg: ChampionsRegulation) -> Set<String> {
            lock.lock(); defer { lock.unlock() }
            if let hit = sets[reg] { return hit }
            let parsed = ChampionsRegulation.loadWhitelistFromBundle(reg) ?? []
            sets[reg] = parsed
            return parsed
        }
    }

    nonisolated private static let cache = Cache()

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
