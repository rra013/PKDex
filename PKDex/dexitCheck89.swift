import Foundation
import SwiftData

@Model
final class Gen8Pokemon {
    @Attribute(.unique) var name: String
    
    init(name: String) {
        self.name = name.capitalized
    }
}

@Model
final class Gen9Pokemon {
    @Attribute(.unique) var name: String
    
    init(name: String) {
        self.name = name.capitalized
    }
}

struct PokeAPIResponse: Codable {
    let pokemon_entries: [Entry]
    
    struct Entry: Codable {
        let pokemon_species: Species
    }
    
    struct Species: Codable {
        let name: String
    }
}
