//
//  PokemonStatsModels.swift
//  PKDex
//

import Foundation
import SwiftData

// MARK: - Pokemon with Base Stats, Types, Abilities & Learnset

@Model
final class PKMNStats {
    @Attribute(.unique) var id: Int
    var speciesID: Int
    var name: String
    var formName: String?
    var type1: String
    var type2: String?
    var baseHP: Int
    var baseAtk: Int
    var baseDef: Int
    var baseSpAtk: Int
    var baseSpDef: Int
    var baseSpeed: Int
    var ability1: String?
    var ability2: String?
    var hiddenAbility: String?
    var learnableMoveIDs: [Int]

    init(id: Int, speciesID: Int, name: String, formName: String? = nil,
         type1: String, type2: String? = nil,
         baseHP: Int, baseAtk: Int, baseDef: Int,
         baseSpAtk: Int, baseSpDef: Int, baseSpeed: Int,
         ability1: String? = nil, ability2: String? = nil,
         hiddenAbility: String? = nil, learnableMoveIDs: [Int] = []) {
        self.id = id
        self.speciesID = speciesID
        self.name = name
        self.formName = formName
        self.type1 = type1
        self.type2 = type2
        self.baseHP = baseHP
        self.baseAtk = baseAtk
        self.baseDef = baseDef
        self.baseSpAtk = baseSpAtk
        self.baseSpDef = baseSpDef
        self.baseSpeed = baseSpeed
        self.ability1 = ability1
        self.ability2 = ability2
        self.hiddenAbility = hiddenAbility
        self.learnableMoveIDs = learnableMoveIDs
    }

    var allAbilities: [String] {
        [ability1, ability2, hiddenAbility].compactMap { $0 }
    }

    var isForm: Bool {
        formName != nil && !(formName?.isEmpty ?? true)
    }
}

// MARK: - Move Data

@Model
final class MoveData {
    @Attribute(.unique) var id: Int
    var name: String
    var type: String
    var damageClass: String // "physical", "special"
    var power: Int?
    var accuracy: Int?
    var pp: Int
    var priority: Int
    var minHits: Int?
    var maxHits: Int?
    var drain: Int
    var healing: Int
    var critRate: Int
    var makesContact: Bool
    var generationId: Int

    init(id: Int, name: String, type: String, damageClass: String,
         power: Int? = nil, accuracy: Int? = nil, pp: Int = 0, priority: Int = 0,
         minHits: Int? = nil, maxHits: Int? = nil,
         drain: Int = 0, healing: Int = 0, critRate: Int = 0, makesContact: Bool = false,
         generationId: Int = 0) {
        self.id = id
        self.name = name
        self.type = type
        self.damageClass = damageClass
        self.power = power
        self.accuracy = accuracy
        self.pp = pp
        self.priority = priority
        self.minHits = minHits
        self.maxHits = maxHits
        self.drain = drain
        self.healing = healing
        self.critRate = critRate
        self.makesContact = makesContact
        self.generationId = generationId
    }
}

// MARK: - Nature

struct Nature: Identifiable, Hashable {
    let id: String
    let name: String
    let boosted: StatKey?
    let lowered: StatKey?

    enum StatKey: String, CaseIterable {
        case atk, def, spAtk, spDef, speed

        var label: String {
            switch self {
            case .atk:   return "Atk"
            case .def:   return "Def"
            case .spAtk: return "Sp.Atk"
            case .spDef: return "Sp.Def"
            case .speed: return "Speed"
            }
        }
    }

    func modifier(for stat: StatKey) -> Double {
        if let b = boosted, b == stat { return 1.1 }
        if let l = lowered, l == stat { return 0.9 }
        return 1.0
    }

    var summary: String {
        guard let b = boosted, let l = lowered else { return "Neutral" }
        return "+\(b.label) / -\(l.label)"
    }
}

let allNatures: [Nature] = [
    Nature(id: "hardy",   name: "Hardy",   boosted: nil,    lowered: nil),
    Nature(id: "docile",  name: "Docile",  boosted: nil,    lowered: nil),
    Nature(id: "serious", name: "Serious", boosted: nil,    lowered: nil),
    Nature(id: "bashful", name: "Bashful", boosted: nil,    lowered: nil),
    Nature(id: "quirky",  name: "Quirky",  boosted: nil,    lowered: nil),
    Nature(id: "lonely",  name: "Lonely",  boosted: .atk,   lowered: .def),
    Nature(id: "brave",   name: "Brave",   boosted: .atk,   lowered: .speed),
    Nature(id: "adamant", name: "Adamant", boosted: .atk,   lowered: .spAtk),
    Nature(id: "naughty", name: "Naughty", boosted: .atk,   lowered: .spDef),
    Nature(id: "bold",    name: "Bold",    boosted: .def,   lowered: .atk),
    Nature(id: "relaxed", name: "Relaxed", boosted: .def,   lowered: .speed),
    Nature(id: "impish",  name: "Impish",  boosted: .def,   lowered: .spAtk),
    Nature(id: "lax",     name: "Lax",     boosted: .def,   lowered: .spDef),
    Nature(id: "modest",  name: "Modest",  boosted: .spAtk, lowered: .atk),
    Nature(id: "mild",    name: "Mild",    boosted: .spAtk, lowered: .def),
    Nature(id: "quiet",   name: "Quiet",   boosted: .spAtk, lowered: .speed),
    Nature(id: "rash",    name: "Rash",    boosted: .spAtk, lowered: .spDef),
    Nature(id: "calm",    name: "Calm",    boosted: .spDef, lowered: .atk),
    Nature(id: "gentle",  name: "Gentle",  boosted: .spDef, lowered: .def),
    Nature(id: "sassy",   name: "Sassy",   boosted: .spDef, lowered: .speed),
    Nature(id: "careful", name: "Careful", boosted: .spDef, lowered: .spAtk),
    Nature(id: "timid",   name: "Timid",   boosted: .speed, lowered: .atk),
    Nature(id: "hasty",   name: "Hasty",   boosted: .speed, lowered: .def),
    Nature(id: "jolly",   name: "Jolly",   boosted: .speed, lowered: .spAtk),
    Nature(id: "naive",   name: "Naive",   boosted: .speed, lowered: .spDef),
]

// MARK: - Saved Spread

@Model
final class SavedSpread {
    var name: String
    var pokemonID: Int?
    var pokemonName: String?
    var abilityName: String?
    var itemRawValue: String?
    var championsMode: Bool
    var natureID: String
    var level: Int
    var evHP: Int; var evAtk: Int; var evDef: Int
    var evSpAtk: Int; var evSpDef: Int; var evSpeed: Int
    var ivHP: Int; var ivAtk: Int; var ivDef: Int
    var ivSpAtk: Int; var ivSpDef: Int; var ivSpeed: Int
    var moveID1: Int?
    var moveID2: Int?
    var moveID3: Int?
    var moveID4: Int?
    var createdAt: Date

    init(name: String, pokemonID: Int? = nil, pokemonName: String? = nil,
         abilityName: String? = nil, itemRawValue: String? = nil,
         championsMode: Bool = false, natureID: String = "adamant", level: Int = 50,
         evHP: Int = 0, evAtk: Int = 0, evDef: Int = 0,
         evSpAtk: Int = 0, evSpDef: Int = 0, evSpeed: Int = 0,
         ivHP: Int = 31, ivAtk: Int = 31, ivDef: Int = 31,
         ivSpAtk: Int = 31, ivSpDef: Int = 31, ivSpeed: Int = 31,
         moveID1: Int? = nil, moveID2: Int? = nil,
         moveID3: Int? = nil, moveID4: Int? = nil) {
        self.name = name
        self.pokemonID = pokemonID
        self.pokemonName = pokemonName
        self.abilityName = abilityName
        self.itemRawValue = itemRawValue
        self.championsMode = championsMode
        self.natureID = natureID
        self.level = level
        self.evHP = evHP; self.evAtk = evAtk; self.evDef = evDef
        self.evSpAtk = evSpAtk; self.evSpDef = evSpDef; self.evSpeed = evSpeed
        self.ivHP = ivHP; self.ivAtk = ivAtk; self.ivDef = ivDef
        self.ivSpAtk = ivSpAtk; self.ivSpDef = ivSpDef; self.ivSpeed = ivSpeed
        self.moveID1 = moveID1; self.moveID2 = moveID2
        self.moveID3 = moveID3; self.moveID4 = moveID4
        self.createdAt = Date()
    }
}

// MARK: - Saved Team

@Model
final class SavedTeam {
    var name: String
    var createdAt: Date

    /// JSON-encoded array of `TeamSlotInfo` (up to 6 slots).
    var slotsJSON: Data

    init(name: String, slots: [TeamSlotInfo] = []) {
        self.name = name
        self.createdAt = Date()
        self.slotsJSON = (try? JSONEncoder().encode(slots)) ?? Data()
    }

    var slots: [TeamSlotInfo] {
        get { (try? JSONDecoder().decode([TeamSlotInfo].self, from: slotsJSON)) ?? [] }
        set { slotsJSON = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    /// Returns the team's slots resolved against the live `SavedSpread` records by
    /// name. Each slot stores a JSON snapshot when added (so the team survives spread
    /// deletion), but display and battle code should call this so subsequent edits to
    /// the underlying spread — new moves, EVs, ability, etc. — propagate automatically.
    /// If a slot's `spreadName` no longer matches any saved spread, the cached
    /// snapshot is returned as a fallback.
    func resolvedSlots(allSpreads: [SavedSpread],
                       allPokemon: [PKMNStats],
                       allMoves: [MoveData]) -> [TeamSlotInfo] {
        slots.map { stored -> TeamSlotInfo in
            guard let live = allSpreads.first(where: { $0.name == stored.spreadName }) else {
                return stored
            }
            let pkmn = allPokemon.first(where: { $0.id == live.pokemonID })
            return TeamSlotInfo.from(spread: live, pokemon: pkmn, moves: allMoves) ?? stored
        }
    }
}

struct TeamSlotInfo: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var spreadName: String
    var pokemonID: Int
    var pokemonName: String
    var type1: String
    var type2: String?
    var abilityName: String?
    var itemRawValue: String?
    var championsMode: Bool = false
    var natureID: String = "adamant"
    var level: Int = 50
    var evHP: Int = 0; var evAtk: Int = 0; var evDef: Int = 0
    var evSpAtk: Int = 0; var evSpDef: Int = 0; var evSpeed: Int = 0
    var moveSlots: [TeamMoveInfo]

    static func from(spread: SavedSpread, pokemon: PKMNStats?, moves: [MoveData]) -> TeamSlotInfo? {
        guard let pokemon else { return nil }
        let moveIDs = [spread.moveID1, spread.moveID2, spread.moveID3, spread.moveID4]
        let resolvedMoves = moveIDs.compactMap { mid -> TeamMoveInfo? in
            guard let mid, let move = moves.first(where: { $0.id == mid }) else { return nil }
            let pokemonTypes = [pokemon.type1] + [pokemon.type2].compactMap { $0 }
            let isAttacking = move.damageClass != "status"
            return TeamMoveInfo(moveID: move.id, moveName: move.name, moveType: move.type,
                                damageClass: move.damageClass, power: move.power,
                                isSTAB: isAttacking && pokemonTypes.contains(move.type))
        }
        return TeamSlotInfo(
            spreadName: spread.name,
            pokemonID: pokemon.id,
            pokemonName: pokemon.name,
            type1: pokemon.type1, type2: pokemon.type2,
            abilityName: spread.abilityName,
            itemRawValue: spread.itemRawValue,
            championsMode: spread.championsMode,
            natureID: spread.natureID,
            level: spread.level,
            evHP: spread.evHP, evAtk: spread.evAtk, evDef: spread.evDef,
            evSpAtk: spread.evSpAtk, evSpDef: spread.evSpDef, evSpeed: spread.evSpeed,
            moveSlots: resolvedMoves
        )
    }
}

struct TeamMoveInfo: Codable, Identifiable, Equatable {
    var id: Int { moveID }
    var moveID: Int
    var moveName: String
    var moveType: String
    var damageClass: String
    var power: Int?
    var isSTAB: Bool
}

// MARK: - EV System

// Main-series scale
let maxEVPerStat = 252
let maxTotalEVs = 510

// Champions scale: 0-32 per stat, where 32 == 252 in the main formula.
// Total cap scales proportionally: floor(510 * 32 / 252) = 64
let championsMaxEVPerStat = 32
let championsMaxTotalEVs = 66

/// Convert a Champions-scale EV (0-32) to the main-series value used in stat formulas.
func championsEVToMain(_ cev: Int) -> Int {
    return cev * 252 / 32
}

// MARK: - Stat Calculation (Gen III+ formula)

func calcHP(base: Int, iv: Int, ev: Int, level: Int) -> Int {
    if base == 1 { return 1 } // Shedinja
    return ((2 * base + iv + ev / 4) * level / 100) + level + 10
}

func calcStat(base: Int, iv: Int, ev: Int, level: Int, natureMod: Double) -> Int {
    let raw = ((2 * base + iv + ev / 4) * level / 100) + 5
    return Int(Double(raw) * natureMod)
}

func statStageMultiplier(stage: Int) -> Double {
    let clamped = max(-6, min(6, stage))
    if clamped >= 0 {
        return Double(2 + clamped) / 2.0
    } else {
        return 2.0 / Double(2 - clamped)
    }
}

// MARK: - Weather

// MARK: - Held Items

enum HeldItem: String, CaseIterable, Identifiable {
    case none = "None"

    // Offensive
    case choiceBand = "Choice Band"
    case choiceSpecs = "Choice Specs"
    case lifeOrb = "Life Orb"
    case expertBelt = "Expert Belt"
    case metronome = "Metronome"

    // Type-boosting plates / gems
    case typeBoost = "Type-Boost (1.2x)"

    // Defensive
    case assaultVest = "Assault Vest"
    case eviolite = "Eviolite"

    // Species-specific
    case lightBall = "Light Ball"
    case thickClub = "Thick Club"

    // Mega Stones — no damage-calc effect, but required to trigger Mega Evolution
    // in the Battle Simulator. Mega Rayquaza uses Dragon Ascent instead of a stone.
    case venusaurite     = "Venusaurite"
    case charizarditeX   = "Charizardite X"
    case charizarditeY   = "Charizardite Y"
    case blastoisinite   = "Blastoisinite"
    case beedrillite     = "Beedrillite"
    case pidgeotite      = "Pidgeotite"
    case alakazite       = "Alakazite"
    case slowbronite     = "Slowbronite"
    case gengarite       = "Gengarite"
    case kangaskhanite   = "Kangaskhanite"
    case pinsirite       = "Pinsirite"
    case gyaradosite     = "Gyaradosite"
    case aerodactylite   = "Aerodactylite"
    case mewtwoniteX     = "Mewtwonite X"
    case mewtwoniteY     = "Mewtwonite Y"
    case ampharosite     = "Ampharosite"
    case steelixite      = "Steelixite"
    case scizorite       = "Scizorite"
    case heracronite     = "Heracronite"
    case houndoominite   = "Houndoominite"
    case tyranitarite    = "Tyranitarite"
    case sceptilite      = "Sceptilite"
    case blazikenite     = "Blazikenite"
    case swampertite     = "Swampertite"
    case gardevoirite    = "Gardevoirite"
    case sablenite       = "Sablenite"
    case mawilite        = "Mawilite"
    case medichamite     = "Medichamite"
    case manectite       = "Manectite"
    case sharpedonite    = "Sharpedonite"
    case cameruptite     = "Cameruptite"
    case altarianite     = "Altarianite"
    case banettite       = "Banettite"
    case absolite        = "Absolite"
    case glalitite       = "Glalitite"
    case salamencite     = "Salamencite"
    case metagrossite    = "Metagrossite"
    case latiasite       = "Latiasite"
    case latiosite       = "Latiosite"
    case garchompite     = "Garchompite"
    case lucarionite     = "Lucarionite"
    case abomasite       = "Abomasite"
    case lopunnite       = "Lopunnite"
    case audinite        = "Audinite"
    case diancite        = "Diancite"

    // Additional Mega Stones (canon Gallade/Aggron + Z-A roster). Stones in this
    // group exist as held-item data so users can save them on team spreads. Forms
    // without entries in `MegaForms.all` won't trigger a Mega Evolution yet — they're
    // present here so the team builder doesn't reject the item.
    case aggronite       = "Aggronite"
    case galladite       = "Galladite"
    case chandelurite    = "Chandelurite"
    case chesnaughtite   = "Chesnaughtite"
    case chimechite      = "Chimechite"
    case clefablite      = "Clefablite"
    case crabominite     = "Crabominite"
    case delphoxite      = "Delphoxite"
    case dragoninite     = "Dragoninite"
    case drampanite      = "Drampanite"
    case emboarite       = "Emboarite"
    case excadrite       = "Excadrite"
    case feraligite      = "Feraligite"
    case floettite       = "Floettite"
    case froslassite     = "Froslassite"
    case glimmoranite    = "Glimmoranite"
    case golurkite       = "Golurkite"
    case greninjite      = "Greninjite"
    case hawluchanite    = "Hawluchanite"
    case meganiumite     = "Meganiumite"
    case meowsticite     = "Meowsticite"
    case scovillainite   = "Scovillainite"
    case skarmorite      = "Skarmorite"
    case starminite      = "Starminite"
    case victreebelite   = "Victreebelite"

    // Type-boosting items (1.2x to moves of the listed type).
    case silkScarf       = "Silk Scarf"        // Normal
    case charcoal        = "Charcoal"          // Fire
    case mysticWater     = "Mystic Water"      // Water
    case magnet          = "Magnet"            // Electric
    case miracleSeed     = "Miracle Seed"      // Grass
    case neverMeltIce    = "Never-Melt Ice"    // Ice
    case blackBelt       = "Black Belt"        // Fighting
    case poisonBarb      = "Poison Barb"       // Poison
    case softSand        = "Soft Sand"         // Ground
    case sharpBeak       = "Sharp Beak"        // Flying
    case twistedSpoon    = "Twisted Spoon"     // Psychic
    case silverPowder    = "Silver Powder"     // Bug
    case hardStone       = "Hard Stone"        // Rock
    case spellTag        = "Spell Tag"         // Ghost
    case dragonFang      = "Dragon Fang"       // Dragon
    case blackGlasses    = "Black Glasses"     // Dark
    case metalCoat       = "Metal Coat"        // Steel
    case fairyFeather    = "Fairy Feather"     // Fairy

    // Other competitive items
    case choiceScarf     = "Choice Scarf"
    case focusSash       = "Focus Sash"
    case focusBand       = "Focus Band"
    case leftovers       = "Leftovers"
    case scopeLens       = "Scope Lens"
    case shellBell       = "Shell Bell"
    case quickClaw       = "Quick Claw"
    case kingsRock       = "King's Rock"
    case brightPowder    = "Bright Powder"
    case mentalHerb      = "Mental Herb"
    case whiteHerb       = "White Herb"
    case rockyHelmet     = "Rocky Helmet"
    case lightClay       = "Light Clay"   // extends screens from 5 → 8 turns

    // Healing & status berries
    case aspearBerry     = "Aspear Berry"
    case cheriBerry      = "Cheri Berry"
    case chestoBerry     = "Chesto Berry"
    case leppaBerry      = "Leppa Berry"
    case lumBerry        = "Lum Berry"
    case oranBerry       = "Oran Berry"
    case pechaBerry      = "Pecha Berry"
    case persimBerry     = "Persim Berry"
    case rawstBerry      = "Rawst Berry"
    case sitrusBerry     = "Sitrus Berry"

    // Type-resist berries (halve a supereffective hit of the matching type, once).
    case occaBerry       = "Occa Berry"        // Fire
    case passhoBerry     = "Passho Berry"      // Water
    case wacanBerry      = "Wacan Berry"       // Electric
    case rindoBerry      = "Rindo Berry"       // Grass
    case yacheBerry      = "Yache Berry"       // Ice
    case chopleBerry     = "Chople Berry"      // Fighting
    case kebiaBerry      = "Kebia Berry"       // Poison
    case shucaBerry      = "Shuca Berry"       // Ground
    case cobaBerry       = "Coba Berry"        // Flying
    case payapaBerry     = "Payapa Berry"      // Psychic
    case tangaBerry      = "Tanga Berry"       // Bug
    case chartiBerry     = "Charti Berry"      // Rock
    case kasibBerry      = "Kasib Berry"       // Ghost
    case habanBerry      = "Haban Berry"       // Dragon
    case colburBerry     = "Colbur Berry"      // Dark
    case babiriBerry     = "Babiri Berry"      // Steel
    case roseliBerry     = "Roseli Berry"      // Fairy
    case chilanBerry     = "Chilan Berry"      // Normal (triggers regardless of effectiveness)

    var id: String { rawValue }

    /// True for any item that exists as a Mega Stone in `MegaForms.all`. Used by
    /// Knock Off (can't remove a Mega Stone) and similar item-removal effects.
    var isMegaStone: Bool {
        MegaForms.all.contains { $0.stone == self }
    }

    /// True for any held item whose display name ends in "Berry" (Oran, Sitrus, Lum,
    /// Occa, ...). Used by Harvest to know which consumed items can be regrown.
    var isBerry: Bool {
        rawValue.hasSuffix("Berry")
    }
}

/// Maps a damage-affecting held item to the type it boosts. Used by the damage calc
/// to apply 1.2x to moves of that type without bloating the main switch statement.
let typeBoostingItemMap: [HeldItem: String] = [
    .silkScarf: "Normal", .charcoal: "Fire", .mysticWater: "Water",
    .magnet: "Electric", .miracleSeed: "Grass", .neverMeltIce: "Ice",
    .blackBelt: "Fighting", .poisonBarb: "Poison", .softSand: "Ground",
    .sharpBeak: "Flying", .twistedSpoon: "Psychic", .silverPowder: "Bug",
    .hardStone: "Rock", .spellTag: "Ghost", .dragonFang: "Dragon",
    .blackGlasses: "Dark", .metalCoat: "Steel", .fairyFeather: "Fairy",
]

/// Maps a type-resist berry to the move type it resists. Triggers in the damage calc
/// (halves damage) and is consumed by the engine after the hit.
let typeResistBerryMap: [HeldItem: String] = [
    .occaBerry: "Fire", .passhoBerry: "Water", .wacanBerry: "Electric",
    .rindoBerry: "Grass", .yacheBerry: "Ice", .chopleBerry: "Fighting",
    .kebiaBerry: "Poison", .shucaBerry: "Ground", .cobaBerry: "Flying",
    .payapaBerry: "Psychic", .tangaBerry: "Bug", .chartiBerry: "Rock",
    .kasibBerry: "Ghost", .habanBerry: "Dragon", .colburBerry: "Dark",
    .babiriBerry: "Steel", .roseliBerry: "Fairy",
]

struct ItemModResult {
    var atkMultiplier: Double = 1.0
    var spAtkMultiplier: Double = 1.0
    var defMultiplier: Double = 1.0
    var spDefMultiplier: Double = 1.0
    var damageMult: Double = 1.0
}

func computeItemModifiers(
    attackerItem: HeldItem,
    defenderItem: HeldItem,
    isPhysical: Bool,
    typeEffectiveness: Double,
    moveType: String
) -> ItemModResult {
    var r = ItemModResult()

    // Attacker items
    switch attackerItem {
    case .choiceBand:
        if isPhysical { r.atkMultiplier = 1.5 }
    case .choiceSpecs:
        if !isPhysical { r.spAtkMultiplier = 1.5 }
    case .lifeOrb:
        r.damageMult = 5324.0 / 4096.0 // ~1.3, exact game value
    case .expertBelt:
        if typeEffectiveness > 1.0 { r.damageMult = 1.2 }
    case .metronome:
        break // user adjusts via misc multiplier
    case .typeBoost:
        r.damageMult = 1.2
    case .lightBall:
        r.atkMultiplier = 2.0; r.spAtkMultiplier = 2.0
    case .thickClub:
        if isPhysical { r.atkMultiplier = 2.0 }
    default:
        break
    }

    // Attacker: type-specific 1.2x boosters (Charcoal, Magnet, Silk Scarf, ...)
    if let boostedType = typeBoostingItemMap[attackerItem], boostedType == moveType {
        r.damageMult *= 1.2
    }

    // Defender items
    switch defenderItem {
    case .assaultVest:
        r.spDefMultiplier = 1.5
    case .eviolite:
        r.defMultiplier = 1.5; r.spDefMultiplier = 1.5
    default:
        break
    }

    // Defender: type-resist berries (halve a supereffective hit of that type).
    // Chilan Berry is special — halves any Normal-type hit regardless of effectiveness.
    if let resistedType = typeResistBerryMap[defenderItem],
       resistedType == moveType,
       typeEffectiveness > 1.0 {
        r.damageMult *= 0.5
    }
    if defenderItem == .chilanBerry && moveType == "Normal" {
        r.damageMult *= 0.5
    }

    return r
}

// MARK: - Weather

enum WeatherCondition: String, CaseIterable, Identifiable {
    case none = "None"
    case sun = "Sun"
    case rain = "Rain"
    case sand = "Sand"
    case snow = "Snow"

    var id: String { rawValue }

    /// Multiplier applied to the move's damage based on its type.
    func moveDamageMultiplier(moveType: String) -> Double {
        switch self {
        case .sun:
            if moveType == "Fire"  { return 1.5 }
            if moveType == "Water" { return 0.5 }
        case .rain:
            if moveType == "Water" { return 1.5 }
            if moveType == "Fire"  { return 0.5 }
        default:
            break
        }
        return 1.0
    }

    /// Sandstorm: Rock types get 1.5x SpDef.
    func sandSpDefMultiplier(defenderTypes: [String]) -> Double {
        if self == .sand && defenderTypes.contains("Rock") { return 1.5 }
        return 1.0
    }

    /// Snow: Ice types get 1.5x Def.
    func snowDefMultiplier(defenderTypes: [String]) -> Double {
        if self == .snow && defenderTypes.contains("Ice") { return 1.5 }
        return 1.0
    }
}

// MARK: - Terrain

enum TerrainCondition: String, CaseIterable, Identifiable {
    case none = "None"
    case electric = "Electric"
    case grassy = "Grassy"
    case misty = "Misty"
    case psychic = "Psychic"

    var id: String { rawValue }

    /// Multiplier applied to the move's damage based on its type.
    func moveDamageMultiplier(moveType: String) -> Double {
        switch self {
        case .electric:
            if moveType == "Electric" { return 1.3 }
        case .grassy:
            if moveType == "Grass" { return 1.3 }
        case .misty:
            if moveType == "Dragon" { return 0.5 }
        case .psychic:
            if moveType == "Psychic" { return 1.3 }
        case .none:
            break
        }
        return 1.0
    }
}

// MARK: - Ability Damage Modifiers

/// All competitively relevant abilities that modify damage calculation.
enum DamageAbility: String, CaseIterable, Identifiable {
    // Attacker — stat / power multipliers
    case adaptability = "adaptability"
    case aerilate = "aerilate"
    case analytic = "analytic"
    case blaze = "blaze"
    case darkAura = "dark-aura"
    case dragonsMaw = "dragons-maw"
    case fairyAura = "fairy-aura"
    case galvanize = "galvanize"
    case gorillaTactics = "gorilla-tactics"
    case hugePower = "huge-power"
    case hustle = "hustle"
    case ironFist = "iron-fist"
    case megaLauncher = "mega-launcher"
    case normalize = "normalize"
    case overgrow = "overgrow"
    case pixilate = "pixilate"
    case protean = "protean"
    case libero = "libero"
    case purePower = "pure-power"
    case punkRock = "punk-rock"
    case reckless = "reckless"
    case refrigerate = "refrigerate"
    case sandForce = "sand-force"
    case sheerForce = "sheer-force"
    case sniperAbility = "sniper"
    case solarPower = "solar-power"
    case stakeout = "stakeout"
    case steelworker = "steelworker"
    case strongJaw = "strong-jaw"
    case supremeOverlord = "supreme-overlord"
    case swarm = "swarm"
    case technician = "technician"
    case tintedLens = "tinted-lens"
    case torrent = "torrent"
    case toughClaws = "tough-claws"
    case transistor = "transistor"
    case waterBubble = "water-bubble"
    // Defender — damage reduction / immunities
    case drySkin = "dry-skin"
    case filter = "filter"
    case flashFire = "flash-fire"
    case fluffy = "fluffy"
    case furCoat = "fur-coat"
    case heatproof = "heatproof"
    case iceScales = "ice-scales"
    case levitate = "levitate"
    case lightningRod = "lightning-rod"
    case marvelScale = "marvel-scale"
    case motorDrive = "motor-drive"
    case multiscale = "multiscale"
    case prismArmor = "prism-armor"
    case punkRockDefense = "punk-rock-def" // same ability, defender side
    case sapSipper = "sap-sipper"
    case shadowShield = "shadow-shield"
    case solidRock = "solid-rock"
    case stormDrain = "storm-drain"
    case thickFat = "thick-fat"
    case voltAbsorb = "volt-absorb"
    case waterAbsorb = "water-absorb"
    case waterBubbleDefense = "water-bubble-def" // same ability, defender side
    case wonderGuard = "wonder-guard"

    // Gen IX+ attacker abilities
    case scrappy = "scrappy"
    case mindsEye = "minds-eye"
    case guts = "guts"
    case toxicBoost = "toxic-boost"
    case flareBoost = "flare-boost"
    case defeatist = "defeatist"
    case slowStart = "slow-start"
    case rockyPayload = "rocky-payload"
    case sharpness = "sharpness"
    case neuroforce = "neuroforce"
    case orichalcumPulse = "orichalcum-pulse"
    case hadronEngine = "hadron-engine"
    case steelySpirit = "steely-spirit"
    case battery = "battery"
    case powerSpot = "power-spot"
    case parentalBond = "parental-bond"
    case swordOfRuin = "sword-of-ruin"
    case beadsOfRuin = "beads-of-ruin"

    // Gen IX+ defender abilities
    case purifyingSalt = "purifying-salt"
    case wellBakedBody = "well-baked-body"
    case earthEater = "earth-eater"
    case teraShell = "tera-shell"
    case tabletsOfRuin = "tablets-of-ruin"
    case vesselOfRuin = "vessel-of-ruin"
    case friendGuard = "friend-guard"

    var id: String { rawValue }

    var displayName: String {
        rawValue.split(separator: "-").map { $0.capitalized }.joined(separator: " ")
    }
}

struct AbilityModResult {
    var atkMultiplier: Double = 1.0
    var defMultiplier: Double = 1.0
    var powerMultiplier: Double = 1.0
    var stabOverride: Double?       // e.g. Adaptability makes STAB 2.0
    var critMultiplierOverride: Double?  // Sniper makes crit 2.25x
    var typeEffOverride: Double?    // Immunities
    var finalMultiplier: Double = 1.0
}

func computeAbilityModifiers(
    attackerAbility: String?,
    defenderAbility: String?,
    moveType: String,
    movePower: Int,
    isPhysical: Bool,
    isContact: Bool,
    isSTAB: Bool,
    typeEffectiveness: Double,
    weather: WeatherCondition,
    attackerAtFullHP: Bool,
    defenderAtFullHP: Bool,
    defenderTypes: [String] = [],
    terrain: TerrainCondition = .none,
    isSpread: Bool = false,
    moldBreaker: Bool = false
) -> AbilityModResult {
    var r = AbilityModResult()
    let atk = attackerAbility ?? ""
    // Mold Breaker suppresses the defender's ability for ALL damage-calc
    // purposes — type immunities (Levitate, Volt Absorb, …) and damage
    // reducers (Multiscale, Thick Fat, …) both no-op when the attacker has it.
    let def = moldBreaker ? "" : (defenderAbility ?? "")

    // --- Attacker abilities ---

    switch atk {
    case "adaptability":
        if isSTAB { r.stabOverride = 2.0 }

    case "protean", "libero":
        // Grants STAB on every move (type changes to match move)
        if !isSTAB { r.stabOverride = 1.5 }

    case "huge-power", "pure-power":
        if isPhysical { r.atkMultiplier *= 2.0 }

    case "hustle":
        if isPhysical { r.atkMultiplier *= 1.5 }

    case "gorilla-tactics":
        if isPhysical { r.atkMultiplier *= 1.5 }

    case "solar-power":
        if weather == .sun && !isPhysical { r.atkMultiplier *= 1.5 }

    case "water-bubble":
        // 2x Water move power + halves incoming Fire damage (defender handled below)
        if moveType == "Water" { r.powerMultiplier *= 2.0 }

    case "transistor":
        if moveType == "Electric" { r.powerMultiplier *= 1.3 }

    case "dragons-maw":
        if moveType == "Dragon" { r.powerMultiplier *= 1.5 }

    case "steelworker":
        if moveType == "Steel" { r.powerMultiplier *= 1.5 }

    case "dark-aura":
        if moveType == "Dark" { r.powerMultiplier *= 1.33 }

    case "fairy-aura":
        if moveType == "Fairy" { r.powerMultiplier *= 1.33 }

    case "blaze":
        if moveType == "Fire" && !attackerAtFullHP { r.powerMultiplier *= 1.5 }

    case "torrent":
        if moveType == "Water" && !attackerAtFullHP { r.powerMultiplier *= 1.5 }

    case "overgrow":
        if moveType == "Grass" && !attackerAtFullHP { r.powerMultiplier *= 1.5 }

    case "swarm":
        if moveType == "Bug" && !attackerAtFullHP { r.powerMultiplier *= 1.5 }

    case "technician":
        if movePower <= 60 { r.powerMultiplier *= 1.5 }

    case "tough-claws":
        if isContact { r.powerMultiplier *= 1.3 }

    case "iron-fist":
        r.powerMultiplier *= 1.2 // applies to punching moves; simplified

    case "strong-jaw":
        r.powerMultiplier *= 1.5 // applies to biting moves; simplified

    case "mega-launcher":
        r.powerMultiplier *= 1.5 // applies to pulse/aura moves; simplified

    case "punk-rock":
        r.powerMultiplier *= 1.3 // applies to sound moves; simplified

    case "reckless":
        r.powerMultiplier *= 1.2 // applies to recoil moves; simplified

    case "sheer-force":
        r.powerMultiplier *= 1.3 // applies to moves with secondary effects; simplified

    case "sand-force":
        // 1.3x to Rock/Ground/Steel in sand
        if weather == .sand && (moveType == "Rock" || moveType == "Ground" || moveType == "Steel") {
            r.powerMultiplier *= 1.3
        }

    case "analytic":
        r.powerMultiplier *= 1.3 // if moving last; user toggled

    case "stakeout":
        r.powerMultiplier *= 2.0 // if target switched in; simplified

    case "supreme-overlord":
        r.powerMultiplier *= 1.1 // 1.1x per fainted ally, simplified to 1 fainted

    case "tinted-lens":
        // Doubles damage of "not very effective" moves
        if typeEffectiveness < 1.0 && typeEffectiveness > 0 {
            r.finalMultiplier *= 2.0
        }

    case "sniper":
        r.critMultiplierOverride = 2.25

    case "normalize":
        // All moves become Normal type; 1.2x power boost (Gen VII+)
        r.powerMultiplier *= 1.2

    case "aerilate":
        if moveType == "Normal" { r.powerMultiplier *= 1.2 }
    case "pixilate":
        if moveType == "Normal" { r.powerMultiplier *= 1.2 }
    case "refrigerate":
        if moveType == "Normal" { r.powerMultiplier *= 1.2 }
    case "galvanize":
        if moveType == "Normal" { r.powerMultiplier *= 1.2 }

    case "scrappy", "minds-eye":
        // Normal and Fighting moves can hit Ghost types
        if (moveType == "Normal" || moveType == "Fighting") && typeEffectiveness == 0 {
            var recalc = 1.0
            let chart = typeEffectivenessChart[moveType] ?? [:]
            for dt in defenderTypes {
                if dt == "Ghost" { continue }
                recalc *= chart[dt] ?? 1.0
            }
            r.typeEffOverride = recalc
        }

    case "guts":
        if isPhysical { r.atkMultiplier *= 1.5 }

    case "toxic-boost":
        if isPhysical { r.atkMultiplier *= 1.5 }

    case "flare-boost":
        if !isPhysical { r.atkMultiplier *= 1.5 }

    case "defeatist":
        if !attackerAtFullHP { r.atkMultiplier *= 0.5 }

    case "slow-start":
        if isPhysical { r.atkMultiplier *= 0.5 }

    case "rocky-payload":
        if moveType == "Rock" { r.powerMultiplier *= 1.5 }

    case "sharpness":
        r.powerMultiplier *= 1.5 // applies to slicing moves; simplified

    case "neuroforce":
        if typeEffectiveness > 1.0 { r.finalMultiplier *= 1.25 }

    case "orichalcum-pulse":
        if weather == .sun && isPhysical { r.atkMultiplier *= (4.0 / 3.0) }

    case "hadron-engine":
        if !isPhysical && terrain == .electric { r.atkMultiplier *= (4.0 / 3.0) }

    case "steely-spirit":
        if moveType == "Steel" { r.powerMultiplier *= 1.5 }

    case "battery":
        if !isPhysical { r.finalMultiplier *= 1.3 }

    case "power-spot":
        r.finalMultiplier *= 1.3

    case "parental-bond":
        // Parental Bond does not activate on spread (multi-target) moves in doubles.
        if !isSpread { r.powerMultiplier *= 1.25 }

    case "sword-of-ruin":
        if isPhysical { r.defMultiplier *= 0.75 }

    case "beads-of-ruin":
        if !isPhysical { r.defMultiplier *= 0.75 }

    default: break
    }

    // --- Defender abilities ---

    switch def {
    case "multiscale", "shadow-shield":
        if defenderAtFullHP { r.finalMultiplier *= 0.5 }

    case "marvel-scale":
        // 1.5x Def when statused; simplified as always active when selected
        if isPhysical { r.defMultiplier *= 1.5 }

    case "thick-fat":
        if moveType == "Fire" || moveType == "Ice" { r.atkMultiplier *= 0.5 }

    case "ice-scales":
        if !isPhysical { r.defMultiplier *= 2.0 }

    case "fur-coat":
        if isPhysical { r.defMultiplier *= 2.0 }

    case "punk-rock":
        // Defender side: halves incoming sound move damage; simplified
        r.finalMultiplier *= 0.5

    case "water-bubble":
        // Defender side: halves incoming Fire damage
        if moveType == "Fire" { r.finalMultiplier *= 0.5 }

    case "fluffy":
        if isContact { r.finalMultiplier *= 0.5 }
        if moveType == "Fire" { r.finalMultiplier *= 2.0 }

    case "filter", "solid-rock", "prism-armor":
        if typeEffectiveness > 1.0 { r.finalMultiplier *= 0.75 }

    case "heatproof":
        if moveType == "Fire" { r.finalMultiplier *= 0.5 }

    case "dry-skin":
        if moveType == "Water" { r.typeEffOverride = 0.0 }
        if moveType == "Fire"  { r.finalMultiplier *= 1.25 }

    case "levitate":
        if moveType == "Ground" { r.typeEffOverride = 0.0 }

    case "flash-fire":
        if moveType == "Fire" { r.typeEffOverride = 0.0 }

    case "water-absorb", "storm-drain":
        if moveType == "Water" { r.typeEffOverride = 0.0 }

    case "volt-absorb", "lightning-rod", "motor-drive":
        if moveType == "Electric" { r.typeEffOverride = 0.0 }

    case "sap-sipper":
        if moveType == "Grass" { r.typeEffOverride = 0.0 }

    case "wonder-guard":
        if typeEffectiveness <= 1.0 { r.typeEffOverride = 0.0 }

    case "purifying-salt":
        if moveType == "Ghost" { r.finalMultiplier *= 0.5 }

    case "well-baked-body":
        if moveType == "Fire" { r.typeEffOverride = 0.0 }

    case "earth-eater":
        if moveType == "Ground" { r.typeEffOverride = 0.0 }

    case "tera-shell":
        if defenderAtFullHP && typeEffectiveness > 1.0 { r.typeEffOverride = 0.5 }

    case "tablets-of-ruin":
        if isPhysical { r.atkMultiplier *= 0.75 }

    case "vessel-of-ruin":
        if !isPhysical { r.atkMultiplier *= 0.75 }

    case "friend-guard":
        r.finalMultiplier *= 0.75

    default: break
    }

    return r
}
