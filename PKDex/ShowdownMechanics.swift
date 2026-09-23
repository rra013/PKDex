//
//  ShowdownMechanics.swift
//  PKDex
//
//  Port of @smogon/calc's mechanics/util.ts helpers + mechanics/champions.ts
//  (the Champions damage pipeline). MIT — see PKDex/ShowdownPort-NOTES.md.
//  The human-readable `RawDesc` is intentionally not ported (damage-only); the
//  math mirrors upstream line-for-line, incl. modifier order and rounding.
//

import Foundation

// MARK: - Result

/// `result.damage` union: a fixed amount, the 16 damage rolls, or a matrix
/// (multi-hit / Parental Bond `[parent, child]`).
nonisolated enum ShowdownDamageValue {
    case fixed(Int)
    case rolls([Int])
    case matrix([[Int]])
}

nonisolated struct ShowdownResult {
    var damage: ShowdownDamageValue = .fixed(0)
}

// MARK: - Rounding / overflow (util.ts)

/// Game Freak rounds DOWN on .5.
nonisolated func pokeRound(_ num: Double) -> Int {
    num.truncatingRemainder(dividingBy: 1) > 0.5 ? Int(num.rounded(.up)) : Int(num.rounded(.down))
}
nonisolated func OF16(_ n: Int) -> Int { n > 65535 ? n % 65536 : n }
nonisolated func OF32(_ n: Int) -> Int { n > 4294967295 ? n % 4294967296 : n }

// MARK: - Small helpers

private func clampBoost(_ v: Int) -> Int { min(6, max(-6, v)) }

nonisolated func sdIsGrounded(_ p: ShowdownPokemon, _ field: ShowdownField) -> Bool {
    field.isGravity || p.hasItem("Iron Ball") ||
        (!p.hasType(.flying) && !p.hasAbility("Levitate", "Eelevate") && !p.hasItem("Air Balloon"))
}

/// Modern-gen stat boost table (gens 3+; Champions uses this path).
nonisolated func getModifiedStat(_ stat: Int, _ mod: Int) -> Int {
    let table = [[2, 8], [2, 7], [2, 6], [2, 5], [2, 4], [2, 3], [2, 2],
                 [3, 2], [4, 2], [5, 2], [6, 2], [7, 2], [8, 2]]
    var s = OF16(stat * table[6 + mod][0])
    s = Int(floor(Double(s) / Double(table[6 + mod][1])))
    return s
}

nonisolated func chainMods(_ mods: [Int], _ lowerBound: Int, _ upperBound: Int) -> Int {
    var M = 4096
    for mod in mods where mod != 4096 {
        M = (M * mod + 2048) >> 12
    }
    return max(min(M, upperBound), lowerBound)
}

nonisolated func getBaseDamage(_ level: Int, _ basePower: Int, _ attack: Int, _ defense: Int) -> Int {
    Int(floor(
        Double(OF32(
            Int(floor(
                Double(OF32(OF32(Int(floor(Double(2 * level) / 5 + 2)) * basePower) * attack))
                    / Double(defense)
            )) / 50 + 2
        ))
    ))
}

nonisolated func getFinalDamage(_ baseAmount: Int, _ i: Int, _ effectiveness: Double, _ isBurned: Bool,
                    _ stabMod: Int, _ finalMod: Int, _ protect: Bool) -> Int {
    var d = Double(Int(floor(Double(OF32(baseAmount * (85 + i))) / 100)))
    if stabMod != 4096 { d = Double(OF32(Int(d) * stabMod)) / 4096 }
    var damageAmount = Int(floor(Double(OF32(Int(Double(pokeRound(d)) * effectiveness)))))
    // Match TS: floor(OF32(pokeRound(d) * effectiveness))
    damageAmount = Int(floor(Double(OF32(Int(Double(pokeRound(d)) * effectiveness)))))
    if isBurned { damageAmount = damageAmount / 2 }
    if `protect` { damageAmount = pokeRound(Double(OF32(damageAmount * 1024)) / 4096) }
    return OF16(pokeRound(max(1, Double(OF32(damageAmount * finalMod)) / 4096)))
}

nonisolated func countBoosts(_ boosts: ShowdownStats) -> Int {
    var sum = 0
    for stat in [ShowdownStat.atk, .def, .spa, .spd, .spe] where boosts[stat] > 0 { sum += boosts[stat] }
    return sum
}

nonisolated func getWeight(_ p: ShowdownPokemon) -> Double {
    var weightHG = p.weightkg * 10
    let factor = p.hasAbility("Heavy Metal") ? 2.0 : p.hasAbility("Light Metal") ? 0.5 : 1.0
    if factor != 1 { weightHG = max(Double(Int(weightHG * factor)), 1) }
    if p.hasItem("Float Stone") { weightHG = max(Double(Int(weightHG * 0.5)), 1) }
    return weightHG / 10
}

nonisolated func getStabMod(_ p: ShowdownPokemon, _ move: ShowdownMove) -> Int {
    var stabMod = 4096
    if p.hasOriginalType(move.type) {
        stabMod += 2048
    } else if p.hasAbility("Protean", "Libero") && p.teraType == nil {
        stabMod += 2048
    }
    if let tera = p.teraType, tera == move.type, tera != .stellar { stabMod += 2048 }
    if p.hasAbility("Adaptability") && p.hasType(move.type) {
        stabMod += (p.teraType != nil && p.hasOriginalType(p.teraType!)) ? 1024 : 2048
    }
    return stabMod
}

nonisolated func handleFixedDamageMoves(_ attacker: ShowdownPokemon, _ move: ShowdownMove) -> Int {
    if move.named("Seismic Toss", "Night Shade") { return attacker.level }
    if move.named("Dragon Rage") { return 40 }
    if move.named("Sonic Boom") { return 20 }
    return 0
}

nonisolated func getShellSideArmCategory(_ source: ShowdownPokemon, _ target: ShowdownPokemon,
                             _ wonderRoomActive: Bool = false) -> ShowdownCategory {
    var physical = Double(source.stats.atk) / Double(target.stats.def)
    var special = Double(source.stats.spa) / Double(target.stats.spd)
    if wonderRoomActive {
        physical = Double(source.stats.atk) / Double(target.stats.spd)
        special = Double(source.stats.spa) / Double(target.stats.def)
    }
    return physical > special ? .physical : .special
}

nonisolated func getQPBoostedStat(_ p: ShowdownPokemon) -> ShowdownStat {
    if let b = p.boostedStat, b != "auto", let s = ShowdownStat(rawValue: b) { return s }
    var best: ShowdownStat = .atk
    for stat in [ShowdownStat.def, .spa, .spd, .spe] {
        if getModifiedStat(p.rawStats[stat], p.boosts[stat]) > getModifiedStat(p.rawStats[best], p.boosts[best]) {
            best = stat
        }
    }
    return best
}

nonisolated func isQPActive(_ p: ShowdownPokemon, _ field: ShowdownField) -> Bool {
    guard let boosted = p.boostedStat else { return false }
    let weatherSun = field.weather == .sun || field.weather == .harshSunshine
    return (p.hasAbility("Protosynthesis") && (weatherSun || p.hasItem("Booster Energy")))
        || (p.hasAbility("Quark Drive") && (field.terrain == .electric || p.hasItem("Booster Energy")))
        || (boosted != "auto")
}

nonisolated func getMoveEffectiveness(_ gen: ShowdownGeneration, _ move: ShowdownMove, _ type: ShowdownType,
                          isGhostRevealed: Bool, isGravity: Bool, isRingTarget: Bool) -> Double {
    if isGhostRevealed && type == .ghost && move.hasType(.normal, .fighting) { return 1 }
    if isGravity && type == .flying && move.hasType(.ground) { return 1 }
    if move.named("Freeze-Dry") && type == .water { return 2 }
    var eff = gen.effectiveness(move.type, type)
    if eff == 0 && isRingTarget { eff = 1 }
    if move.named("Flying Press") { eff *= gen.effectiveness(.flying, type) }
    return eff
}

// MARK: - Speed / final stats (util.ts)

nonisolated private let EV_ITEMS: Set<String> = [
    "Macho Brace", "Power Anklet", "Power Band", "Power Belt",
    "Power Bracer", "Power Lens", "Power Weight",
]

nonisolated func getFinalSpeed(_ gen: ShowdownGeneration, _ p: ShowdownPokemon,
                   _ field: ShowdownField, _ side: ShowdownSide) -> Int {
    var speed = getModifiedStat(p.rawStats.spe, p.boosts.spe)
    var speedMods: [Int] = []
    if side.isTailwind { speedMods.append(8192) }

    let sun = field.weather == .sun || field.weather == .harshSunshine
    let rain = field.weather == .rain || field.weather == .heavyRain
    if (p.hasAbility("Unburden") && p.abilityOn)
        || (p.hasAbility("Chlorophyll") && sun)
        || (p.hasAbility("Sand Rush") && field.weather == .sand)
        || (p.hasAbility("Swift Swim") && rain)
        || (p.hasAbility("Slush Rush") && (field.weather == .hail || field.weather == .snow))
        || (p.hasAbility("Surge Surfer") && field.terrain == .electric) {
        speedMods.append(8192)
    } else if p.hasAbility("Quick Feet") && p.status != .none {
        speedMods.append(6144)
    } else if p.hasAbility("Slow Start") && p.abilityOn {
        speedMods.append(2048)
    } else if isQPActive(p, field) && getQPBoostedStat(p) == .spe {
        speedMods.append(6144)
    }

    if !(p.hasAbility("Unburden") && p.abilityOn) {
        if p.hasItem("Choice Scarf") {
            speedMods.append(6144)
        } else if p.hasItem("Iron Ball") || EV_ITEMS.contains(p.item ?? "") {
            speedMods.append(2048)
        } else if p.hasItem("Quick Powder") && p.named("Ditto") {
            speedMods.append(8192)
        }
    }

    speed = OF32(pokeRound(Double(speed * chainMods(speedMods, 410, 131172)) / 4096))
    if p.hasStatus(.par) && !p.hasAbility("Quick Feet") {
        // gen 0 (Champions) uses the modern 50% paralysis speed cut.
        speed = Int(floor(Double(OF32(speed * 50)) / 100))
    }
    speed = min(10000, speed)
    return max(0, speed)
}

nonisolated func computeFinalStats(_ gen: ShowdownGeneration, _ attacker: ShowdownPokemon,
                       _ defender: ShowdownPokemon, _ field: ShowdownField, _ stats: [ShowdownStat]) {
    let sides: [(ShowdownPokemon, ShowdownSide)] =
        [(attacker, field.attackerSide), (defender, field.defenderSide)]
    for (pokemon, side) in sides {
        for stat in stats {
            if stat == .spe {
                pokemon.stats.spe = getFinalSpeed(gen, pokemon, field, side)
            } else {
                pokemon.stats[stat] = getModifiedStat(pokemon.rawStats[stat], pokemon.boosts[stat])
            }
        }
    }
}

// MARK: - Pre-damage checks (util.ts)

nonisolated func checkAirLock(_ p: ShowdownPokemon, _ field: ShowdownField) {
    if p.hasAbility("Air Lock", "Cloud Nine") { field.weather = nil }
}

nonisolated func checkForecast(_ p: ShowdownPokemon, _ weather: ShowdownWeather?) {
    guard p.hasAbility("Forecast") && p.named("Castform") else { return }
    switch weather {
    case .sun, .harshSunshine: p.types = [.fire]
    case .rain, .heavyRain: p.types = [.water]
    case .hail, .snow: p.types = [.ice]
    default: p.types = [.normal]
    }
}

nonisolated func checkItem(_ p: ShowdownPokemon, _ magicRoomActive: Bool) {
    if (p.hasAbility("Klutz") && !EV_ITEMS.contains(p.item ?? "")) || magicRoomActive {
        p.disabledItem = p.item
        p.item = nil
    }
}

nonisolated func checkRawStatChanges(_ p: ShowdownPokemon, _ powerTrick: Bool, _ wonderRoom: Bool) {
    if powerTrick { swap(&p.rawStats.atk, &p.rawStats.def) }
    if wonderRoom { swap(&p.rawStats.def, &p.rawStats.spd) }
}

nonisolated func checkIntimidate(_ gen: ShowdownGeneration, _ source: ShowdownPokemon, _ target: ShowdownPokemon) {
    let blocked = target.hasAbility("Clear Body", "White Smoke", "Hyper Cutter", "Full Metal Body")
        || target.hasAbility("Inner Focus", "Own Tempo", "Oblivious", "Scrappy")   // gen0/8+
        || target.hasItem("Clear Amulet")
    guard source.hasAbility("Intimidate") && source.abilityOn && !blocked else { return }
    if target.hasAbility("Contrary", "Defiant", "Guard Dog") {
        target.boosts.atk = min(6, target.boosts.atk + 1)
    } else if target.hasAbility("Simple") {
        target.boosts.atk = max(-6, target.boosts.atk - 2)
    } else {
        target.boosts.atk = max(-6, target.boosts.atk - 1)
    }
    if target.hasAbility("Competitive") { target.boosts.spa = min(6, target.boosts.spa + 2) }
}

nonisolated func checkInfiltrator(_ p: ShowdownPokemon, _ affected: ShowdownSide) {
    if p.hasAbility("Infiltrator") {
        affected.isReflect = false; affected.isLightScreen = false; affected.isAuroraVeil = false
    }
}

nonisolated func checkSeedBoost(_ p: ShowdownPokemon, _ field: ShowdownField) {
    guard let item = p.item, item.contains("Seed"), field.terrain != nil else { return }
    let prefix = String(item.prefix(upTo: item.firstIndex(of: " ") ?? item.endIndex))
    let seedTerrain = ShowdownTerrain(rawValue: prefix)
    guard let seedTerrain, field.hasTerrain(seedTerrain) else { return }
    if seedTerrain == .grassy || seedTerrain == .electric {
        p.boosts.def = p.hasAbility("Contrary") ? max(-6, p.boosts.def - 1) : min(6, p.boosts.def + 1)
    } else {
        p.boosts.spd = p.hasAbility("Contrary") ? max(-6, p.boosts.spd - 1) : min(6, p.boosts.spd + 1)
    }
    p.item = nil
}

/// Multi-hit / repeated-use boost bookkeeping (Champions subset, faithful to util.ts).
@discardableResult
nonisolated func checkMultihitBoost(_ gen: ShowdownGeneration, _ attacker: ShowdownPokemon,
                        _ defender: ShowdownPokemon, _ move: ShowdownMove, _ field: ShowdownField,
                        _ attackerUsedItem: Bool = false, _ defenderUsedItem: Bool = false) -> (Bool, Bool) {
    // This Champions subset never consumes White Herb/berries, so the "used
    // item" flags pass straight through (kept in the signature for parity with
    // upstream's multi-hit loop, which threads them across iterations).
    let aUsed = attackerUsedItem
    let dUsed = defenderUsedItem
    if move.named("Power-Up Punch") {
        attacker.boosts.atk = min(attacker.boosts.atk + 1, 6)
        attacker.stats.atk = getModifiedStat(attacker.rawStats.atk, attacker.boosts.atk)
    }
    let defSimple = defender.hasAbility("Simple") ? 2 : 1
    if defender.hasAbility("Stamina") && !attacker.hasAbility("Unaware") {
        defender.boosts.def = min(defender.boosts.def + 1, 6)
        defender.stats.def = getModifiedStat(defender.rawStats.def, defender.boosts.def)
    } else if defender.hasAbility("Weak Armor") && !attacker.hasAbility("Unaware") {
        defender.boosts.def = max(defender.boosts.def - 1, -6)
        defender.stats.def = getModifiedStat(defender.rawStats.def, defender.boosts.def)
        defender.boosts.spe = min(defender.boosts.spe + 2, 6)
        defender.stats.spe = getFinalSpeed(gen, defender, field, field.defenderSide)
    }
    if let drops = move.dropsStats, !attacker.hasAbility("Unaware") {
        let stat: ShowdownStat = move.category == .special ? .spa : .atk
        var boosts = attacker.boosts[stat]
        if attacker.hasAbility("Contrary") {
            boosts = min(6, boosts + drops)
        } else {
            boosts = max(-6, boosts - drops * (attacker.hasAbility("Simple") ? 2 : 1))
        }
        attacker.boosts[stat] = boosts
        attacker.stats[stat] = getModifiedStat(attacker.rawStats[stat], attacker.boosts[stat])
    }
    _ = defSimple
    return (aUsed, dUsed)
}
