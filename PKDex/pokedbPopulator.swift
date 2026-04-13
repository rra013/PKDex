import Foundation
import SwiftData

@ModelActor
actor PokeSyncManager {
    // Note: @ModelActor automatically provides 'modelExecutor' and 'modelContext'
    
    static let championsRoster: Set<String> = [
        "Venusaur", "Charizard", "Blastoise", "Beedrill", "Pidgeot", "Arbok", "Pikachu", "Raichu",
        "Alolan Raichu", "Clefable", "Ninetales", "Alolan Ninetales", "Arcanine", "Hisuian Arcanine",
        "Alakazam", "Machamp", "Victreebel", "Slowbro", "Galarian Slowbro", "Gengar", "Kangaskhan",
        "Starmie", "Pinsir", "Tauros", "Gyarados", "Ditto", "Vaporeon", "Jolteon", "Flareon",
        "Aerodactyl", "Snorlax", "Dragonite", "Meganium", "Typhlosion", "Hisuian Typhlosion",
        "Feraligatr", "Ariados", "Ampharos", "Azumarill", "Politoed", "Espeon", "Umbreon",
        "Slowking", "Galarian Slowking", "Forretress", "Steelix", "Scizor", "Heracross",
        "Skarmory", "Houndoom", "Tyranitar", "Pelipper", "Gardevoir", "Sableye", "Aggron",
        "Medicham", "Manectric", "Sharpedo", "Camerupt", "Torkoal", "Altaria", "Milotic",
        "Castform", "Banette", "Chimecho", "Absol", "Glalie", "Torterra", "Infernape",
        "Empoleon", "Luxray", "Roserade", "Rampardos", "Bastiodon", "Lopunny", "Spiritomb",
        "Garchomp", "Lucario", "Hippowdon", "Toxicroak", "Abomasnow", "Weavile", "Rhyperior",
        "Leafeon", "Glaceon", "Gliscor", "Mamoswine", "Gallade", "Froslass", "Rotom", "Serperior",
        "Emboar", "Samurott", "Hisuian Samurott", "Watchog", "Liepard", "Simisage", "Simisear",
        "Simipour", "Excadrill", "Audino", "Conkeldurr", "Whimsicott", "Krookodile", "Cofagrigus",
        "Garbodor", "Zoroark", "Hisuian Zoroark", "Reuniclus", "Vanilluxe", "Emolga", "Chandelure",
        "Beartic", "Stunfisk", "Galarian Stunfisk", "Golurk", "Hydreigon", "Volcarona", "Chesnaught",
        "Delphox", "Greninja", "Diggersby", "Talonflame", "Vivillon", "Florges", "Pangoro",
        "Furfrou", "Meowstic", "Aegislash", "Aromatisse", "Slurpuff", "Clawitzer", "Heliolisk",
        "Tyrantrum", "Aurorus", "Sylveon", "Hawlucha", "Dedenne", "Goodra", "Hisuian Goodra",
        "Klefki", "Trevenant", "Gourgeist", "Avalugg", "Noivern", "Decidueye", "Incineroar",
        "Primarina", "Mimikyu", "Kommo-o", "Corviknight", "Grimmsnarl", "Dragapult", "Zacian",
        "Urshifu", "Meowscarada", "Skeledirge", "Quaquaval", "Garganacl", "Armarouge",
        "Ceruledge", "Tinkaton", "Palafin", "Kingambit", "Glimmora", "Miraidon", "Wyrdeer",
        "Kleavor", "Basculegion", "Sneasler", "Ursaluna"
    ]

    func refreshPokedex() async throws {
        // 1. Fetch data from API first (In-memory, no DB contact yet)
        let gen8Names = await fetchNames(ids: [27, 28, 29])
        let gen9Names = await fetchNames(ids: [31, 32, 33])
        
        guard let url = URL(string: "https://pokeapi.co/api/v2/pokedex/national") else { return }
        let (data, _) = try await URLSession.shared.data(from: url)
        let decoded = try JSONDecoder().decode(PokedexResponseDTO.self, from: data)

        // 2. Clear out the database
        // We do this individually to avoid Schema mapping errors
        try modelContext.delete(model: PKMN.self)
        try modelContext.delete(model: Gen8Pokemon.self)
        try modelContext.delete(model: Gen9Pokemon.self)
        try modelContext.save() // Finalize the wipe

        // 3. Prepare lookup sets and deduplicated insert lists.
        // The regional dex endpoints overlap, and inserting duplicate values into
        // models with unique attributes in one save can crash SwiftData.
        let gen8Set = Set(gen8Names.map { $0.capitalized })
        let gen9Set = Set(gen9Names.map { $0.capitalized })

        // 4. Batch Inserts
        for name in gen8Set.sorted() {
            modelContext.insert(Gen8Pokemon(name: name))
        }
        for name in gen9Set.sorted() {
            modelContext.insert(Gen9Pokemon(name: name))
        }

        for entry in decoded.pokemon_entries {
            let name = entry.pokemon_species.name.capitalized
            let raw = entry.pokemon_species.name
            let id = entry.entry_number
            let padded = String(format: "%03d", id)

            let isG8 = gen8Set.contains(name)
            let isG9 = gen9Set.contains(name)
            let isChamp = Self.championsRoster.contains(name)

            let newPokemon = PKMN(
                name: name,
                nationalPokedexNumber: id,
                genOneLink: id <= 151 ? "https://serebii.net/pokedex/\(padded).shtml" : nil,
                genTwoLink: id <= 251 ? "https://serebii.net/pokedex/\(padded).shtml" : nil,
                genThreeLink: id <= 386 ? "https://serebii.net/pokedex-rs/\(padded).shtml" : nil,
                genFourLink: id <= 493 ? "https://serebii.net/pokedex-dp/\(padded).shtml" : nil,
                genFiveLink: id <= 649 ? "https://serebii.net/pokedex-bw/\(padded).shtml" : nil,
                genSixLink: id <= 721 ? "https://serebii.net/pokedex-xy/\(padded).shtml" : nil,
                genSevenLink: id <= 809 ? "https://serebii.net/pokedex-sm/\(padded).shtml" : nil,
                genEightLink: isG8 ? "https://serebii.net/pokedex-swsh/\(raw)/" : nil,
                genNineLink: isG9 ? "https://serebii.net/pokedex-sv/\(raw)/" : nil,
                champsLink: isChamp ? "https://serebii.net/pokedex-champions/\(raw)/" : nil
            )
            modelContext.insert(newPokemon)
        }

        // 5. Final Save
        try modelContext.save()
        print("✅ Sync Success")
    }

    private func fetchNames(ids: [Int]) async -> [String] {
        var results: [String] = []
        for id in ids {
            if let url = URL(string: "https://pokeapi.co/api/v2/pokedex/\(id)/"),
               let (data, _) = try? await URLSession.shared.data(from: url),
               let decoded = try? JSONDecoder().decode(PokedexResponseDTO.self, from: data) {
                results.append(contentsOf: decoded.pokemon_entries.map { $0.pokemon_species.name })
            }
        }
        return results
    }
}

// MARK: - DTOs
nonisolated struct PokedexResponseDTO: Codable, Sendable {
    let pokemon_entries: [PokemonEntryDTO]
}
nonisolated struct PokemonEntryDTO: Codable, Sendable {
    let entry_number: Int
    let pokemon_species: PokemonSpeciesDTO
}
nonisolated struct PokemonSpeciesDTO: Codable, Sendable {
    let name: String
}
