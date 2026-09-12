//
//  ShowdownItems.swift
//  PKDex
//
//  Port of @smogon/calc's items.ts helpers used by the damage pipeline
//  (type-boost items, resist berries, Fling power, terrain-seed stats).
//  MIT — see PKDex/ShowdownPort-NOTES.md.
//

import Foundation

enum ShowdownItems {
    /// Which defensive stat a terrain seed boosts.
    static let seedBoostedStat: [String: ShowdownStat] = [
        "Electric Seed": .def, "Grassy Seed": .def, "Misty Seed": .spd, "Psychic Seed": .spd,
    ]

    /// 1.2× type-boosting held items (Plates, incenses, type items) → boosted type.
    static func itemBoostType(_ item: String?) -> ShowdownType? {
        switch item {
        case "Draco Plate", "Dragon Fang": return .dragon
        case "Dread Plate", "Black Glasses": return .dark
        case "Earth Plate", "Soft Sand": return .ground
        case "Fist Plate", "Black Belt": return .fighting
        case "Flame Plate", "Charcoal": return .fire
        case "Icicle Plate", "Never-Melt Ice": return .ice
        case "Insect Plate", "Silver Powder": return .bug
        case "Iron Plate", "Metal Coat": return .steel
        case "Meadow Plate", "Rose Incense", "Miracle Seed": return .grass
        case "Mind Plate", "Odd Incense", "Twisted Spoon": return .psychic
        case "Fairy Feather", "Pixie Plate": return .fairy
        case "Sky Plate", "Sharp Beak": return .flying
        case "Splash Plate", "Sea Incense", "Wave Incense", "Mystic Water": return .water
        case "Spooky Plate", "Spell Tag": return .ghost
        case "Stone Plate", "Rock Incense", "Hard Stone": return .rock
        case "Toxic Plate", "Poison Barb": return .poison
        case "Zap Plate", "Magnet": return .electric
        case "Silk Scarf", "Pink Bow", "Polkadot Bow": return .normal
        default: return nil
        }
    }

    /// Resist-berry → the type it halves (on a super-effective / Normal hit).
    static func berryResistType(_ berry: String?) -> ShowdownType? {
        switch berry {
        case "Chilan Berry": return .normal
        case "Occa Berry": return .fire
        case "Passho Berry": return .water
        case "Wacan Berry": return .electric
        case "Rindo Berry": return .grass
        case "Yache Berry": return .ice
        case "Chople Berry": return .fighting
        case "Kebia Berry": return .poison
        case "Shuca Berry": return .ground
        case "Coba Berry": return .flying
        case "Payapa Berry": return .psychic
        case "Tanga Berry": return .bug
        case "Charti Berry": return .rock
        case "Kasib Berry": return .ghost
        case "Haban Berry": return .dragon
        case "Colbur Berry": return .dark
        case "Babiri Berry": return .steel
        case "Roseli Berry": return .fairy
        default: return nil
        }
    }

    private static let fling60: Set<String> = [
        "Adamant Orb", "Damp Rock", "Heat Rock", "Leek", "Lustrous Orb", "Macho Brace",
        "Rocky Helmet", "Stick", "Utility Umbrella", "Terrain Extender",
    ]
    private static let fling30: Set<String> = [
        "Absorb Bulb", "Black Belt", "Black Sludge", "Black Glasses", "Cell Battery", "Charcoal",
        "Flame Orb", "King's Rock", "Life Orb", "Light Ball", "Light Clay", "Magnet", "Metal Coat",
        "Miracle Seed", "Mystic Water", "Never-Melt Ice", "Razor Fang", "Scope Lens", "Spell Tag",
        "Throat Spray", "Toxic Orb", "Twisted Spoon", "Luminous Moss", "Eject Button", "Snowball",
    ]
    private static let fling10: Set<String> = [
        "Air Balloon", "Choice Band", "Choice Scarf", "Choice Specs", "Destiny Knot",
        "Electric Seed", "Expert Belt", "Focus Band", "Focus Sash", "Grassy Seed", "Lagging Tail",
        "Leftovers", "Mental Herb", "Misty Seed", "Muscle Band", "Power Herb", "Psychic Seed",
        "Quick Powder", "Red Card", "Ring Target", "Shed Shell", "Silk Scarf", "Silver Powder",
        "Soft Sand", "White Herb", "Wide Lens", "Wise Glasses", "Zoom Lens",
    ]

    /// Fling base power (Champions-relevant subset + generic Plate/Berry rules,
    /// faithful to items.ts). Fling is rarely used in the format.
    static func flingPower(_ item: String?) -> Int {
        guard let item, !item.isEmpty else { return 0 }
        if item == "Iron Ball" { return 130 }
        if item == "Hard Stone" { return 100 }
        if item.contains("Plate") { return 90 }
        if ["Quick Claw", "Heavy-Duty Boots", "Assault Vest", "Weakness Policy"].contains(item) { return 80 }
        if ["Poison Barb", "Dragon Fang"].contains(item) { return 70 }
        if fling60.contains(item) { return 60 }
        if ["Sharp Beak"].contains(item) { return 50 }
        if ["Eviolite"].contains(item) { return 40 }
        if fling30.contains(item) { return 30 }
        if item.contains("Berry") || fling10.contains(item) { return 10 }
        return 0
    }

    /// Knock Off resist for a held Mega Stone matching its holder (matches the
    /// calc's `item.megaStone` check via the same "ite" heuristic used by
    /// `Pokemon.getForme`). Also true once already Mega-Evolved.
    static func isHeldMegaStone(_ item: String?, speciesName: String) -> Bool {
        guard let item else { return false }
        return item.contains("ite") && !item.contains("ite Y") ? true
             : item.contains("ite Y")
    }
}
