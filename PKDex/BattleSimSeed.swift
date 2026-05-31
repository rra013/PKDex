//
//  BattleSimSeed.swift
//  PKDex
//

import Foundation
import SwiftData

/// One-time seeder that inserts a handful of pre-built spreads and teams so a fresh
/// install can demo the Battle Simulator without first building a team by hand.
enum BattleSimSeed {
    static let seedKey = "battleSimSeededV1"

    @MainActor
    static func seedIfNeeded(modelContainer: ModelContainer) {
        if UserDefaults.standard.bool(forKey: seedKey) { return }

        let context = ModelContext(modelContainer)

        guard let allPokemon = try? context.fetch(FetchDescriptor<PKMNStats>()),
              let allMoves = try? context.fetch(FetchDescriptor<MoveData>()),
              !allPokemon.isEmpty, !allMoves.isEmpty else {
            // Calc data isn't ready yet; try again next launch.
            return
        }

        var byName: [String: SavedSpread] = [:]
        for def in spreads {
            guard let spread = makeSpread(def: def, pokemon: allPokemon, moves: allMoves) else { continue }
            context.insert(spread)
            byName[def.name] = spread
        }

        for teamDef in teams {
            let slots = teamDef.spreadNames.compactMap { name -> TeamSlotInfo? in
                guard let spread = byName[name],
                      let pid = spread.pokemonID,
                      let pkmn = allPokemon.first(where: { $0.id == pid }) else { return nil }
                return TeamSlotInfo.from(spread: spread, pokemon: pkmn, moves: allMoves)
            }
            guard !slots.isEmpty else { continue }
            context.insert(SavedTeam(name: teamDef.name, slots: slots))
        }

        do {
            try context.save()
            UserDefaults.standard.set(true, forKey: seedKey)
        } catch {
            print("BattleSimSeed save failed: \(error)")
        }
    }

    // MARK: - Definitions

    private struct SeedSpread {
        let name: String
        let pokemon: String
        let nature: String
        let ability: String?
        let item: HeldItem
        let level: Int
        let evHP: Int; let evAtk: Int; let evDef: Int
        let evSpAtk: Int; let evSpDef: Int; let evSpeed: Int
        let moves: [String]
    }

    private struct SeedTeam {
        let name: String
        let spreadNames: [String]
    }

    private static let spreads: [SeedSpread] = [
        SeedSpread(name: "Sample: Garchomp (Physical)", pokemon: "Garchomp",
                   nature: "jolly", ability: "rough-skin", item: .lifeOrb, level: 50,
                   evHP: 4, evAtk: 252, evDef: 0, evSpAtk: 0, evSpDef: 0, evSpeed: 252,
                   moves: ["Earthquake", "Outrage", "Stone Edge", "Fire Fang"]),

        SeedSpread(name: "Sample: Tyranitar (Band)", pokemon: "Tyranitar",
                   nature: "adamant", ability: "sand-stream", item: .choiceBand, level: 50,
                   evHP: 4, evAtk: 252, evDef: 0, evSpAtk: 0, evSpDef: 0, evSpeed: 252,
                   moves: ["Crunch", "Stone Edge", "Earthquake", "Ice Punch"]),

        SeedSpread(name: "Sample: Excadrill (Sand Rush)", pokemon: "Excadrill",
                   nature: "adamant", ability: "sand-rush", item: .lifeOrb, level: 50,
                   evHP: 4, evAtk: 252, evDef: 0, evSpAtk: 0, evSpDef: 0, evSpeed: 252,
                   moves: ["Earthquake", "Iron Head", "Rock Slide", "Rapid Spin"]),

        SeedSpread(name: "Sample: Heatran (Specs)", pokemon: "Heatran",
                   nature: "modest", ability: "flash-fire", item: .choiceSpecs, level: 50,
                   evHP: 4, evAtk: 0, evDef: 0, evSpAtk: 252, evSpDef: 0, evSpeed: 252,
                   moves: ["Fire Blast", "Earth Power", "Flash Cannon", "Magma Storm"]),

        SeedSpread(name: "Sample: Dragapult (Mixed)", pokemon: "Dragapult",
                   nature: "timid", ability: "infiltrator", item: .lifeOrb, level: 50,
                   evHP: 0, evAtk: 0, evDef: 0, evSpAtk: 252, evSpDef: 4, evSpeed: 252,
                   moves: ["Shadow Ball", "Draco Meteor", "Flamethrower", "U-turn"]),

        SeedSpread(name: "Sample: Tapu Koko (Surge)", pokemon: "Tapu Koko",
                   nature: "timid", ability: "electric-surge", item: .lifeOrb, level: 50,
                   evHP: 0, evAtk: 0, evDef: 4, evSpAtk: 252, evSpDef: 0, evSpeed: 252,
                   moves: ["Thunderbolt", "Dazzling Gleam", "Volt Switch", "U-turn"]),
    ]

    private static let teams: [SeedTeam] = [
        SeedTeam(name: "Sample: Sand Offense",
                 spreadNames: [
                    "Sample: Tyranitar (Band)",
                    "Sample: Excadrill (Sand Rush)",
                    "Sample: Garchomp (Physical)",
                 ]),
        SeedTeam(name: "Sample: Special Offense",
                 spreadNames: [
                    "Sample: Heatran (Specs)",
                    "Sample: Dragapult (Mixed)",
                    "Sample: Tapu Koko (Surge)",
                 ]),
    ]

    // MARK: - Helpers

    private static func makeSpread(def: SeedSpread,
                                   pokemon: [PKMNStats],
                                   moves: [MoveData]) -> SavedSpread? {
        let key = normalize(def.pokemon)
        guard let pkmn = pokemon.first(where: { normalize($0.name) == key && !$0.isForm })
            ?? pokemon.first(where: { normalize($0.name) == key }) else {
            return nil
        }

        let moveIDs: [Int?] = (0..<4).map { i in
            guard i < def.moves.count else { return nil }
            let k = normalize(def.moves[i])
            return moves.first(where: { normalize($0.name) == k })?.id
        }

        return SavedSpread(
            name: def.name,
            pokemonID: pkmn.id,
            pokemonName: pkmn.name,
            abilityName: def.ability,
            itemRawValue: def.item == .none ? nil : def.item.rawValue,
            championsMode: false,
            natureID: def.nature,
            level: def.level,
            evHP: def.evHP, evAtk: def.evAtk, evDef: def.evDef,
            evSpAtk: def.evSpAtk, evSpDef: def.evSpDef, evSpeed: def.evSpeed,
            ivHP: 31, ivAtk: 31, ivDef: 31,
            ivSpAtk: 31, ivSpDef: 31, ivSpeed: 31,
            moveID1: moveIDs[0], moveID2: moveIDs[1],
            moveID3: moveIDs[2], moveID4: moveIDs[3]
        )
    }

    /// Normalizes Pokemon and move names so lookups succeed regardless of whether the
    /// data source uses "Will-O-Wisp", "will-o-wisp", or "willowisp".
    static func normalize(_ s: String) -> String {
        s.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}
