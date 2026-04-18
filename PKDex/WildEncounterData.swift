import Foundation

// ============================================================================
// MARK: - Wild Encounter Data
// ============================================================================

// Slot rate labels for Gen 3/4 grass encounters (12 slots)
private let grassRates = ["20%", "20%", "10%", "10%", "10%", "10%", "5%", "5%", "4%", "4%", "1%", "1%"]
// Slot rate labels for surf encounters (5 slots)
private let surfRates = ["60%", "30%", "5%", "4%", "1%"]
// Slot rate labels for Old Rod (2 slots)
private let oldRodRates = ["70%", "30%"]
// Slot rate labels for Good Rod (3 slots)
private let goodRodRates = ["60%", "20%", "20%"]
// Slot rate labels for Super Rod (5 slots)
private let superRodRates = ["40%", "40%", "15%", "4%", "1%"]
// Rock Smash (5 slots)
private let rockSmashRates = ["60%", "30%", "5%", "4%", "1%"]

private func gs(_ slots: [(UInt16, String, UInt8, UInt8)]) -> [WildSlot] {
    slots.enumerated().map { i, s in
        WildSlot(species: s.0, speciesName: s.1, minLevel: s.2, maxLevel: s.3,
                 slotRate: i < grassRates.count ? grassRates[i] : "?")
    }
}

private func ss(_ slots: [(UInt16, String, UInt8, UInt8)]) -> [WildSlot] {
    slots.enumerated().map { i, s in
        WildSlot(species: s.0, speciesName: s.1, minLevel: s.2, maxLevel: s.3,
                 slotRate: i < surfRates.count ? surfRates[i] : "?")
    }
}

private func ors(_ slots: [(UInt16, String, UInt8, UInt8)]) -> [WildSlot] {
    slots.enumerated().map { i, s in
        WildSlot(species: s.0, speciesName: s.1, minLevel: s.2, maxLevel: s.3,
                 slotRate: i < oldRodRates.count ? oldRodRates[i] : "?")
    }
}

private func grs(_ slots: [(UInt16, String, UInt8, UInt8)]) -> [WildSlot] {
    slots.enumerated().map { i, s in
        WildSlot(species: s.0, speciesName: s.1, minLevel: s.2, maxLevel: s.3,
                 slotRate: i < goodRodRates.count ? goodRodRates[i] : "?")
    }
}

private func srs(_ slots: [(UInt16, String, UInt8, UInt8)]) -> [WildSlot] {
    slots.enumerated().map { i, s in
        WildSlot(species: s.0, speciesName: s.1, minLevel: s.2, maxLevel: s.3,
                 slotRate: i < superRodRates.count ? superRodRates[i] : "?")
    }
}

private func rs(_ slots: [(UInt16, String, UInt8, UInt8)]) -> [WildSlot] {
    slots.enumerated().map { i, s in
        WildSlot(species: s.0, speciesName: s.1, minLevel: s.2, maxLevel: s.3,
                 slotRate: i < rockSmashRates.count ? rockSmashRates[i] : "?")
    }
}

// ============================================================================
// MARK: - Ruby/Sapphire Wild Encounters
// ============================================================================

enum WildEncounterData {

    // MARK: Ruby/Sapphire

    static let rubySapphire: [WildEncounterRoute] = [
        // Route 101
        WildEncounterRoute(gameVersions: [.ruby, .sapphire], locationName: "Route 101", encounterType: .grass, slots: gs([
            (263, "Zigzagoon", 2, 2), (265, "Wurmple", 2, 2),
            (263, "Zigzagoon", 3, 3), (265, "Wurmple", 3, 3),
            (263, "Zigzagoon", 2, 2), (265, "Wurmple", 2, 2),
            (263, "Zigzagoon", 3, 3), (265, "Wurmple", 3, 3),
            (261, "Poochyena", 2, 2), (261, "Poochyena", 2, 2),
            (261, "Poochyena", 3, 3), (261, "Poochyena", 3, 3),
        ])),
        // Route 102
        WildEncounterRoute(gameVersions: [.ruby, .sapphire], locationName: "Route 102", encounterType: .grass, slots: gs([
            (263, "Zigzagoon", 3, 3), (265, "Wurmple", 3, 3),
            (280, "Ralts", 4, 4), (261, "Poochyena", 3, 3),
            (263, "Zigzagoon", 4, 4), (265, "Wurmple", 4, 4),
            (276, "Taillow", 3, 3), (276, "Taillow", 4, 4),
            (270, "Lotad", 3, 3), (270, "Lotad", 4, 4),
            (283, "Surskit", 3, 3), (283, "Surskit", 4, 4),
        ])),
        // Route 103
        WildEncounterRoute(gameVersions: [.ruby, .sapphire], locationName: "Route 103", encounterType: .grass, slots: gs([
            (263, "Zigzagoon", 2, 2), (261, "Poochyena", 2, 2),
            (263, "Zigzagoon", 3, 3), (261, "Poochyena", 3, 3),
            (263, "Zigzagoon", 3, 3), (261, "Poochyena", 3, 3),
            (278, "Wingull", 2, 2), (278, "Wingull", 3, 3),
            (263, "Zigzagoon", 2, 2), (261, "Poochyena", 2, 2),
            (263, "Zigzagoon", 3, 3), (261, "Poochyena", 3, 3),
        ])),
        // Route 104
        WildEncounterRoute(gameVersions: [.ruby, .sapphire], locationName: "Route 104", encounterType: .grass, slots: gs([
            (263, "Zigzagoon", 4, 4), (265, "Wurmple", 4, 4),
            (276, "Taillow", 5, 5), (263, "Zigzagoon", 5, 5),
            (265, "Wurmple", 5, 5), (276, "Taillow", 4, 4),
            (278, "Wingull", 4, 4), (278, "Wingull", 5, 5),
            (183, "Marill", 4, 4), (183, "Marill", 5, 5),
            (183, "Marill", 4, 4), (183, "Marill", 5, 5),
        ])),
        // Petalburg Woods
        WildEncounterRoute(gameVersions: [.ruby, .sapphire], locationName: "Petalburg Woods", encounterType: .grass, slots: gs([
            (263, "Zigzagoon", 5, 5), (265, "Wurmple", 5, 5),
            (285, "Shroomish", 5, 5), (266, "Silcoon", 5, 5),
            (276, "Taillow", 5, 5), (263, "Zigzagoon", 6, 6),
            (265, "Wurmple", 6, 6), (285, "Shroomish", 6, 6),
            (290, "Nincada", 5, 5), (290, "Nincada", 6, 6),
            (286, "Breloom", 5, 5), (286, "Breloom", 6, 6),
        ])),
        // Route 110
        WildEncounterRoute(gameVersions: [.ruby, .sapphire], locationName: "Route 110", encounterType: .grass, slots: gs([
            (261, "Poochyena", 12, 12), (309, "Electrike", 12, 12),
            (312, "Minun", 12, 12), (263, "Zigzagoon", 12, 12),
            (278, "Wingull", 12, 12), (100, "Voltorb", 12, 12),
            (311, "Plusle", 12, 12), (116, "Horsea", 12, 12),
            (81, "Magnemite", 12, 12), (81, "Magnemite", 13, 13),
            (309, "Electrike", 13, 13), (100, "Voltorb", 13, 13),
        ])),
        // Route 116
        WildEncounterRoute(gameVersions: [.ruby, .sapphire], locationName: "Route 116", encounterType: .grass, slots: gs([
            (263, "Zigzagoon", 6, 6), (290, "Nincada", 6, 6),
            (276, "Taillow", 6, 6), (300, "Skitty", 6, 6),
            (265, "Wurmple", 6, 6), (293, "Whismur", 6, 6),
            (063, "Abra", 7, 7), (063, "Abra", 8, 8),
            (290, "Nincada", 7, 7), (276, "Taillow", 7, 7),
            (300, "Skitty", 7, 7), (293, "Whismur", 7, 7),
        ])),
        // Route 119
        WildEncounterRoute(gameVersions: [.ruby, .sapphire], locationName: "Route 119", encounterType: .grass, slots: gs([
            (263, "Zigzagoon", 25, 25), (264, "Linoone", 25, 25),
            (352, "Kecleon", 25, 25), (043, "Oddish", 25, 25),
            (044, "Gloom", 25, 25), (276, "Taillow", 25, 25),
            (277, "Swellow", 26, 26), (357, "Tropius", 25, 25),
            (357, "Tropius", 26, 26), (357, "Tropius", 27, 27),
            (352, "Kecleon", 26, 26), (352, "Kecleon", 27, 27),
        ])),
        // Meteor Falls
        WildEncounterRoute(gameVersions: [.ruby, .sapphire], locationName: "Meteor Falls", encounterType: .grass, slots: gs([
            (041, "Zubat", 16, 16), (041, "Zubat", 17, 17),
            (041, "Zubat", 18, 18), (338, "Solrock", 16, 16),
            (041, "Zubat", 15, 15), (338, "Solrock", 17, 17),
            (338, "Solrock", 18, 18), (041, "Zubat", 14, 14),
            (338, "Solrock", 14, 14), (338, "Solrock", 15, 15),
            (041, "Zubat", 19, 19), (338, "Solrock", 19, 19),
        ])),
        // Victory Road
        WildEncounterRoute(gameVersions: [.ruby, .sapphire], locationName: "Victory Road", encounterType: .grass, slots: gs([
            (042, "Golbat", 40, 40), (296, "Makuhita", 40, 40),
            (297, "Hariyama", 40, 40), (294, "Loudred", 40, 40),
            (304, "Aron", 40, 40), (305, "Lairon", 40, 40),
            (302, "Sableye", 40, 40), (303, "Mawile", 40, 40),
            (042, "Golbat", 38, 38), (042, "Golbat", 42, 42),
            (296, "Makuhita", 38, 38), (297, "Hariyama", 42, 42),
        ])),
        // Safari Zone
        WildEncounterRoute(gameVersions: [.ruby, .sapphire], locationName: "Safari Zone", encounterType: .grass, slots: gs([
            (043, "Oddish", 25, 25), (044, "Gloom", 27, 27),
            (084, "Doduo", 25, 25), (177, "Natu", 25, 25),
            (084, "Doduo", 27, 27), (177, "Natu", 27, 27),
            (043, "Oddish", 27, 27), (127, "Pinsir", 25, 25),
            (214, "Heracross", 25, 25), (127, "Pinsir", 27, 27),
            (214, "Heracross", 27, 27), (127, "Pinsir", 29, 29),
        ])),
    ]

    // MARK: Emerald

    static let emerald: [WildEncounterRoute] = [
        // Route 101
        WildEncounterRoute(gameVersions: [.emerald], locationName: "Route 101", encounterType: .grass, slots: gs([
            (263, "Zigzagoon", 2, 2), (265, "Wurmple", 2, 2),
            (263, "Zigzagoon", 3, 3), (265, "Wurmple", 3, 3),
            (263, "Zigzagoon", 2, 2), (265, "Wurmple", 2, 2),
            (263, "Zigzagoon", 3, 3), (265, "Wurmple", 3, 3),
            (261, "Poochyena", 2, 2), (261, "Poochyena", 2, 2),
            (261, "Poochyena", 3, 3), (261, "Poochyena", 3, 3),
        ])),
        // Route 102
        WildEncounterRoute(gameVersions: [.emerald], locationName: "Route 102", encounterType: .grass, slots: gs([
            (263, "Zigzagoon", 3, 3), (265, "Wurmple", 3, 3),
            (280, "Ralts", 4, 4), (261, "Poochyena", 3, 3),
            (273, "Seedot", 3, 3), (270, "Lotad", 3, 3),
            (276, "Taillow", 3, 3), (276, "Taillow", 4, 4),
            (283, "Surskit", 3, 3), (283, "Surskit", 4, 4),
            (273, "Seedot", 4, 4), (270, "Lotad", 4, 4),
        ])),
        // Route 103
        WildEncounterRoute(gameVersions: [.emerald], locationName: "Route 103", encounterType: .grass, slots: gs([
            (263, "Zigzagoon", 2, 2), (261, "Poochyena", 2, 2),
            (263, "Zigzagoon", 3, 3), (261, "Poochyena", 3, 3),
            (278, "Wingull", 2, 2), (278, "Wingull", 3, 3),
            (263, "Zigzagoon", 2, 2), (261, "Poochyena", 2, 2),
            (263, "Zigzagoon", 3, 3), (261, "Poochyena", 3, 3),
            (263, "Zigzagoon", 3, 3), (261, "Poochyena", 3, 3),
        ])),
        // Route 110
        WildEncounterRoute(gameVersions: [.emerald], locationName: "Route 110", encounterType: .grass, slots: gs([
            (261, "Poochyena", 12, 12), (309, "Electrike", 12, 12),
            (100, "Voltorb", 12, 12), (311, "Plusle", 12, 12),
            (312, "Minun", 12, 12), (263, "Zigzagoon", 12, 12),
            (278, "Wingull", 12, 12), (081, "Magnemite", 12, 12),
            (312, "Minun", 13, 13), (311, "Plusle", 13, 13),
            (309, "Electrike", 13, 13), (100, "Voltorb", 13, 13),
        ])),
        // Route 119
        WildEncounterRoute(gameVersions: [.emerald], locationName: "Route 119", encounterType: .grass, slots: gs([
            (263, "Zigzagoon", 25, 25), (264, "Linoone", 25, 25),
            (043, "Oddish", 25, 25), (044, "Gloom", 25, 25),
            (352, "Kecleon", 25, 25), (276, "Taillow", 25, 25),
            (277, "Swellow", 26, 26), (357, "Tropius", 25, 25),
            (357, "Tropius", 26, 26), (357, "Tropius", 27, 27),
            (352, "Kecleon", 26, 26), (352, "Kecleon", 27, 27),
        ])),
        // Petalburg Woods
        WildEncounterRoute(gameVersions: [.emerald], locationName: "Petalburg Woods", encounterType: .grass, slots: gs([
            (263, "Zigzagoon", 5, 5), (265, "Wurmple", 5, 5),
            (285, "Shroomish", 5, 5), (266, "Silcoon", 5, 5),
            (276, "Taillow", 5, 5), (268, "Cascoon", 5, 5),
            (265, "Wurmple", 6, 6), (285, "Shroomish", 6, 6),
            (290, "Nincada", 5, 5), (290, "Nincada", 6, 6),
            (263, "Zigzagoon", 6, 6), (276, "Taillow", 6, 6),
        ])),
        // Meteor Falls
        WildEncounterRoute(gameVersions: [.emerald], locationName: "Meteor Falls", encounterType: .grass, slots: gs([
            (041, "Zubat", 16, 16), (041, "Zubat", 17, 17),
            (041, "Zubat", 18, 18), (338, "Solrock", 16, 16),
            (337, "Lunatone", 16, 16), (338, "Solrock", 17, 17),
            (337, "Lunatone", 17, 17), (041, "Zubat", 15, 15),
            (338, "Solrock", 18, 18), (337, "Lunatone", 18, 18),
            (041, "Zubat", 14, 14), (041, "Zubat", 19, 19),
        ])),
        // Victory Road
        WildEncounterRoute(gameVersions: [.emerald], locationName: "Victory Road", encounterType: .grass, slots: gs([
            (042, "Golbat", 40, 40), (296, "Makuhita", 36, 36),
            (297, "Hariyama", 40, 40), (294, "Loudred", 40, 40),
            (304, "Aron", 40, 40), (305, "Lairon", 40, 40),
            (302, "Sableye", 38, 38), (303, "Mawile", 38, 38),
            (042, "Golbat", 38, 38), (042, "Golbat", 42, 42),
            (297, "Hariyama", 38, 38), (305, "Lairon", 42, 42),
        ])),
        // Safari Zone
        WildEncounterRoute(gameVersions: [.emerald], locationName: "Safari Zone", encounterType: .grass, slots: gs([
            (043, "Oddish", 25, 25), (044, "Gloom", 27, 27),
            (084, "Doduo", 25, 25), (177, "Natu", 25, 25),
            (084, "Doduo", 27, 27), (177, "Natu", 27, 27),
            (043, "Oddish", 27, 27), (127, "Pinsir", 25, 25),
            (214, "Heracross", 25, 25), (127, "Pinsir", 27, 27),
            (214, "Heracross", 27, 27), (127, "Pinsir", 29, 29),
        ])),
    ]

    // MARK: FireRed/LeafGreen

    static let fireRedLeafGreen: [WildEncounterRoute] = [
        // Route 1
        WildEncounterRoute(gameVersions: [.fireRed, .leafGreen], locationName: "Route 1", encounterType: .grass, slots: gs([
            (019, "Rattata", 2, 2), (016, "Pidgey", 2, 2),
            (019, "Rattata", 3, 3), (016, "Pidgey", 3, 3),
            (019, "Rattata", 3, 3), (016, "Pidgey", 3, 3),
            (019, "Rattata", 2, 2), (016, "Pidgey", 2, 2),
            (019, "Rattata", 2, 2), (016, "Pidgey", 2, 2),
            (019, "Rattata", 3, 3), (016, "Pidgey", 3, 3),
        ])),
        // Route 2
        WildEncounterRoute(gameVersions: [.fireRed, .leafGreen], locationName: "Route 2", encounterType: .grass, slots: gs([
            (019, "Rattata", 2, 2), (016, "Pidgey", 2, 2),
            (010, "Caterpie", 3, 3), (013, "Weedle", 3, 3),
            (016, "Pidgey", 3, 3), (019, "Rattata", 3, 3),
            (010, "Caterpie", 4, 4), (013, "Weedle", 4, 4),
            (016, "Pidgey", 4, 4), (019, "Rattata", 4, 4),
            (010, "Caterpie", 5, 5), (013, "Weedle", 5, 5),
        ])),
        // Viridian Forest
        WildEncounterRoute(gameVersions: [.fireRed, .leafGreen], locationName: "Viridian Forest", encounterType: .grass, slots: gs([
            (010, "Caterpie", 4, 4), (013, "Weedle", 4, 4),
            (010, "Caterpie", 5, 5), (013, "Weedle", 5, 5),
            (011, "Metapod", 4, 4), (014, "Kakuna", 4, 4),
            (011, "Metapod", 5, 5), (014, "Kakuna", 5, 5),
            (025, "Pikachu", 3, 3), (025, "Pikachu", 5, 5),
            (010, "Caterpie", 3, 3), (013, "Weedle", 3, 3),
        ])),
        // Mt. Moon
        WildEncounterRoute(gameVersions: [.fireRed, .leafGreen], locationName: "Mt. Moon", encounterType: .grass, slots: gs([
            (041, "Zubat", 8, 8), (074, "Geodude", 7, 7),
            (041, "Zubat", 7, 7), (046, "Paras", 8, 8),
            (041, "Zubat", 9, 9), (074, "Geodude", 8, 8),
            (046, "Paras", 10, 10), (035, "Clefairy", 8, 8),
            (041, "Zubat", 10, 10), (074, "Geodude", 9, 9),
            (035, "Clefairy", 10, 10), (035, "Clefairy", 12, 12),
        ])),
        // Rock Tunnel
        WildEncounterRoute(gameVersions: [.fireRed, .leafGreen], locationName: "Rock Tunnel", encounterType: .grass, slots: gs([
            (041, "Zubat", 15, 15), (074, "Geodude", 15, 15),
            (066, "Machop", 15, 15), (041, "Zubat", 16, 16),
            (074, "Geodude", 16, 16), (066, "Machop", 17, 17),
            (095, "Onix", 13, 13), (095, "Onix", 15, 15),
            (041, "Zubat", 17, 17), (074, "Geodude", 17, 17),
            (066, "Machop", 16, 16), (095, "Onix", 17, 17),
        ])),
        // Route 6
        WildEncounterRoute(gameVersions: [.fireRed, .leafGreen], locationName: "Route 6", encounterType: .grass, slots: gs([
            (016, "Pidgey", 13, 13), (043, "Oddish", 12, 12),
            (016, "Pidgey", 14, 14), (043, "Oddish", 13, 13),
            (056, "Mankey", 10, 10), (052, "Meowth", 10, 10),
            (056, "Mankey", 12, 12), (052, "Meowth", 12, 12),
            (016, "Pidgey", 15, 15), (043, "Oddish", 14, 14),
            (056, "Mankey", 14, 14), (052, "Meowth", 14, 14),
        ])),
        // Safari Zone
        WildEncounterRoute(gameVersions: [.fireRed, .leafGreen], locationName: "Safari Zone Center", encounterType: .grass, slots: gs([
            (029, "Nidoran♀", 22, 22), (032, "Nidoran♂", 22, 22),
            (030, "Nidorina", 25, 25), (033, "Nidorino", 25, 25),
            (046, "Paras", 22, 22), (047, "Parasect", 25, 25),
            (049, "Venomoth", 32, 32), (102, "Exeggcute", 24, 24),
            (113, "Chansey", 23, 23), (128, "Tauros", 25, 25),
            (115, "Kangaskhan", 25, 25), (123, "Scyther", 25, 25),
        ])),
        // Pokemon Tower
        WildEncounterRoute(gameVersions: [.fireRed, .leafGreen], locationName: "Pokemon Tower", encounterType: .grass, slots: gs([
            (092, "Gastly", 13, 13), (092, "Gastly", 14, 14),
            (092, "Gastly", 15, 15), (092, "Gastly", 16, 16),
            (104, "Cubone", 13, 13), (104, "Cubone", 15, 15),
            (092, "Gastly", 17, 17), (092, "Gastly", 18, 18),
            (093, "Haunter", 15, 15), (093, "Haunter", 17, 17),
            (104, "Cubone", 17, 17), (093, "Haunter", 19, 19),
        ])),
        // Cerulean Cave
        WildEncounterRoute(gameVersions: [.fireRed, .leafGreen], locationName: "Cerulean Cave", encounterType: .grass, slots: gs([
            (042, "Golbat", 46, 46), (064, "Kadabra", 46, 46),
            (082, "Magneton", 46, 46), (047, "Parasect", 46, 46),
            (057, "Primeape", 46, 46), (112, "Rhydon", 46, 46),
            (042, "Golbat", 49, 49), (064, "Kadabra", 49, 49),
            (132, "Ditto", 46, 46), (132, "Ditto", 49, 49),
            (131, "Lapras", 49, 49), (132, "Ditto", 52, 52),
        ])),
        // Power Plant
        WildEncounterRoute(gameVersions: [.fireRed, .leafGreen], locationName: "Power Plant", encounterType: .grass, slots: gs([
            (100, "Voltorb", 22, 22), (081, "Magnemite", 22, 22),
            (100, "Voltorb", 24, 24), (081, "Magnemite", 24, 24),
            (100, "Voltorb", 26, 26), (082, "Magneton", 26, 26),
            (101, "Electrode", 28, 28), (082, "Magneton", 28, 28),
            (125, "Electabuzz", 32, 32), (125, "Electabuzz", 35, 35),
            (101, "Electrode", 30, 30), (082, "Magneton", 30, 30),
        ])),
    ]

    // MARK: Diamond/Pearl

    static let diamondPearl: [WildEncounterRoute] = [
        // Route 201
        WildEncounterRoute(gameVersions: [.diamond, .pearl], locationName: "Route 201", encounterType: .grass, slots: gs([
            (396, "Starly", 2, 2), (399, "Bidoof", 2, 2),
            (396, "Starly", 3, 3), (399, "Bidoof", 3, 3),
            (396, "Starly", 2, 2), (399, "Bidoof", 2, 2),
            (396, "Starly", 3, 3), (399, "Bidoof", 3, 3),
            (396, "Starly", 2, 2), (399, "Bidoof", 2, 2),
            (396, "Starly", 3, 3), (399, "Bidoof", 3, 3),
        ])),
        // Route 202
        WildEncounterRoute(gameVersions: [.diamond, .pearl], locationName: "Route 202", encounterType: .grass, slots: gs([
            (396, "Starly", 3, 3), (399, "Bidoof", 3, 3),
            (401, "Kricketot", 3, 3), (396, "Starly", 4, 4),
            (399, "Bidoof", 4, 4), (401, "Kricketot", 4, 4),
            (403, "Shinx", 3, 3), (403, "Shinx", 4, 4),
            (396, "Starly", 3, 3), (399, "Bidoof", 3, 3),
            (401, "Kricketot", 3, 3), (403, "Shinx", 3, 3),
        ])),
        // Route 203
        WildEncounterRoute(gameVersions: [.diamond, .pearl], locationName: "Route 203", encounterType: .grass, slots: gs([
            (396, "Starly", 4, 4), (063, "Abra", 4, 4),
            (399, "Bidoof", 4, 4), (403, "Shinx", 4, 4),
            (396, "Starly", 5, 5), (063, "Abra", 5, 5),
            (399, "Bidoof", 5, 5), (403, "Shinx", 5, 5),
            (396, "Starly", 4, 4), (063, "Abra", 4, 4),
            (399, "Bidoof", 4, 4), (403, "Shinx", 4, 4),
        ])),
        // Route 204
        WildEncounterRoute(gameVersions: [.diamond, .pearl], locationName: "Route 204", encounterType: .grass, slots: gs([
            (399, "Bidoof", 4, 4), (265, "Wurmple", 4, 4),
            (396, "Starly", 4, 4), (399, "Bidoof", 5, 5),
            (265, "Wurmple", 5, 5), (396, "Starly", 5, 5),
            (406, "Budew", 4, 4), (406, "Budew", 5, 5),
            (399, "Bidoof", 3, 3), (265, "Wurmple", 3, 3),
            (406, "Budew", 3, 3), (406, "Budew", 6, 6),
        ])),
        // Eterna Forest
        WildEncounterRoute(gameVersions: [.diamond, .pearl], locationName: "Eterna Forest", encounterType: .grass, slots: gs([
            (399, "Bidoof", 10, 10), (265, "Wurmple", 10, 10),
            (266, "Silcoon", 10, 10), (268, "Cascoon", 10, 10),
            (415, "Combee", 10, 10), (406, "Budew", 10, 10),
            (420, "Cherubi", 10, 10), (092, "Gastly", 12, 12),
            (397, "Staravia", 12, 12), (400, "Bibarel", 12, 12),
            (415, "Combee", 11, 11), (420, "Cherubi", 11, 11),
        ])),
        // Route 209
        WildEncounterRoute(gameVersions: [.diamond, .pearl], locationName: "Route 209", encounterType: .grass, slots: gs([
            (396, "Starly", 16, 16), (399, "Bidoof", 16, 16),
            (397, "Staravia", 16, 16), (400, "Bibarel", 16, 16),
            (183, "Marill", 18, 18), (183, "Marill", 20, 20),
            (054, "Psyduck", 18, 18), (054, "Psyduck", 20, 20),
            (442, "Spiritomb", 25, 25), (442, "Spiritomb", 25, 25),
            (183, "Marill", 22, 22), (054, "Psyduck", 22, 22),
        ])),
        // Mt. Coronet
        WildEncounterRoute(gameVersions: [.diamond, .pearl], locationName: "Mt. Coronet (1F)", encounterType: .grass, slots: gs([
            (041, "Zubat", 14, 14), (074, "Geodude", 14, 14),
            (436, "Bronzor", 14, 14), (041, "Zubat", 15, 15),
            (074, "Geodude", 15, 15), (436, "Bronzor", 15, 15),
            (042, "Golbat", 16, 16), (075, "Graveler", 16, 16),
            (066, "Machop", 14, 14), (066, "Machop", 15, 15),
            (035, "Clefairy", 14, 14), (035, "Clefairy", 15, 15),
        ])),
        // Lake Verity
        WildEncounterRoute(gameVersions: [.diamond, .pearl], locationName: "Lake Verity", encounterType: .grass, slots: gs([
            (396, "Starly", 2, 2), (399, "Bidoof", 2, 2),
            (396, "Starly", 3, 3), (399, "Bidoof", 3, 3),
            (396, "Starly", 4, 4), (399, "Bidoof", 4, 4),
            (396, "Starly", 2, 2), (399, "Bidoof", 2, 2),
            (396, "Starly", 3, 3), (399, "Bidoof", 3, 3),
            (396, "Starly", 4, 4), (399, "Bidoof", 4, 4),
        ])),
        // Victory Road
        WildEncounterRoute(gameVersions: [.diamond, .pearl], locationName: "Victory Road", encounterType: .grass, slots: gs([
            (042, "Golbat", 41, 41), (307, "Meditite", 40, 40),
            (308, "Medicham", 42, 42), (075, "Graveler", 41, 41),
            (095, "Onix", 41, 41), (042, "Golbat", 42, 42),
            (307, "Meditite", 42, 42), (308, "Medicham", 44, 44),
            (075, "Graveler", 43, 43), (095, "Onix", 43, 43),
            (042, "Golbat", 44, 44), (308, "Medicham", 46, 46),
        ])),
    ]

    // MARK: Platinum

    static let platinum: [WildEncounterRoute] = [
        // Route 201
        WildEncounterRoute(gameVersions: [.platinum], locationName: "Route 201", encounterType: .grass, slots: gs([
            (396, "Starly", 2, 2), (399, "Bidoof", 2, 2),
            (396, "Starly", 3, 3), (399, "Bidoof", 3, 3),
            (396, "Starly", 2, 2), (399, "Bidoof", 2, 2),
            (401, "Kricketot", 2, 2), (401, "Kricketot", 3, 3),
            (396, "Starly", 3, 3), (399, "Bidoof", 3, 3),
            (396, "Starly", 2, 2), (399, "Bidoof", 2, 2),
        ])),
        // Route 202
        WildEncounterRoute(gameVersions: [.platinum], locationName: "Route 202", encounterType: .grass, slots: gs([
            (396, "Starly", 3, 3), (399, "Bidoof", 3, 3),
            (401, "Kricketot", 3, 3), (396, "Starly", 4, 4),
            (399, "Bidoof", 4, 4), (401, "Kricketot", 4, 4),
            (403, "Shinx", 3, 3), (403, "Shinx", 4, 4),
            (396, "Starly", 3, 3), (399, "Bidoof", 3, 3),
            (401, "Kricketot", 3, 3), (403, "Shinx", 3, 3),
        ])),
        // Eterna Forest
        WildEncounterRoute(gameVersions: [.platinum], locationName: "Eterna Forest", encounterType: .grass, slots: gs([
            (399, "Bidoof", 10, 10), (406, "Budew", 10, 10),
            (415, "Combee", 10, 10), (265, "Wurmple", 10, 10),
            (266, "Silcoon", 10, 10), (268, "Cascoon", 10, 10),
            (420, "Cherubi", 10, 10), (092, "Gastly", 12, 12),
            (397, "Staravia", 12, 12), (400, "Bibarel", 12, 12),
            (415, "Combee", 11, 11), (420, "Cherubi", 11, 11),
        ])),
        // Mt. Coronet
        WildEncounterRoute(gameVersions: [.platinum], locationName: "Mt. Coronet (1F)", encounterType: .grass, slots: gs([
            (041, "Zubat", 14, 14), (074, "Geodude", 14, 14),
            (436, "Bronzor", 14, 14), (041, "Zubat", 15, 15),
            (074, "Geodude", 15, 15), (436, "Bronzor", 15, 15),
            (042, "Golbat", 16, 16), (075, "Graveler", 16, 16),
            (066, "Machop", 14, 14), (066, "Machop", 15, 15),
            (035, "Clefairy", 14, 14), (035, "Clefairy", 15, 15),
        ])),
        // Distortion World
        WildEncounterRoute(gameVersions: [.platinum], locationName: "Stark Mountain", encounterType: .grass, slots: gs([
            (322, "Numel", 52, 52), (323, "Camerupt", 54, 54),
            (218, "Slugma", 52, 52), (219, "Magcargo", 54, 54),
            (075, "Graveler", 55, 55), (112, "Rhydon", 56, 56),
            (042, "Golbat", 52, 52), (323, "Camerupt", 56, 56),
            (322, "Numel", 54, 54), (218, "Slugma", 54, 54),
            (219, "Magcargo", 56, 56), (075, "Graveler", 57, 57),
        ])),
        // Victory Road
        WildEncounterRoute(gameVersions: [.platinum], locationName: "Victory Road", encounterType: .grass, slots: gs([
            (042, "Golbat", 41, 41), (307, "Meditite", 40, 40),
            (308, "Medicham", 42, 42), (075, "Graveler", 41, 41),
            (095, "Onix", 41, 41), (042, "Golbat", 42, 42),
            (308, "Medicham", 44, 44), (075, "Graveler", 43, 43),
            (207, "Gligar", 41, 41), (207, "Gligar", 43, 43),
            (042, "Golbat", 44, 44), (308, "Medicham", 46, 46),
        ])),
    ]

    // MARK: HeartGold/SoulSilver

    static let heartGoldSoulSilver: [WildEncounterRoute] = [
        // Route 29
        WildEncounterRoute(gameVersions: [.heartGold, .soulSilver], locationName: "Route 29", encounterType: .grass, slots: gs([
            (016, "Pidgey", 2, 2), (019, "Rattata", 2, 2),
            (161, "Sentret", 2, 2), (016, "Pidgey", 3, 3),
            (019, "Rattata", 3, 3), (161, "Sentret", 3, 3),
            (016, "Pidgey", 2, 2), (019, "Rattata", 2, 2),
            (187, "Hoppip", 2, 2), (187, "Hoppip", 3, 3),
            (016, "Pidgey", 3, 3), (019, "Rattata", 3, 3),
        ])),
        // Route 30
        WildEncounterRoute(gameVersions: [.heartGold, .soulSilver], locationName: "Route 30", encounterType: .grass, slots: gs([
            (016, "Pidgey", 3, 3), (010, "Caterpie", 3, 3),
            (013, "Weedle", 3, 3), (011, "Metapod", 4, 4),
            (014, "Kakuna", 4, 4), (016, "Pidgey", 4, 4),
            (187, "Hoppip", 4, 4), (010, "Caterpie", 4, 4),
            (013, "Weedle", 4, 4), (016, "Pidgey", 5, 5),
            (187, "Hoppip", 5, 5), (016, "Pidgey", 3, 3),
        ])),
        // Route 31
        WildEncounterRoute(gameVersions: [.heartGold, .soulSilver], locationName: "Route 31", encounterType: .grass, slots: gs([
            (016, "Pidgey", 5, 5), (010, "Caterpie", 4, 4),
            (013, "Weedle", 4, 4), (069, "Bellsprout", 5, 5),
            (187, "Hoppip", 5, 5), (016, "Pidgey", 6, 6),
            (010, "Caterpie", 5, 5), (013, "Weedle", 5, 5),
            (069, "Bellsprout", 6, 6), (187, "Hoppip", 6, 6),
            (016, "Pidgey", 7, 7), (069, "Bellsprout", 7, 7),
        ])),
        // Route 32
        WildEncounterRoute(gameVersions: [.heartGold, .soulSilver], locationName: "Route 32", encounterType: .grass, slots: gs([
            (019, "Rattata", 7, 7), (041, "Zubat", 4, 4),
            (069, "Bellsprout", 6, 6), (187, "Hoppip", 6, 6),
            (194, "Wooper", 6, 6), (179, "Mareep", 6, 6),
            (019, "Rattata", 6, 6), (041, "Zubat", 6, 6),
            (069, "Bellsprout", 7, 7), (179, "Mareep", 7, 7),
            (194, "Wooper", 7, 7), (187, "Hoppip", 7, 7),
        ])),
        // Sprout Tower
        WildEncounterRoute(gameVersions: [.heartGold, .soulSilver], locationName: "Sprout Tower", encounterType: .grass, slots: gs([
            (019, "Rattata", 3, 3), (092, "Gastly", 3, 3),
            (019, "Rattata", 4, 4), (092, "Gastly", 4, 4),
            (019, "Rattata", 5, 5), (092, "Gastly", 5, 5),
            (019, "Rattata", 3, 3), (092, "Gastly", 3, 3),
            (019, "Rattata", 6, 6), (092, "Gastly", 6, 6),
            (019, "Rattata", 3, 3), (092, "Gastly", 3, 3),
        ])),
        // Route 34
        WildEncounterRoute(gameVersions: [.heartGold, .soulSilver], locationName: "Route 34", encounterType: .grass, slots: gs([
            (019, "Rattata", 10, 10), (132, "Ditto", 10, 10),
            (063, "Abra", 10, 10), (096, "Drowzee", 10, 10),
            (019, "Rattata", 12, 12), (132, "Ditto", 12, 12),
            (063, "Abra", 12, 12), (096, "Drowzee", 12, 12),
            (019, "Rattata", 11, 11), (132, "Ditto", 11, 11),
            (063, "Abra", 11, 11), (096, "Drowzee", 11, 11),
        ])),
        // National Park
        WildEncounterRoute(gameVersions: [.heartGold, .soulSilver], locationName: "National Park", encounterType: .grass, slots: gs([
            (010, "Caterpie", 10, 10), (011, "Metapod", 10, 10),
            (013, "Weedle", 10, 10), (014, "Kakuna", 10, 10),
            (016, "Pidgey", 10, 10), (187, "Hoppip", 10, 10),
            (191, "Sunkern", 10, 10), (016, "Pidgey", 12, 12),
            (010, "Caterpie", 12, 12), (013, "Weedle", 12, 12),
            (187, "Hoppip", 12, 12), (191, "Sunkern", 12, 12),
        ])),
        // Mt. Silver
        WildEncounterRoute(gameVersions: [.heartGold, .soulSilver], locationName: "Mt. Silver (Outside)", encounterType: .grass, slots: gs([
            (042, "Golbat", 42, 42), (217, "Ursaring", 42, 42),
            (075, "Graveler", 42, 42), (095, "Onix", 42, 42),
            (215, "Sneasel", 42, 42), (042, "Golbat", 44, 44),
            (217, "Ursaring", 44, 44), (075, "Graveler", 44, 44),
            (095, "Onix", 44, 44), (215, "Sneasel", 44, 44),
            (042, "Golbat", 46, 46), (217, "Ursaring", 46, 46),
        ])),
        // Safari Zone
        WildEncounterRoute(gameVersions: [.heartGold, .soulSilver], locationName: "Safari Zone (Plains)", encounterType: .grass, slots: gs([
            (029, "Nidoran♀", 15, 15), (032, "Nidoran♂", 15, 15),
            (084, "Doduo", 17, 17), (016, "Pidgey", 15, 15),
            (029, "Nidoran♀", 17, 17), (032, "Nidoran♂", 17, 17),
            (084, "Doduo", 15, 15), (016, "Pidgey", 17, 17),
            (029, "Nidoran♀", 16, 16), (032, "Nidoran♂", 16, 16),
            (084, "Doduo", 16, 16), (016, "Pidgey", 16, 16),
        ])),
        // Route 45
        WildEncounterRoute(gameVersions: [.heartGold, .soulSilver], locationName: "Route 45", encounterType: .grass, slots: gs([
            (074, "Geodude", 22, 22), (075, "Graveler", 24, 24),
            (231, "Phanpy", 22, 22), (232, "Donphan", 24, 24),
            (027, "Sandshrew", 22, 22), (041, "Zubat", 22, 22),
            (042, "Golbat", 24, 24), (231, "Phanpy", 24, 24),
            (232, "Donphan", 26, 26), (074, "Geodude", 24, 24),
            (075, "Graveler", 26, 26), (027, "Sandshrew", 24, 24),
        ])),
    ]

    // MARK: Lookup

    static func wildRoutes(for game: FinderGameVersion) -> [WildEncounterRoute] {
        let allRoutes: [WildEncounterRoute]
        switch game {
        case .ruby, .sapphire:
            allRoutes = rubySapphire
        case .emerald:
            allRoutes = emerald
        case .fireRed, .leafGreen:
            allRoutes = fireRedLeafGreen
        case .diamond, .pearl:
            allRoutes = diamondPearl
        case .platinum:
            allRoutes = platinum
        case .heartGold, .soulSilver:
            allRoutes = heartGoldSoulSilver
        }
        return allRoutes.filter { $0.gameVersions.contains(game) }
    }

    static func locationNames(for game: FinderGameVersion) -> [String] {
        let routes = wildRoutes(for: game)
        var seen = Set<String>()
        return routes.compactMap { r in
            if seen.contains(r.locationName) { return nil }
            seen.insert(r.locationName)
            return r.locationName
        }
    }

    static func encounterTypes(for game: FinderGameVersion, location: String) -> [EncounterType] {
        wildRoutes(for: game)
            .filter { $0.locationName == location }
            .map { $0.encounterType }
    }

    static func wildEncounter(for game: FinderGameVersion, location: String, type: EncounterType) -> WildEncounterRoute? {
        wildRoutes(for: game).first { $0.locationName == location && $0.encounterType == type }
    }
}
