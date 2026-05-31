//
//  ChampionsLearnsetStore.swift
//  PKDex
//
//  Loads `champions-m-a-learnsets.json` once and exposes per-species data
//  (abilities, base stats, learnset, megas, alternate forms) for use by the
//  Champions detail view. The JSON keys are base species names; regional and
//  Hisuian variants live nested under their base species' `alternate_forms`.
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
    static let shared = ChampionsLearnsetStore()

    private let bySpecies: [String: ChampionsSpecies]

    private init() {
        self.bySpecies = Self.loadBundledData()
    }

    func data(for speciesName: String) -> ChampionsSpecies? {
        bySpecies[speciesName]
    }

    private static func loadBundledData() -> [String: ChampionsSpecies] {
        guard let url = Bundle.main.url(forResource: "champions-m-a-learnsets",
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
