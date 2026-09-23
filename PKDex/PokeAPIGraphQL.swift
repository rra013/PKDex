//
//  PokeAPIGraphQL.swift
//  PKDex
//

import Foundation
import SwiftData

// MARK: - GraphQL Fetcher

actor PokeGraphQLFetcher {
    // The legacy `beta.pokeapi.co/graphql/v1beta` endpoint is stale and is
    // missing Legends Z-A content (e.g. Mega Scovillain / Spicy Spray). The
    // current production endpoint at `graphql.pokeapi.co/v1beta2` mirrors
    // the up-to-date REST data at `pokeapi.co/api/v2/`. The v1beta2 schema
    // drops the `pokemon_v2_` prefix on every table/relationship name but
    // keeps scalar field names (`is_default`, `is_hidden`, `base_stat`, etc.)
    // unchanged.
    private let endpoint = URL(string: "https://graphql.pokeapi.co/v1beta2")!

    private func execute<T: Decodable>(query: String, type: T.Type) async throws -> T {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120
        let body = ["query": query]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw GraphQLError.badResponse
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    // MARK: - Fetch Default Pokemon (types + base stats + abilities + learnset)

    func fetchAllPokemon() async throws -> [GQLPokemon] {
        let query = """
        {
          pokemon(where: {is_default: {_eq: true}}, order_by: {id: asc}) {
            id
            name
            pokemon_species_id
            pokemontypes {
              type { name }
            }
            pokemonstats {
              base_stat
              stat { name }
            }
            pokemonabilities {
              ability { name }
              is_hidden
            }
            pokemonmoves(distinct_on: move_id) {
              move_id
            }
            pokemonspecy {
              evolves_from_species_id
            }
          }
        }
        """
        let result = try await execute(query: query, type: GQLPokemonResponse.self)
        return result.data.pokemon
    }

    // MARK: - Fetch Alternate Forms (Megas, Regionals, etc.)

    func fetchAllForms() async throws -> [GQLPokemon] {
        let query = """
        {
          pokemon(where: {is_default: {_eq: false}}, order_by: {id: asc}) {
            id
            name
            pokemon_species_id
            pokemontypes {
              type { name }
            }
            pokemonstats {
              base_stat
              stat { name }
            }
            pokemonabilities {
              ability { name }
              is_hidden
            }
            pokemonforms {
              form_name
            }
          }
        }
        """
        let result = try await execute(query: query, type: GQLPokemonResponse.self)
        return result.data.pokemon
    }

    // MARK: - Fetch Moves

    func fetchAllMoves() async throws -> [GQLMove] {
        let query = """
        {
          move {
            id
            name
            generation_id
            power
            accuracy
            pp
            priority
            type { name }
            movedamageclass { name }
            movemeta {
              min_hits
              max_hits
              drain
              healing
              crit_rate
            }
          }
        }
        """
        let result = try await execute(query: query, type: GQLMoveResponse.self)
        return result.data.move
    }

    enum GraphQLError: Error {
        case badResponse
    }
}

// MARK: - GraphQL Response DTOs

nonisolated struct GQLPokemonResponse: Decodable, Sendable {
    let data: PokemonData
    nonisolated struct PokemonData: Decodable, Sendable {
        let pokemon: [GQLPokemon]
    }
}

nonisolated struct GQLPokemon: Decodable, Sendable {
    let id: Int
    let name: String
    let pokemon_species_id: Int?
    let pokemontypes: [GQLPokemonType]
    let pokemonstats: [GQLPokemonStat]
    let pokemonabilities: [GQLPokemonAbility]
    let pokemonmoves: [GQLPokemonMove]?
    let pokemonforms: [GQLPokemonForm]?
    let pokemonspecy: GQLPokemonSpecies?

    nonisolated struct GQLPokemonType: Decodable, Sendable {
        let type: TypeName
        nonisolated struct TypeName: Decodable, Sendable { let name: String }
    }
    nonisolated struct GQLPokemonStat: Decodable, Sendable {
        let base_stat: Int
        let stat: StatName
        nonisolated struct StatName: Decodable, Sendable { let name: String }
    }
    nonisolated struct GQLPokemonAbility: Decodable, Sendable {
        let ability: AbilityName
        let is_hidden: Bool
        nonisolated struct AbilityName: Decodable, Sendable { let name: String }
    }
    nonisolated struct GQLPokemonMove: Decodable, Sendable {
        let move_id: Int
    }
    nonisolated struct GQLPokemonForm: Decodable, Sendable {
        let form_name: String?
    }
    nonisolated struct GQLPokemonSpecies: Decodable, Sendable {
        let evolves_from_species_id: Int?
    }
}

nonisolated struct GQLMoveResponse: Decodable, Sendable {
    let data: MoveDataContainer
    nonisolated struct MoveDataContainer: Decodable, Sendable {
        let move: [GQLMove]
    }
}

nonisolated struct GQLMove: Decodable, Sendable {
    let id: Int
    let name: String
    let generation_id: Int
    let power: Int?
    let accuracy: Int?
    let pp: Int?
    let priority: Int?
    let type: TypeRef
    let movedamageclass: DamageClassRef
    let movemeta: [GQLMoveMeta]

    nonisolated struct TypeRef: Decodable, Sendable { let name: String }
    nonisolated struct DamageClassRef: Decodable, Sendable { let name: String }

    nonisolated struct GQLMoveMeta: Decodable, Sendable {
        let min_hits: Int?
        let max_hits: Int?
        let drain: Int?
        let healing: Int?
        let crit_rate: Int?
    }
}

// MARK: - Helpers

nonisolated private func formatPokemonName(_ raw: String) -> String {
    raw.split(separator: "-").map { $0.capitalized }.joined(separator: "-")
}

nonisolated private func parseStats(_ gqlStats: [GQLPokemon.GQLPokemonStat]) -> [String: Int] {
    var stats: [String: Int] = [:]
    for s in gqlStats { stats[s.stat.name] = s.base_stat }
    return stats
}

nonisolated private func parseTypes(_ gqlTypes: [GQLPokemon.GQLPokemonType]) -> [String] {
    gqlTypes.map { $0.type.name.capitalized }
}

nonisolated private func parseAbilities(_ gqlAbilities: [GQLPokemon.GQLPokemonAbility]) -> (a1: String?, a2: String?, ha: String?) {
    let normal = gqlAbilities.filter { !$0.is_hidden }
    let hidden = gqlAbilities.filter { $0.is_hidden }
    return (
        normal.first?.ability.name,
        normal.count > 1 ? normal[1].ability.name : nil,
        hidden.first?.ability.name
    )
}

// MARK: - Learnset Inheritance

/// Input for the learnset inheritance algorithm.
struct SpeciesLearnsetEntry {
    let speciesID: Int
    var moveIDs: [Int]
    let evolvesFromSpeciesID: Int?
}

/// Merges pre-evolution moves into each species' learnset by walking evolution chains.
/// Returns a dictionary mapping speciesID -> merged move ID set.
func inheritLearnsets(_ entries: [SpeciesLearnsetEntry]) -> [Int: Set<Int>] {
    var speciesMap: [Int: SpeciesLearnsetEntry] = [:]
    for entry in entries {
        speciesMap[entry.speciesID] = entry
    }

    var result: [Int: Set<Int>] = [:]
    for speciesID in speciesMap.keys {
        var inherited = Set(speciesMap[speciesID]!.moveIDs)
        var current = speciesMap[speciesID]?.evolvesFromSpeciesID
        var visited = Set<Int>()
        while let preEvoID = current, !visited.contains(preEvoID) {
            visited.insert(preEvoID)
            if let preEvo = speciesMap[preEvoID] {
                inherited.formUnion(preEvo.moveIDs)
                current = preEvo.evolvesFromSpeciesID
            } else {
                break
            }
        }
        result[speciesID] = inherited
    }
    return result
}

// MARK: - Sync Manager

@ModelActor
actor CalcDataSyncManager {

    func syncCalcData() async throws {
        let fetcher = PokeGraphQLFetcher()

        // Fetch all three datasets in parallel
        async let pokemonTask = fetcher.fetchAllPokemon()
        async let formsTask = fetcher.fetchAllForms()
        async let movesTask = fetcher.fetchAllMoves()

        let (pokemon, forms, moves) = try await (pokemonTask, formsTask, movesTask)

        // Clear existing data
        try modelContext.delete(model: PKMNStats.self)
        try modelContext.delete(model: MoveData.self)
        try modelContext.save()

        // Build base-species lookup for learnset sharing and cosmetic-form filtering
        struct SpeciesInfo {
            let stats: [String: Int]
            let types: [String]
        }
        var speciesInfoMap: [Int: SpeciesInfo] = [:]

        // Build learnset entries and inherit pre-evo moves
        var learnsetEntries: [SpeciesLearnsetEntry] = []
        for p in pokemon {
            let types = parseTypes(p.pokemontypes)
            let stats = parseStats(p.pokemonstats)
            let moveIDs = (p.pokemonmoves ?? []).map { $0.move_id }
            let speciesID = p.pokemon_species_id ?? p.id
            let evolvesFrom = p.pokemonspecy?.evolves_from_species_id

            speciesInfoMap[speciesID] = SpeciesInfo(stats: stats, types: types)
            learnsetEntries.append(SpeciesLearnsetEntry(speciesID: speciesID, moveIDs: moveIDs, evolvesFromSpeciesID: evolvesFrom))
        }

        let inheritedLearnsets = await inheritLearnsets(learnsetEntries)

        // Insert default Pokemon with inherited learnsets
        for p in pokemon {
            let types = parseTypes(p.pokemontypes)
            let stats = parseStats(p.pokemonstats)
            let abilities = parseAbilities(p.pokemonabilities)
            let speciesID = p.pokemon_species_id ?? p.id
            let moveIDs = Array(inheritedLearnsets[speciesID] ?? [])

            let entry = PKMNStats(
                id: p.id,
                speciesID: speciesID,
                name: formatPokemonName(p.name),
                type1: types.first ?? "Normal",
                type2: types.count > 1 ? types[1] : nil,
                baseHP: stats["hp"] ?? 1,
                baseAtk: stats["attack"] ?? 1,
                baseDef: stats["defense"] ?? 1,
                baseSpAtk: stats["special-attack"] ?? 1,
                baseSpDef: stats["special-defense"] ?? 1,
                baseSpeed: stats["speed"] ?? 1,
                ability1: abilities.a1,
                ability2: abilities.a2,
                hiddenAbility: abilities.ha,
                learnableMoveIDs: moveIDs
            )
            modelContext.insert(entry)
        }

        // Insert alternate forms, skipping cosmetic ones (same stats + same types as base)
        var formsInserted = 0
        for f in forms {
            let speciesID = f.pokemon_species_id ?? f.id
            let types = parseTypes(f.pokemontypes)
            let stats = parseStats(f.pokemonstats)

            // Skip cosmetic forms (identical stats and types to base species)
            if let base = speciesInfoMap[speciesID] {
                if stats == base.stats && types == base.types { continue }
            }

            let abilities = parseAbilities(f.pokemonabilities)
            let formName = f.pokemonforms?.first?.form_name
            // Inherit learnset from base species (with egg move inheritance)
            let moveIDs = Array(inheritedLearnsets[speciesID] ?? [])

            let entry = PKMNStats(
                id: f.id,
                speciesID: speciesID,
                name: formatPokemonName(f.name),
                formName: formName,
                type1: types.first ?? "Normal",
                type2: types.count > 1 ? types[1] : nil,
                baseHP: stats["hp"] ?? 1,
                baseAtk: stats["attack"] ?? 1,
                baseDef: stats["defense"] ?? 1,
                baseSpAtk: stats["special-attack"] ?? 1,
                baseSpDef: stats["special-defense"] ?? 1,
                baseSpeed: stats["speed"] ?? 1,
                ability1: abilities.a1,
                ability2: abilities.a2,
                hiddenAbility: abilities.ha,
                learnableMoveIDs: moveIDs
            )
            modelContext.insert(entry)
            formsInserted += 1
        }

        // Insert Moves
        for m in moves {
            let meta = m.movemeta.first

            let displayName = m.name
                .split(separator: "-")
                .map { $0.capitalized }
                .joined(separator: " ")

            let entry = MoveData(
                id: m.id,
                name: displayName,
                type: m.type.name.capitalized,
                damageClass: m.movedamageclass.name,
                power: m.power,
                accuracy: m.accuracy,
                pp: m.pp ?? 0,
                priority: m.priority ?? 0,
                minHits: meta?.min_hits,
                maxHits: meta?.max_hits,
                drain: meta?.drain ?? 0,
                healing: meta?.healing ?? 0,
                critRate: meta?.crit_rate ?? 0,
                generationId: m.generation_id
            )
            modelContext.insert(entry)
        }

        try modelContext.save()
        print("Calc data synced: \(pokemon.count) Pokemon, \(formsInserted) forms, \(moves.count) moves")
    }
}
