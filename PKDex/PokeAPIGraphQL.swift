//
//  PokeAPIGraphQL.swift
//  PKDex
//

import Foundation
import SwiftData

// MARK: - GraphQL Fetcher

actor PokeGraphQLFetcher {
    private let endpoint = URL(string: "https://beta.pokeapi.co/graphql/v1beta")!

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
          pokemon_v2_pokemon(where: {is_default: {_eq: true}}, order_by: {id: asc}) {
            id
            name
            pokemon_species_id
            pokemon_v2_pokemontypes {
              pokemon_v2_type { name }
            }
            pokemon_v2_pokemonstats {
              base_stat
              pokemon_v2_stat { name }
            }
            pokemon_v2_pokemonabilities {
              pokemon_v2_ability { name }
              is_hidden
            }
            pokemon_v2_pokemonmoves(distinct_on: move_id) {
              move_id
            }
          }
        }
        """
        let result = try await execute(query: query, type: GQLPokemonResponse.self)
        return result.data.pokemon_v2_pokemon
    }

    // MARK: - Fetch Alternate Forms (Megas, Regionals, etc.)

    func fetchAllForms() async throws -> [GQLPokemon] {
        let query = """
        {
          pokemon_v2_pokemon(where: {is_default: {_eq: false}}, order_by: {id: asc}) {
            id
            name
            pokemon_species_id
            pokemon_v2_pokemontypes {
              pokemon_v2_type { name }
            }
            pokemon_v2_pokemonstats {
              base_stat
              pokemon_v2_stat { name }
            }
            pokemon_v2_pokemonabilities {
              pokemon_v2_ability { name }
              is_hidden
            }
            pokemon_v2_pokemonforms {
              form_name
            }
          }
        }
        """
        let result = try await execute(query: query, type: GQLPokemonResponse.self)
        return result.data.pokemon_v2_pokemon
    }

    // MARK: - Fetch Moves

    func fetchAllMoves() async throws -> [GQLMove] {
        let query = """
        {
          pokemon_v2_move {
            id
            name
            power
            accuracy
            pp
            priority
            pokemon_v2_type { name }
            pokemon_v2_movedamageclass { name }
            pokemon_v2_movemeta {
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
        return result.data.pokemon_v2_move
    }

    enum GraphQLError: Error {
        case badResponse
    }
}

// MARK: - GraphQL Response DTOs

nonisolated struct GQLPokemonResponse: Decodable, Sendable {
    let data: PokemonData
    nonisolated struct PokemonData: Decodable, Sendable {
        let pokemon_v2_pokemon: [GQLPokemon]
    }
}

nonisolated struct GQLPokemon: Decodable, Sendable {
    let id: Int
    let name: String
    let pokemon_species_id: Int?
    let pokemon_v2_pokemontypes: [GQLPokemonType]
    let pokemon_v2_pokemonstats: [GQLPokemonStat]
    let pokemon_v2_pokemonabilities: [GQLPokemonAbility]
    let pokemon_v2_pokemonmoves: [GQLPokemonMove]?
    let pokemon_v2_pokemonforms: [GQLPokemonForm]?

    nonisolated struct GQLPokemonType: Decodable, Sendable {
        let pokemon_v2_type: TypeName
        nonisolated struct TypeName: Decodable, Sendable { let name: String }
    }
    nonisolated struct GQLPokemonStat: Decodable, Sendable {
        let base_stat: Int
        let pokemon_v2_stat: StatName
        nonisolated struct StatName: Decodable, Sendable { let name: String }
    }
    nonisolated struct GQLPokemonAbility: Decodable, Sendable {
        let pokemon_v2_ability: AbilityName
        let is_hidden: Bool
        nonisolated struct AbilityName: Decodable, Sendable { let name: String }
    }
    nonisolated struct GQLPokemonMove: Decodable, Sendable {
        let move_id: Int
    }
    nonisolated struct GQLPokemonForm: Decodable, Sendable {
        let form_name: String?
    }
}

nonisolated struct GQLMoveResponse: Decodable, Sendable {
    let data: MoveDataContainer
    nonisolated struct MoveDataContainer: Decodable, Sendable {
        let pokemon_v2_move: [GQLMove]
    }
}

nonisolated struct GQLMove: Decodable, Sendable {
    let id: Int
    let name: String
    let power: Int?
    let accuracy: Int?
    let pp: Int?
    let priority: Int?
    let pokemon_v2_type: TypeRef
    let pokemon_v2_movedamageclass: DamageClassRef
    let pokemon_v2_movemeta: [GQLMoveMeta]

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

private func formatPokemonName(_ raw: String) -> String {
    raw.split(separator: "-").map { $0.capitalized }.joined(separator: "-")
}

private func parseStats(_ gqlStats: [GQLPokemon.GQLPokemonStat]) -> [String: Int] {
    var stats: [String: Int] = [:]
    for s in gqlStats { stats[s.pokemon_v2_stat.name] = s.base_stat }
    return stats
}

private func parseTypes(_ gqlTypes: [GQLPokemon.GQLPokemonType]) -> [String] {
    gqlTypes.map { $0.pokemon_v2_type.name.capitalized }
}

private func parseAbilities(_ gqlAbilities: [GQLPokemon.GQLPokemonAbility]) -> (a1: String?, a2: String?, ha: String?) {
    let normal = gqlAbilities.filter { !$0.is_hidden }
    let hidden = gqlAbilities.filter { $0.is_hidden }
    return (
        normal.first?.pokemon_v2_ability.name,
        normal.count > 1 ? normal[1].pokemon_v2_ability.name : nil,
        hidden.first?.pokemon_v2_ability.name
    )
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
            let moveIDs: [Int]
        }
        var speciesMap: [Int: SpeciesInfo] = [:]

        // Insert default Pokemon
        for p in pokemon {
            let types = parseTypes(p.pokemon_v2_pokemontypes)
            let stats = parseStats(p.pokemon_v2_pokemonstats)
            let abilities = parseAbilities(p.pokemon_v2_pokemonabilities)
            let moveIDs = (p.pokemon_v2_pokemonmoves ?? []).map { $0.move_id }
            let speciesID = p.pokemon_species_id ?? p.id

            speciesMap[speciesID] = SpeciesInfo(stats: stats, types: types, moveIDs: moveIDs)

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
            let types = parseTypes(f.pokemon_v2_pokemontypes)
            let stats = parseStats(f.pokemon_v2_pokemonstats)

            // Skip cosmetic forms (identical stats and types to base species)
            if let base = speciesMap[speciesID] {
                if stats == base.stats && types == base.types { continue }
            }

            let abilities = parseAbilities(f.pokemon_v2_pokemonabilities)
            let formName = f.pokemon_v2_pokemonforms?.first?.form_name
            // Inherit learnset from base species
            let moveIDs = speciesMap[speciesID]?.moveIDs ?? []

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
            let meta = m.pokemon_v2_movemeta.first

            let displayName = m.name
                .split(separator: "-")
                .map { $0.capitalized }
                .joined(separator: " ")

            let entry = MoveData(
                id: m.id,
                name: displayName,
                type: m.pokemon_v2_type.name.capitalized,
                damageClass: m.pokemon_v2_movedamageclass.name,
                power: m.power,
                accuracy: m.accuracy,
                pp: m.pp ?? 0,
                priority: m.priority ?? 0,
                minHits: meta?.min_hits,
                maxHits: meta?.max_hits,
                drain: meta?.drain ?? 0,
                healing: meta?.healing ?? 0,
                critRate: meta?.crit_rate ?? 0
            )
            modelContext.insert(entry)
        }

        try modelContext.save()
        print("Calc data synced: \(pokemon.count) Pokemon, \(formsInserted) forms, \(moves.count) moves")
    }
}
