import SwiftData
import Foundation

@MainActor
class PokedexDataHandler {
    let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func syncAllData() async throws {
        // Gen 8 IDs: 27 (Galar), 28 (Armor), 29 (Tundra)
        try await fetchAndStore(ids: [27, 28, 29], type: Gen8Pokemon.self)
        
        // Gen 9 IDs: 31 (Paldea), 32 (Kitakami), 33 (Blueberry)
        try await fetchAndStore(ids: [31, 32, 33], type: Gen9Pokemon.self)
    }

    private func fetchAndStore<T: PersistentModel>(ids: [Int], type: T.Type) async throws {
        for id in ids {
            let url = URL(string: "https://pokeapi.co/api/v2/pokedex/\(id)/")!
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoded = try JSONDecoder().decode(PokeAPIResponse.self, from: data)

            for entry in decoded.pokemon_entries {
                let name = entry.pokemon_species.name.capitalized
                
                // Save to Gen 8 table
                if T.self == Gen8Pokemon.self {
                    let newPoke = Gen8Pokemon(name: name)
                    modelContext.insert(newPoke)
                }
                // Save to Gen 9 table
                else if T.self == Gen9Pokemon.self {
                    let newPoke = Gen9Pokemon(name: name)
                    modelContext.insert(newPoke)
                }
            }
        }
        try modelContext.save()
    }
}
