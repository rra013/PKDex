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
    // case mB = "m-b"   // add here when the next regulation drops

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
        }
    }

    /// The "currently active" regulation, used wherever code reads from the
    /// regulation without an explicit override. Bump this when a new format
    /// goes live (and keep the old case around so legacy validators / saved
    /// teams can still reference it). `nonisolated` so it's reachable from
    /// `@ModelActor` contexts (the Pokedex sync) without an `await` hop —
    /// the enum value itself is immutable.
    nonisolated static let current: ChampionsRegulation = .mA

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
