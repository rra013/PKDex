import Foundation

// ============================================================================
// MARK: - Encounter Data Models
// ============================================================================

enum FinderGameVersion: String, CaseIterable, Identifiable, Hashable {
    case ruby = "Ruby"
    case sapphire = "Sapphire"
    case emerald = "Emerald"
    case fireRed = "FireRed"
    case leafGreen = "LeafGreen"
    case diamond = "Diamond"
    case pearl = "Pearl"
    case platinum = "Platinum"
    case heartGold = "HeartGold"
    case soulSilver = "SoulSilver"

    var id: String { rawValue }

    var generation: FinderGeneration {
        switch self {
        case .ruby, .sapphire, .emerald, .fireRed, .leafGreen: return .gen3
        case .diamond, .pearl, .platinum, .heartGold, .soulSilver: return .gen4
        }
    }

    static func games(for gen: FinderGeneration) -> [FinderGameVersion] {
        allCases.filter { $0.generation == gen }
    }
}

enum StaticEncounterCategory: String, CaseIterable, Identifiable, Hashable {
    case starters = "Starters"
    case fossils = "Fossils"
    case gifts = "Gifts"
    case gameCorner = "Game Corner"
    case stationary = "Stationary"
    case legends = "Legends"
    case roamers = "Roamers"

    var id: String { rawValue }
}

struct StaticEncounter: Identifiable, Hashable {
    let id = UUID()
    let gameVersions: [FinderGameVersion]
    let species: UInt16
    let speciesName: String
    let level: UInt8
    let category: StaticEncounterCategory
    let method: FinderMethod
    let shinyLocked: Bool

    init(games: [FinderGameVersion], species: UInt16, name: String,
         level: UInt8, category: StaticEncounterCategory,
         method: FinderMethod, shinyLocked: Bool = false) {
        self.gameVersions = games
        self.species = species
        self.speciesName = name
        self.level = level
        self.category = category
        self.method = method
        self.shinyLocked = shinyLocked
    }
}

enum EncounterType: String, CaseIterable, Identifiable, Hashable {
    case grass = "Grass"
    case surf = "Surf"
    case oldRod = "Old Rod"
    case goodRod = "Good Rod"
    case superRod = "Super Rod"
    case rockSmash = "Rock Smash"

    var id: String { rawValue }
}

struct WildSlot: Identifiable, Hashable {
    let id = UUID()
    let species: UInt16
    let speciesName: String
    let minLevel: UInt8
    let maxLevel: UInt8
    let slotRate: String
}

struct WildEncounterRoute: Identifiable, Hashable {
    let id = UUID()
    let gameVersions: [FinderGameVersion]
    let locationName: String
    let encounterType: EncounterType
    let slots: [WildSlot]
}

// ============================================================================
// MARK: - Static Encounter Data
// ============================================================================

enum StaticEncounterData {

    // MARK: Gen 3 Starters

    static let gen3Starters: [StaticEncounter] = [
        // Ruby/Sapphire/Emerald starters
        StaticEncounter(games: [.ruby, .sapphire, .emerald], species: 252, name: "Treecko",
                        level: 5, category: .starters, method: .method1),
        StaticEncounter(games: [.ruby, .sapphire, .emerald], species: 255, name: "Torchic",
                        level: 5, category: .starters, method: .method1),
        StaticEncounter(games: [.ruby, .sapphire, .emerald], species: 258, name: "Mudkip",
                        level: 5, category: .starters, method: .method1),
        // FRLG starters
        StaticEncounter(games: [.fireRed, .leafGreen], species: 1, name: "Bulbasaur",
                        level: 5, category: .starters, method: .method1),
        StaticEncounter(games: [.fireRed, .leafGreen], species: 4, name: "Charmander",
                        level: 5, category: .starters, method: .method1),
        StaticEncounter(games: [.fireRed, .leafGreen], species: 7, name: "Squirtle",
                        level: 5, category: .starters, method: .method1),
    ]

    // MARK: Gen 3 Fossils

    static let gen3Fossils: [StaticEncounter] = [
        // RSE fossils
        StaticEncounter(games: [.ruby, .sapphire, .emerald], species: 345, name: "Lileep",
                        level: 20, category: .fossils, method: .method1),
        StaticEncounter(games: [.ruby, .sapphire, .emerald], species: 347, name: "Anorith",
                        level: 20, category: .fossils, method: .method1),
        // FRLG fossils
        StaticEncounter(games: [.fireRed, .leafGreen], species: 138, name: "Omanyte",
                        level: 5, category: .fossils, method: .method1),
        StaticEncounter(games: [.fireRed, .leafGreen], species: 140, name: "Kabuto",
                        level: 5, category: .fossils, method: .method1),
        StaticEncounter(games: [.fireRed, .leafGreen], species: 142, name: "Aerodactyl",
                        level: 5, category: .fossils, method: .method1),
    ]

    // MARK: Gen 3 Gifts

    static let gen3Gifts: [StaticEncounter] = [
        // Castform (Weather Institute)
        StaticEncounter(games: [.ruby, .sapphire, .emerald], species: 351, name: "Castform",
                        level: 25, category: .gifts, method: .method1),
        // Beldum (Steven's house)
        StaticEncounter(games: [.ruby, .sapphire, .emerald], species: 374, name: "Beldum",
                        level: 5, category: .gifts, method: .method1),
        // Wynaut egg (Lavaridge)
        StaticEncounter(games: [.ruby, .sapphire, .emerald], species: 360, name: "Wynaut",
                        level: 5, category: .gifts, method: .method1),
        // FRLG gifts
        StaticEncounter(games: [.fireRed, .leafGreen], species: 106, name: "Hitmonlee",
                        level: 25, category: .gifts, method: .method1),
        StaticEncounter(games: [.fireRed, .leafGreen], species: 107, name: "Hitmonchan",
                        level: 25, category: .gifts, method: .method1),
        StaticEncounter(games: [.fireRed, .leafGreen], species: 131, name: "Lapras",
                        level: 25, category: .gifts, method: .method1),
        StaticEncounter(games: [.fireRed, .leafGreen], species: 133, name: "Eevee",
                        level: 25, category: .gifts, method: .method1),
        StaticEncounter(games: [.fireRed, .leafGreen], species: 137, name: "Porygon",
                        level: 9, category: .gifts, method: .method1),
        // Togepi egg
        StaticEncounter(games: [.fireRed, .leafGreen], species: 175, name: "Togepi",
                        level: 5, category: .gifts, method: .method1),
        // Johto starters from Emerald
        StaticEncounter(games: [.emerald], species: 152, name: "Chikorita",
                        level: 5, category: .gifts, method: .method1),
        StaticEncounter(games: [.emerald], species: 155, name: "Cyndaquil",
                        level: 5, category: .gifts, method: .method1),
        StaticEncounter(games: [.emerald], species: 158, name: "Totodile",
                        level: 5, category: .gifts, method: .method1),
    ]

    // MARK: Gen 3 Legends

    static let gen3Legends: [StaticEncounter] = [
        // Weather duo
        StaticEncounter(games: [.ruby], species: 383, name: "Groudon",
                        level: 45, category: .legends, method: .method1),
        StaticEncounter(games: [.sapphire], species: 382, name: "Kyogre",
                        level: 45, category: .legends, method: .method1),
        StaticEncounter(games: [.emerald], species: 383, name: "Groudon",
                        level: 70, category: .legends, method: .method1),
        StaticEncounter(games: [.emerald], species: 382, name: "Kyogre",
                        level: 70, category: .legends, method: .method1),
        // Rayquaza
        StaticEncounter(games: [.ruby, .sapphire], species: 384, name: "Rayquaza",
                        level: 70, category: .legends, method: .method1),
        StaticEncounter(games: [.emerald], species: 384, name: "Rayquaza",
                        level: 70, category: .legends, method: .method1),
        // Regis
        StaticEncounter(games: [.ruby, .sapphire, .emerald], species: 377, name: "Regirock",
                        level: 40, category: .legends, method: .method1),
        StaticEncounter(games: [.ruby, .sapphire, .emerald], species: 378, name: "Regice",
                        level: 40, category: .legends, method: .method1),
        StaticEncounter(games: [.ruby, .sapphire, .emerald], species: 379, name: "Registeel",
                        level: 40, category: .legends, method: .method1),
        // Latis
        StaticEncounter(games: [.ruby], species: 381, name: "Latios",
                        level: 40, category: .legends, method: .method1),
        StaticEncounter(games: [.sapphire], species: 380, name: "Latias",
                        level: 40, category: .legends, method: .method1),
        StaticEncounter(games: [.emerald], species: 380, name: "Latias",
                        level: 40, category: .legends, method: .method1),
        StaticEncounter(games: [.emerald], species: 381, name: "Latios",
                        level: 40, category: .legends, method: .method1),
        // FRLG legends
        StaticEncounter(games: [.fireRed, .leafGreen], species: 150, name: "Mewtwo",
                        level: 70, category: .legends, method: .method1),
        StaticEncounter(games: [.fireRed, .leafGreen], species: 144, name: "Articuno",
                        level: 50, category: .legends, method: .method1),
        StaticEncounter(games: [.fireRed, .leafGreen], species: 145, name: "Zapdos",
                        level: 50, category: .legends, method: .method1),
        StaticEncounter(games: [.fireRed, .leafGreen], species: 146, name: "Moltres",
                        level: 50, category: .legends, method: .method1),
        // Event legends
        StaticEncounter(games: [.emerald], species: 151, name: "Mew",
                        level: 30, category: .legends, method: .method1),
        StaticEncounter(games: [.emerald], species: 386, name: "Deoxys",
                        level: 30, category: .legends, method: .method1),
        StaticEncounter(games: [.emerald], species: 249, name: "Lugia",
                        level: 70, category: .legends, method: .method1),
        StaticEncounter(games: [.emerald], species: 250, name: "Ho-Oh",
                        level: 70, category: .legends, method: .method1),
        // FRLG event
        StaticEncounter(games: [.fireRed, .leafGreen], species: 151, name: "Mew",
                        level: 30, category: .legends, method: .method1),
        StaticEncounter(games: [.fireRed, .leafGreen], species: 386, name: "Deoxys",
                        level: 30, category: .legends, method: .method1),
        StaticEncounter(games: [.fireRed, .leafGreen], species: 249, name: "Lugia",
                        level: 70, category: .legends, method: .method1),
        StaticEncounter(games: [.fireRed, .leafGreen], species: 250, name: "Ho-Oh",
                        level: 70, category: .legends, method: .method1),
    ]

    // MARK: Gen 3 Stationary

    static let gen3Stationary: [StaticEncounter] = [
        // Snorlax (FRLG)
        StaticEncounter(games: [.fireRed, .leafGreen], species: 143, name: "Snorlax",
                        level: 30, category: .stationary, method: .method1),
        // Electrode (FRLG Power Plant)
        StaticEncounter(games: [.fireRed, .leafGreen], species: 101, name: "Electrode",
                        level: 34, category: .stationary, method: .method1),
        // Voltorb (RSE New Mauville)
        StaticEncounter(games: [.ruby, .sapphire, .emerald], species: 100, name: "Voltorb",
                        level: 25, category: .stationary, method: .method1),
        StaticEncounter(games: [.ruby, .sapphire, .emerald], species: 101, name: "Electrode",
                        level: 25, category: .stationary, method: .method1),
        // Kecleon
        StaticEncounter(games: [.ruby, .sapphire, .emerald], species: 352, name: "Kecleon",
                        level: 30, category: .stationary, method: .method1),
        // Sudowoodo (Emerald)
        StaticEncounter(games: [.emerald], species: 185, name: "Sudowoodo",
                        level: 40, category: .stationary, method: .method1),
    ]

    // MARK: Gen 3 Roamers

    static let gen3Roamers: [StaticEncounter] = [
        StaticEncounter(games: [.ruby], species: 380, name: "Latias",
                        level: 40, category: .roamers, method: .method1),
        StaticEncounter(games: [.sapphire], species: 381, name: "Latios",
                        level: 40, category: .roamers, method: .method1),
        StaticEncounter(games: [.fireRed], species: 243, name: "Raikou",
                        level: 50, category: .roamers, method: .method1),
        StaticEncounter(games: [.fireRed], species: 244, name: "Entei",
                        level: 50, category: .roamers, method: .method1),
        StaticEncounter(games: [.fireRed], species: 245, name: "Suicune",
                        level: 50, category: .roamers, method: .method1),
        StaticEncounter(games: [.leafGreen], species: 243, name: "Raikou",
                        level: 50, category: .roamers, method: .method1),
        StaticEncounter(games: [.leafGreen], species: 244, name: "Entei",
                        level: 50, category: .roamers, method: .method1),
        StaticEncounter(games: [.leafGreen], species: 245, name: "Suicune",
                        level: 50, category: .roamers, method: .method1),
    ]

    // MARK: Gen 4 Starters

    static let gen4Starters: [StaticEncounter] = [
        // DPPt starters
        StaticEncounter(games: [.diamond, .pearl, .platinum], species: 387, name: "Turtwig",
                        level: 5, category: .starters, method: .method1),
        StaticEncounter(games: [.diamond, .pearl, .platinum], species: 390, name: "Chimchar",
                        level: 5, category: .starters, method: .method1),
        StaticEncounter(games: [.diamond, .pearl, .platinum], species: 393, name: "Piplup",
                        level: 5, category: .starters, method: .method1),
        // HGSS starters
        StaticEncounter(games: [.heartGold, .soulSilver], species: 152, name: "Chikorita",
                        level: 5, category: .starters, method: .method1),
        StaticEncounter(games: [.heartGold, .soulSilver], species: 155, name: "Cyndaquil",
                        level: 5, category: .starters, method: .method1),
        StaticEncounter(games: [.heartGold, .soulSilver], species: 158, name: "Totodile",
                        level: 5, category: .starters, method: .method1),
        // Kanto starters from Steven in HGSS
        StaticEncounter(games: [.heartGold, .soulSilver], species: 1, name: "Bulbasaur",
                        level: 5, category: .starters, method: .method1),
        StaticEncounter(games: [.heartGold, .soulSilver], species: 4, name: "Charmander",
                        level: 5, category: .starters, method: .method1),
        StaticEncounter(games: [.heartGold, .soulSilver], species: 7, name: "Squirtle",
                        level: 5, category: .starters, method: .method1),
        // Hoenn starters from Steven in HGSS
        StaticEncounter(games: [.heartGold, .soulSilver], species: 252, name: "Treecko",
                        level: 5, category: .starters, method: .method1),
        StaticEncounter(games: [.heartGold, .soulSilver], species: 255, name: "Torchic",
                        level: 5, category: .starters, method: .method1),
        StaticEncounter(games: [.heartGold, .soulSilver], species: 258, name: "Mudkip",
                        level: 5, category: .starters, method: .method1),
    ]

    // MARK: Gen 4 Fossils

    static let gen4Fossils: [StaticEncounter] = [
        StaticEncounter(games: [.diamond, .pearl, .platinum], species: 138, name: "Omanyte",
                        level: 20, category: .fossils, method: .method1),
        StaticEncounter(games: [.diamond, .pearl, .platinum], species: 140, name: "Kabuto",
                        level: 20, category: .fossils, method: .method1),
        StaticEncounter(games: [.diamond, .pearl, .platinum], species: 142, name: "Aerodactyl",
                        level: 20, category: .fossils, method: .method1),
        StaticEncounter(games: [.diamond, .pearl, .platinum], species: 345, name: "Lileep",
                        level: 20, category: .fossils, method: .method1),
        StaticEncounter(games: [.diamond, .pearl, .platinum], species: 347, name: "Anorith",
                        level: 20, category: .fossils, method: .method1),
        StaticEncounter(games: [.diamond, .pearl, .platinum], species: 408, name: "Cranidos",
                        level: 20, category: .fossils, method: .method1),
        StaticEncounter(games: [.diamond, .pearl, .platinum], species: 410, name: "Shieldon",
                        level: 20, category: .fossils, method: .method1),
        // HGSS fossils
        StaticEncounter(games: [.heartGold, .soulSilver], species: 138, name: "Omanyte",
                        level: 20, category: .fossils, method: .method1),
        StaticEncounter(games: [.heartGold, .soulSilver], species: 140, name: "Kabuto",
                        level: 20, category: .fossils, method: .method1),
        StaticEncounter(games: [.heartGold, .soulSilver], species: 142, name: "Aerodactyl",
                        level: 20, category: .fossils, method: .method1),
        StaticEncounter(games: [.heartGold, .soulSilver], species: 345, name: "Lileep",
                        level: 20, category: .fossils, method: .method1),
        StaticEncounter(games: [.heartGold, .soulSilver], species: 347, name: "Anorith",
                        level: 20, category: .fossils, method: .method1),
    ]

    // MARK: Gen 4 Gifts

    static let gen4Gifts: [StaticEncounter] = [
        // Eevee (Bebe)
        StaticEncounter(games: [.diamond, .pearl, .platinum], species: 133, name: "Eevee",
                        level: 5, category: .gifts, method: .method1),
        // Porygon (Veilstone)
        StaticEncounter(games: [.platinum], species: 137, name: "Porygon",
                        level: 25, category: .gifts, method: .method1),
        // Togepi egg (Cynthia)
        StaticEncounter(games: [.diamond, .pearl, .platinum], species: 175, name: "Togepi",
                        level: 1, category: .gifts, method: .method1),
        // Riolu egg (Riley)
        StaticEncounter(games: [.diamond, .pearl, .platinum], species: 447, name: "Riolu",
                        level: 1, category: .gifts, method: .method1),
        // HGSS gifts
        StaticEncounter(games: [.heartGold, .soulSilver], species: 133, name: "Eevee",
                        level: 5, category: .gifts, method: .method1),
        StaticEncounter(games: [.heartGold, .soulSilver], species: 175, name: "Togepi",
                        level: 1, category: .gifts, method: .method1),
        StaticEncounter(games: [.heartGold, .soulSilver], species: 147, name: "Dratini",
                        level: 15, category: .gifts, method: .method1),
        StaticEncounter(games: [.heartGold, .soulSilver], species: 236, name: "Tyrogue",
                        level: 10, category: .gifts, method: .method1),
        StaticEncounter(games: [.heartGold, .soulSilver], species: 25, name: "Spiky-eared Pichu",
                        level: 30, category: .gifts, method: .method1, shinyLocked: true),
    ]

    // MARK: Gen 4 Legends

    static let gen4Legends: [StaticEncounter] = [
        // Creation trio
        StaticEncounter(games: [.diamond], species: 483, name: "Dialga",
                        level: 47, category: .legends, method: .method1),
        StaticEncounter(games: [.pearl], species: 484, name: "Palkia",
                        level: 47, category: .legends, method: .method1),
        StaticEncounter(games: [.platinum], species: 483, name: "Dialga",
                        level: 70, category: .legends, method: .method1),
        StaticEncounter(games: [.platinum], species: 484, name: "Palkia",
                        level: 70, category: .legends, method: .method1),
        StaticEncounter(games: [.platinum], species: 487, name: "Giratina",
                        level: 47, category: .legends, method: .method1),
        StaticEncounter(games: [.diamond, .pearl], species: 487, name: "Giratina",
                        level: 70, category: .legends, method: .method1),
        // Lake trio
        StaticEncounter(games: [.diamond, .pearl, .platinum], species: 480, name: "Uxie",
                        level: 50, category: .legends, method: .method1),
        StaticEncounter(games: [.diamond, .pearl, .platinum], species: 481, name: "Mesprit",
                        level: 50, category: .legends, method: .method1),
        StaticEncounter(games: [.diamond, .pearl, .platinum], species: 482, name: "Azelf",
                        level: 50, category: .legends, method: .method1),
        // Other DPPt legends
        StaticEncounter(games: [.diamond, .pearl, .platinum], species: 485, name: "Heatran",
                        level: 70, category: .legends, method: .method1),
        StaticEncounter(games: [.diamond, .pearl, .platinum], species: 486, name: "Regigigas",
                        level: 70, category: .legends, method: .method1),
        StaticEncounter(games: [.platinum], species: 377, name: "Regirock",
                        level: 30, category: .legends, method: .method1),
        StaticEncounter(games: [.platinum], species: 378, name: "Regice",
                        level: 30, category: .legends, method: .method1),
        StaticEncounter(games: [.platinum], species: 379, name: "Registeel",
                        level: 30, category: .legends, method: .method1),
        // Cresselia
        StaticEncounter(games: [.diamond, .pearl, .platinum], species: 488, name: "Cresselia",
                        level: 50, category: .legends, method: .method1),
        // Event legends
        StaticEncounter(games: [.diamond, .pearl, .platinum], species: 491, name: "Darkrai",
                        level: 40, category: .legends, method: .method1),
        StaticEncounter(games: [.diamond, .pearl, .platinum], species: 492, name: "Shaymin",
                        level: 30, category: .legends, method: .method1),
        StaticEncounter(games: [.diamond, .pearl, .platinum], species: 493, name: "Arceus",
                        level: 80, category: .legends, method: .method1),
        // HGSS legends
        StaticEncounter(games: [.heartGold], species: 250, name: "Ho-Oh",
                        level: 45, category: .legends, method: .method1),
        StaticEncounter(games: [.soulSilver], species: 249, name: "Lugia",
                        level: 45, category: .legends, method: .method1),
        StaticEncounter(games: [.heartGold], species: 249, name: "Lugia",
                        level: 70, category: .legends, method: .method1),
        StaticEncounter(games: [.soulSilver], species: 250, name: "Ho-Oh",
                        level: 70, category: .legends, method: .method1),
        // HGSS Kanto legends
        StaticEncounter(games: [.heartGold, .soulSilver], species: 144, name: "Articuno",
                        level: 50, category: .legends, method: .method1),
        StaticEncounter(games: [.heartGold, .soulSilver], species: 145, name: "Zapdos",
                        level: 50, category: .legends, method: .method1),
        StaticEncounter(games: [.heartGold, .soulSilver], species: 146, name: "Moltres",
                        level: 50, category: .legends, method: .method1),
        StaticEncounter(games: [.heartGold, .soulSilver], species: 150, name: "Mewtwo",
                        level: 70, category: .legends, method: .method1),
        // Beasts
        StaticEncounter(games: [.heartGold, .soulSilver], species: 245, name: "Suicune",
                        level: 40, category: .legends, method: .method1),
        // Weather trio in HGSS
        StaticEncounter(games: [.heartGold], species: 383, name: "Groudon",
                        level: 50, category: .legends, method: .method1),
        StaticEncounter(games: [.soulSilver], species: 382, name: "Kyogre",
                        level: 50, category: .legends, method: .method1),
        StaticEncounter(games: [.heartGold, .soulSilver], species: 384, name: "Rayquaza",
                        level: 50, category: .legends, method: .method1),
        // HGSS Dialga/Palkia/Giratina
        StaticEncounter(games: [.heartGold, .soulSilver], species: 483, name: "Dialga",
                        level: 1, category: .legends, method: .method1),
        StaticEncounter(games: [.heartGold, .soulSilver], species: 484, name: "Palkia",
                        level: 1, category: .legends, method: .method1),
        StaticEncounter(games: [.heartGold, .soulSilver], species: 487, name: "Giratina",
                        level: 1, category: .legends, method: .method1),
    ]

    // MARK: Gen 4 Stationary

    static let gen4Stationary: [StaticEncounter] = [
        // Snorlax (DPPt)
        StaticEncounter(games: [.diamond, .pearl], species: 143, name: "Snorlax",
                        level: 50, category: .stationary, method: .method1),
        // Rotom
        StaticEncounter(games: [.diamond, .pearl, .platinum], species: 479, name: "Rotom",
                        level: 20, category: .stationary, method: .method1),
        // Spiritomb
        StaticEncounter(games: [.diamond, .pearl, .platinum], species: 442, name: "Spiritomb",
                        level: 25, category: .stationary, method: .method1),
        // Drifloon (Valley Windworks)
        StaticEncounter(games: [.diamond, .pearl, .platinum], species: 425, name: "Drifloon",
                        level: 22, category: .stationary, method: .methodJ),
        // HGSS stationary
        StaticEncounter(games: [.heartGold, .soulSilver], species: 143, name: "Snorlax",
                        level: 50, category: .stationary, method: .method1),
        StaticEncounter(games: [.heartGold, .soulSilver], species: 185, name: "Sudowoodo",
                        level: 20, category: .stationary, method: .methodK),
        StaticEncounter(games: [.heartGold, .soulSilver], species: 101, name: "Electrode",
                        level: 23, category: .stationary, method: .method1),
        // Red Gyarados
        StaticEncounter(games: [.heartGold, .soulSilver], species: 130, name: "Gyarados",
                        level: 30, category: .stationary, method: .method1),
    ]

    // MARK: Gen 4 Roamers

    static let gen4Roamers: [StaticEncounter] = [
        StaticEncounter(games: [.diamond, .pearl], species: 481, name: "Mesprit",
                        level: 50, category: .roamers, method: .method1),
        StaticEncounter(games: [.diamond, .pearl], species: 488, name: "Cresselia",
                        level: 50, category: .roamers, method: .method1),
        StaticEncounter(games: [.platinum], species: 481, name: "Mesprit",
                        level: 50, category: .roamers, method: .method1),
        StaticEncounter(games: [.platinum], species: 488, name: "Cresselia",
                        level: 50, category: .roamers, method: .method1),
        StaticEncounter(games: [.platinum], species: 144, name: "Articuno",
                        level: 60, category: .roamers, method: .method1),
        StaticEncounter(games: [.platinum], species: 145, name: "Zapdos",
                        level: 60, category: .roamers, method: .method1),
        StaticEncounter(games: [.platinum], species: 146, name: "Moltres",
                        level: 60, category: .roamers, method: .method1),
        StaticEncounter(games: [.heartGold, .soulSilver], species: 243, name: "Raikou",
                        level: 40, category: .roamers, method: .methodK),
        StaticEncounter(games: [.heartGold, .soulSilver], species: 244, name: "Entei",
                        level: 40, category: .roamers, method: .methodK),
        StaticEncounter(games: [.heartGold, .soulSilver], species: 380, name: "Latias",
                        level: 35, category: .roamers, method: .methodK),
        StaticEncounter(games: [.heartGold, .soulSilver], species: 381, name: "Latios",
                        level: 35, category: .roamers, method: .methodK),
    ]

    // MARK: Game Corner

    static let gen3GameCorner: [StaticEncounter] = [
        // FRLG Game Corner prizes
        StaticEncounter(games: [.fireRed], species: 63, name: "Abra",
                        level: 9, category: .gameCorner, method: .method1),
        StaticEncounter(games: [.fireRed], species: 35, name: "Clefairy",
                        level: 8, category: .gameCorner, method: .method1),
        StaticEncounter(games: [.fireRed], species: 123, name: "Scyther",
                        level: 25, category: .gameCorner, method: .method1),
        StaticEncounter(games: [.fireRed], species: 147, name: "Dratini",
                        level: 18, category: .gameCorner, method: .method1),
        StaticEncounter(games: [.fireRed], species: 137, name: "Porygon",
                        level: 26, category: .gameCorner, method: .method1),
        StaticEncounter(games: [.leafGreen], species: 63, name: "Abra",
                        level: 9, category: .gameCorner, method: .method1),
        StaticEncounter(games: [.leafGreen], species: 35, name: "Clefairy",
                        level: 8, category: .gameCorner, method: .method1),
        StaticEncounter(games: [.leafGreen], species: 127, name: "Pinsir",
                        level: 25, category: .gameCorner, method: .method1),
        StaticEncounter(games: [.leafGreen], species: 147, name: "Dratini",
                        level: 18, category: .gameCorner, method: .method1),
        StaticEncounter(games: [.leafGreen], species: 137, name: "Porygon",
                        level: 26, category: .gameCorner, method: .method1),
    ]

    static let gen4GameCorner: [StaticEncounter] = [
        // DPPt Game Corner
        StaticEncounter(games: [.diamond, .pearl], species: 63, name: "Abra",
                        level: 9, category: .gameCorner, method: .method1),
        StaticEncounter(games: [.diamond, .pearl], species: 35, name: "Clefairy",
                        level: 9, category: .gameCorner, method: .method1),
        StaticEncounter(games: [.diamond, .pearl], species: 137, name: "Porygon",
                        level: 15, category: .gameCorner, method: .method1),
        // HGSS Game Corner (Voltorb Flip prizes)
        StaticEncounter(games: [.heartGold, .soulSilver], species: 63, name: "Abra",
                        level: 9, category: .gameCorner, method: .method1),
        StaticEncounter(games: [.heartGold, .soulSilver], species: 147, name: "Dratini",
                        level: 15, category: .gameCorner, method: .method1),
    ]

    // MARK: Lookup

    static func encounters(for game: FinderGameVersion, category: StaticEncounterCategory) -> [StaticEncounter] {
        let all: [StaticEncounter]
        switch game.generation {
        case .gen3:
            switch category {
            case .starters: all = gen3Starters
            case .fossils: all = gen3Fossils
            case .gifts: all = gen3Gifts
            case .legends: all = gen3Legends
            case .stationary: all = gen3Stationary
            case .roamers: all = gen3Roamers
            case .gameCorner: all = gen3GameCorner
            }
        case .gen4:
            switch category {
            case .starters: all = gen4Starters
            case .fossils: all = gen4Fossils
            case .gifts: all = gen4Gifts
            case .legends: all = gen4Legends
            case .stationary: all = gen4Stationary
            case .roamers: all = gen4Roamers
            case .gameCorner: all = gen4GameCorner
            }
        }
        return all.filter { $0.gameVersions.contains(game) }
    }

    static func categories(for game: FinderGameVersion) -> [StaticEncounterCategory] {
        StaticEncounterCategory.allCases.filter { cat in
            !encounters(for: game, category: cat).isEmpty
        }
    }
}
