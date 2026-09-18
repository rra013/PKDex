//
//  ShowdownCalc.swift
//  PKDex
//
//  Foundation of a faithful Swift port of Smogon's @smogon/calc damage
//  calculator (https://github.com/smogon/damage-calc, MIT License).
//  Ported from calc/src/{util,stats,field,state}.ts. File/function names are
//  kept close to upstream so this stays diffable against future updates.
//
//  This file: IDs, stat tables, natures, the Field/Side model, and the stat
//  formula — including the Champions "gen 0" stat-point model
//  (`calcStatChampions`), which is how @smogon/calc encodes the 0–32 SP system.
//
//  SCOPE: this is a FULL port — mechanics Champions doesn't use (Z-Moves,
//  Dynamax/Max, Tera, older gens) are ported but left present-but-unwired.
//  See PKDex/ShowdownPort-NOTES.md for the wiring decision.
//
//  Copyright the Smogon damage-calc contributors, MIT License. See
//  tools/vendor/damage-calc/LICENSE for the full text; a NOTICE is bundled
//  under Showdown-LICENSE.
//

import Foundation

// MARK: - IDs (util.ts `toID`)

typealias ShowdownID = String

/// Lowercases and strips to `[a-z0-9]`, matching upstream `toID`.
nonisolated func toID(_ text: String) -> ShowdownID {
    let lcase = text.lowercased()
    if lcase == "flabébé" { return "flabebe" }
    var out = ""
    out.reserveCapacity(lcase.count)
    for ch in lcase where ch.isASCII && (ch.isLetter || ch.isNumber) { out.append(ch) }
    return out
}

// MARK: - Stats

nonisolated enum ShowdownStat: String, CaseIterable, Hashable {
    case hp, atk, def, spa, spd, spe
}

/// `StatsTable` — six named integer stats with `StatID` subscripting.
nonisolated struct ShowdownStats: Hashable, Codable {
    var hp = 0, atk = 0, def = 0, spa = 0, spd = 0, spe = 0

    subscript(_ s: ShowdownStat) -> Int {
        get {
            switch s {
            case .hp: return hp
            case .atk: return atk
            case .def: return def
            case .spa: return spa
            case .spd: return spd
            case .spe: return spe
            }
        }
        set {
            switch s {
            case .hp: hp = newValue
            case .atk: atk = newValue
            case .def: def = newValue
            case .spa: spa = newValue
            case .spd: spd = newValue
            case .spe: spe = newValue
            }
        }
    }
}

// MARK: - Natures

/// Minimal nature model: which stat is boosted (+10%) / reduced (−10%).
/// Neutral natures have both nil. Mirrors what `gen.natures.get()` provides to
/// the stat formula (only `plus`/`minus` are read there).
struct ShowdownNature {
    let name: String
    let plus: ShowdownStat?
    let minus: ShowdownStat?
}

enum ShowdownNatures {
    /// name (lowercased id) -> nature. Neutral natures map to (nil, nil).
    static let byID: [ShowdownID: ShowdownNature] = {
        // (name, plus, minus) — the 25 mainline natures. Neutrals omitted from
        // the plus/minus pairs below and added as (nil, nil).
        let pairs: [(String, ShowdownStat, ShowdownStat)] = [
            ("Lonely", .atk, .def), ("Adamant", .atk, .spa), ("Naughty", .atk, .spd), ("Brave", .atk, .spe),
            ("Bold", .def, .atk), ("Impish", .def, .spa), ("Lax", .def, .spd), ("Relaxed", .def, .spe),
            ("Modest", .spa, .atk), ("Mild", .spa, .def), ("Rash", .spa, .spd), ("Quiet", .spa, .spe),
            ("Calm", .spd, .atk), ("Gentle", .spd, .def), ("Careful", .spd, .spa), ("Sassy", .spd, .spe),
            ("Timid", .spe, .atk), ("Hasty", .spe, .def), ("Jolly", .spe, .spa), ("Naive", .spe, .spd),
        ]
        let neutrals = ["Hardy", "Docile", "Bashful", "Quirky", "Serious"]
        var out: [ShowdownID: ShowdownNature] = [:]
        for (n, p, m) in pairs { out[toID(n)] = ShowdownNature(name: n, plus: p, minus: m) }
        for n in neutrals { out[toID(n)] = ShowdownNature(name: n, plus: nil, minus: nil) }
        return out
    }()

    static func get(_ name: String?) -> ShowdownNature? {
        guard let name else { return nil }
        return byID[toID(name)]
    }
}

// MARK: - Stat formula (stats.ts)

enum ShowdownStatsCalc {
    /// `gen` here is the upstream generation number: 0 == Champions, 3–9 use the
    /// ADV+ formula, 1–2 use RBY. We only need Champions (0) and modern (9) for
    /// this app, but the dispatch is kept faithful.
    static func calcStat(gen: Int, stat: ShowdownStat, base: Int, iv: Int, ev: Int,
                         level: Int, nature: String?) -> Int {
        precondition(gen >= 0 && gen <= 9, "Invalid generation \(gen)")
        if gen == 0 { return calcStatChampions(stat: stat, base: base, sp: ev, nature: nature) }
        if gen < 3 { return calcStatRBY(stat: stat, base: base, iv: iv, ev: ev, level: level) }
        return calcStatADV(stat: stat, base: base, iv: iv, ev: ev, level: level, nature: nature)
    }

    /// Champions 0–32 stat-point model (`ev` carries the stat-point value).
    static func calcStatChampions(stat: ShowdownStat, base: Int, sp: Int, nature: String?) -> Int {
        if stat == .hp {
            return base == 1 ? base : base + sp + 75
        }
        let nat = ShowdownNatures.get(nature)
        let n = natureMultiplier(stat: stat, plus: nat?.plus, minus: nat?.minus)
        return Int(floor(n * Double(base + sp + 20)))
    }

    static func calcStatADV(stat: ShowdownStat, base: Int, iv: Int, ev: Int,
                            level: Int, nature: String?) -> Int {
        if stat == .hp {
            return base == 1
                ? base
                : Int(floor(Double((base * 2 + iv + ev / 4) * level) / 100.0)) + level + 10
        }
        let nat = ShowdownNatures.get(nature)
        let n = natureMultiplier(stat: stat, plus: nat?.plus, minus: nat?.minus)
        return Int(floor(Double(Int(floor(Double((base * 2 + iv + ev / 4) * level) / 100.0)) + 5) * n))
    }

    static func calcStatRBY(stat: ShowdownStat, base: Int, iv: Int, ev: Int, level: Int) -> Int {
        let dv = iv / 2
        let statexp = (ev - 1) * (ev - 1) + 1
        let e = Int(floor((Double(statexp - 1).squareRoot() + 1) / 4))
        if stat == .hp {
            return Int(floor(Double(((base + dv) * 2 + e) * level) / 100.0)) + level + 10
        }
        return Int(floor(Double(((base + dv) * 2 + e) * level) / 100.0)) + 5
    }

    private static func natureMultiplier(stat: ShowdownStat, plus: ShowdownStat?, minus: ShowdownStat?) -> Double {
        if plus == stat && minus == stat { return 1 }
        if plus == stat { return 1.1 }
        if minus == stat { return 0.9 }
        return 1
    }
}

// MARK: - Field (field.ts)

enum ShowdownGameType: String { case singles = "Singles", doubles = "Doubles" }
enum ShowdownWeather: String { case sun = "Sun", rain = "Rain", sand = "Sand", snow = "Snow", hail = "Hail", harshSunshine = "Harsh Sunshine", heavyRain = "Heavy Rain", strongWinds = "Strong Winds" }
enum ShowdownTerrain: String { case electric = "Electric", grassy = "Grassy", psychic = "Psychic", misty = "Misty" }

/// Reference type: the damage pipeline mutates sides in place (screens, etc.).
final class ShowdownSide {
    var spikes = 0
    var steelsurge = false
    var vinelash = false
    var wildfire = false
    var cannonade = false
    var volcalith = false
    var isSR = false
    var isReflect = false
    var isLightScreen = false
    var isProtected = false
    var isSeeded = false
    var isForesight = false
    var isTailwind = false
    var isHelpingHand = false
    var isFlowerGift = false
    var isFriendGuard = false
    var isAuroraVeil = false
    var isBattery = false
    var isPowerSpot = false
    var isSteelySpirit = false
    var isSwitching: String? = nil
    var isPowerTrick = false
    var isCharge = false

    func clone() -> ShowdownSide {
        let s = ShowdownSide()
        s.spikes = spikes; s.steelsurge = steelsurge; s.vinelash = vinelash
        s.wildfire = wildfire; s.cannonade = cannonade; s.volcalith = volcalith
        s.isSR = isSR; s.isReflect = isReflect; s.isLightScreen = isLightScreen
        s.isProtected = isProtected; s.isSeeded = isSeeded; s.isForesight = isForesight
        s.isTailwind = isTailwind; s.isHelpingHand = isHelpingHand; s.isFlowerGift = isFlowerGift
        s.isFriendGuard = isFriendGuard; s.isAuroraVeil = isAuroraVeil; s.isBattery = isBattery
        s.isPowerSpot = isPowerSpot; s.isSteelySpirit = isSteelySpirit; s.isSwitching = isSwitching
        s.isPowerTrick = isPowerTrick; s.isCharge = isCharge
        return s
    }
}

/// Reference type: `checkAirLock`, `checkSeedBoost`, etc. mutate the field.
final class ShowdownField {
    var gameType: ShowdownGameType = .singles
    var weather: ShowdownWeather? = nil
    var terrain: ShowdownTerrain? = nil
    var isMagicRoom = false
    var isWonderRoom = false
    var isGravity = false
    var isAuraBreak = false
    var isFairyAura = false
    var isDarkAura = false
    var isBeadsOfRuin = false
    var isSwordOfRuin = false
    var isTabletsOfRuin = false
    var isVesselOfRuin = false
    var attackerSide = ShowdownSide()
    var defenderSide = ShowdownSide()

    func hasWeather(_ weathers: ShowdownWeather...) -> Bool {
        guard let weather else { return false }
        return weathers.contains(weather)
    }

    func hasTerrain(_ terrains: ShowdownTerrain...) -> Bool {
        guard let terrain else { return false }
        return terrains.contains(terrain)
    }

    func clone() -> ShowdownField {
        let f = ShowdownField()
        f.gameType = gameType; f.weather = weather; f.terrain = terrain
        f.isMagicRoom = isMagicRoom; f.isWonderRoom = isWonderRoom; f.isGravity = isGravity
        f.isAuraBreak = isAuraBreak; f.isFairyAura = isFairyAura; f.isDarkAura = isDarkAura
        f.isBeadsOfRuin = isBeadsOfRuin; f.isSwordOfRuin = isSwordOfRuin
        f.isTabletsOfRuin = isTabletsOfRuin; f.isVesselOfRuin = isVesselOfRuin
        f.attackerSide = attackerSide.clone(); f.defenderSide = defenderSide.clone()
        return f
    }
}
