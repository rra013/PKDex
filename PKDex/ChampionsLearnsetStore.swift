//
//  ChampionsLearnsetStore.swift
//  PKDex
//
//  Loads `champions-<id>-learnsets.json` for the active regulation and
//  exposes per-species data (abilities, base stats, learnset, megas,
//  alternate forms) for use by the Champions detail view. The JSON keys are
//  base species names; regional and Hisuian variants live nested under their
//  base species' `alternate_forms`.
//
//  One store is loaded per regulation, cached forever once parsed.
//  `.shared` always returns the store for `ChampionsRegulation.current`, so
//  flipping the regulation in Settings causes the next `.shared` access to
//  serve M-B (or whichever format is now active) with no callsite changes.
//

import Foundation

struct ChampionsBaseStats: Hashable {
    let hp: Int
    let atk: Int
    let def: Int
    let spa: Int
    let spd: Int
    let spe: Int

    var total: Int { hp + atk + def + spa + spd + spe }
}

struct ChampionsForm: Hashable, Identifiable {
    let name: String
    let abilities: [String]
    let stats: ChampionsBaseStats?
    /// Megas inherit the base species' learnset, so this is `nil`. Alternate
    /// forms carry their own move list.
    let moves: [String]?

    var id: String { name }
}

struct ChampionsSpecies: Hashable {
    let name: String
    let abilities: [String]
    let stats: ChampionsBaseStats
    /// Already sorted alphabetically.
    let moves: [String]
    let megas: [ChampionsForm]
    let alternateForms: [ChampionsForm]
}

final class ChampionsLearnsetStore {
    /// Store for the active regulation. Recomputed on each access — the
    /// underlying cache makes this an `O(1)` dictionary lookup once warm.
    static var shared: ChampionsLearnsetStore {
        store(for: ChampionsRegulation.current)
    }

    /// Returns the cached store for `regulation`, parsing the bundled
    /// learnsets JSON on first access. Thread-safe via `cacheLock`.
    static func store(for regulation: ChampionsRegulation) -> ChampionsLearnsetStore {
        cacheLock.lock(); defer { cacheLock.unlock() }
        if let hit = cache[regulation] { return hit }
        let store = ChampionsLearnsetStore(regulation: regulation)
        cache[regulation] = store
        return store
    }

    private static let cacheLock = NSLock()
    nonisolated(unsafe) private static var cache: [ChampionsRegulation: ChampionsLearnsetStore] = [:]

    private let bySpecies: [String: ChampionsSpecies]

    /// Every ability slug used by any base / mega / alt form in this
    /// regulation, sorted by display name. Precomputed at init so the
    /// filter sheet doesn't pay the roster-scan + 250x cache-lookup cost
    /// per `.body` evaluation of `PokedexTab` (every keystroke in the
    /// search bar was burning ~5–10ms here).
    let allAbilities: [String]

    /// Every move name reachable by any species in this regulation
    /// (base + alt-form learnsets; megas inherit base), sorted
    /// case-insensitively. Same one-shot precomputation as `allAbilities`.
    let allMoves: [String]

    private init(regulation: ChampionsRegulation) {
        let bySpecies = Self.loadBundledData(regulation: regulation)
        self.bySpecies = bySpecies

        var abilitySet: Set<String> = []
        var moveSet: Set<String> = []
        for species in bySpecies.values {
            abilitySet.formUnion(species.abilities)
            moveSet.formUnion(species.moves)
            for mega in species.megas {
                abilitySet.formUnion(mega.abilities)
            }
            for alt in species.alternateForms {
                abilitySet.formUnion(alt.abilities)
                if let moves = alt.moves {
                    moveSet.formUnion(moves)
                }
            }
        }
        self.allAbilities = abilitySet.sorted {
            formatAbilityName($0).localizedCaseInsensitiveCompare(formatAbilityName($1)) == .orderedAscending
        }
        self.allMoves = moveSet.sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }

    func data(for speciesName: String) -> ChampionsSpecies? {
        bySpecies[speciesName]
    }

    private static func loadBundledData(regulation: ChampionsRegulation) -> [String: ChampionsSpecies] {
        guard let url = Bundle.main.url(forResource: regulation.learnsetBundleResourceName,
                                        withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = root["species"] as? [String: [String: Any]]
        else {
            return [:]
        }

        var out: [String: ChampionsSpecies] = [:]
        for (key, entry) in entries {
            guard let stats = parseStats(entry["stats"]) else { continue }
            let abilities = (entry["abilities"] as? [String]) ?? []
            let moves = ((entry["moves"] as? [String]) ?? []).sorted()
            let megas = parseForms(entry["megas"])
            let altForms = parseForms(entry["alternate_forms"])
            out[key] = ChampionsSpecies(name: key,
                                        abilities: abilities,
                                        stats: stats,
                                        moves: moves,
                                        megas: megas,
                                        alternateForms: altForms)
        }
        return out
    }

    private static func parseStats(_ raw: Any?) -> ChampionsBaseStats? {
        guard let dict = raw as? [String: Int],
              let hp = dict["hp"], let atk = dict["atk"], let def = dict["def"],
              let spa = dict["spa"], let spd = dict["spd"], let spe = dict["spe"]
        else { return nil }
        return ChampionsBaseStats(hp: hp, atk: atk, def: def, spa: spa, spd: spd, spe: spe)
    }

    private static func parseForms(_ raw: Any?) -> [ChampionsForm] {
        guard let array = raw as? [[String: Any]] else { return [] }
        return array.compactMap { dict in
            guard let name = dict["name"] as? String else { return nil }
            let abilities = (dict["abilities"] as? [String]) ?? []
            let stats = parseStats(dict["stats"])
            let moves = (dict["moves"] as? [String])?.sorted()
            return ChampionsForm(name: name, abilities: abilities, stats: stats, moves: moves)
        }
    }
}
