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

    init(id: Int, name: String, type: String, damageClass: String,
         power: Int? = nil, accuracy: Int? = nil, pp: Int = 0, priority: Int = 0,
         minHits: Int? = nil, maxHits: Int? = nil,
         drain: Int = 0, healing: Int = 0, critRate: Int = 0, makesContact: Bool = false) {
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

// MARK: - EV System

// Main-series scale
let maxEVPerStat = 252
let maxTotalEVs = 510

// Champions scale: 0-32 per stat, where 32 == 252 in the main formula.
// Total cap: 66
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

// MARK: - Ability Damage Modifiers

/// All competitively relevant abilities that modify damage calculation.
enum DamageAbility: String, CaseIterable, Identifiable {
    // Attacker
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
    case overgrow = "overgrow"
    case pixilate = "pixilate"
    case purePower = "pure-power"
    case reckless = "reckless"
    case refrigerate = "refrigerate"
    case sheerForce = "sheer-force"
    case sniperAbility = "sniper"
    case solarPower = "solar-power"
    case stakeout = "stakeout"
    case steelworker = "steelworker"
    case strongJaw = "strong-jaw"
    case swarm = "swarm"
    case technician = "technician"
    case torrent = "torrent"
    case toughClaws = "tough-claws"
    case transistor = "transistor"
    // Defender
    case drySkin = "dry-skin"
    case filter = "filter"
    case flashFire = "flash-fire"
    case fluffy = "fluffy"
    case furCoat = "fur-coat"
    case heatproof = "heatproof"
    case iceScales = "ice-scales"
    case levitate = "levitate"
    case lightningRod = "lightning-rod"
    case motorDrive = "motor-drive"
    case multiscale = "multiscale"
    case prismArmor = "prism-armor"
    case sapSipper = "sap-sipper"
    case shadowShield = "shadow-shield"
    case solidRock = "solid-rock"
    case stormDrain = "storm-drain"
    case thickFat = "thick-fat"
    case voltAbsorb = "volt-absorb"
    case waterAbsorb = "water-absorb"
    case wonderGuard = "wonder-guard"

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
    defenderAtFullHP: Bool
) -> AbilityModResult {
    var r = AbilityModResult()
    let atk = attackerAbility ?? ""
    let def = defenderAbility ?? ""

    // --- Attacker abilities ---

    switch atk {
    case "adaptability":
        if isSTAB { r.stabOverride = 2.0 }

    case "huge-power", "pure-power":
        if isPhysical { r.atkMultiplier *= 2.0 }

    case "hustle":
        if isPhysical { r.atkMultiplier *= 1.5 }

    case "gorilla-tactics":
        if isPhysical { r.atkMultiplier *= 1.5 }

    case "solar-power":
        if weather == .sun && !isPhysical { r.atkMultiplier *= 1.5 }

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
        if moveType == "Fire" && attackerAtFullHP == false { r.powerMultiplier *= 1.5 }

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

    case "reckless":
        r.powerMultiplier *= 1.2 // applies to recoil moves; simplified

    case "sheer-force":
        r.powerMultiplier *= 1.3 // applies to moves with secondary effects; simplified

    case "analytic":
        r.powerMultiplier *= 1.3 // if moving last; user toggled

    case "stakeout":
        r.powerMultiplier *= 2.0 // if target switched in; simplified

    case "sniper":
        r.critMultiplierOverride = 2.25

    case "aerilate":
        if moveType == "Normal" { r.powerMultiplier *= 1.2 }
    case "pixilate":
        if moveType == "Normal" { r.powerMultiplier *= 1.2 }
    case "refrigerate":
        if moveType == "Normal" { r.powerMultiplier *= 1.2 }
    case "galvanize":
        if moveType == "Normal" { r.powerMultiplier *= 1.2 }

    default: break
    }

    // --- Defender abilities ---

    switch def {
    case "multiscale", "shadow-shield":
        if defenderAtFullHP { r.finalMultiplier *= 0.5 }

    case "thick-fat":
        if moveType == "Fire" || moveType == "Ice" { r.atkMultiplier *= 0.5 }

    case "ice-scales":
        if !isPhysical { r.defMultiplier *= 2.0 }

    case "fur-coat":
        if isPhysical { r.defMultiplier *= 2.0 }

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

    default: break
    }

    return r
}
