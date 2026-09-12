//
//  ShowdownChampions.swift
//  PKDex
//
//  Port of @smogon/calc's mechanics/champions.ts — the Champions ("gen 0")
//  damage pipeline — plus the calc.ts dispatch entry point. MIT; see
//  PKDex/ShowdownPort-NOTES.md. The human-readable `RawDesc` sink is dropped
//  (damage-only): every `desc.X = …` line upstream is elided. The math mirrors
//  upstream line-for-line, including modifier order and rounding.
//

import Foundation

// MARK: - Entry point (calc.ts `calculate`)

/// Dispatches to the per-generation mechanics like upstream `MECHANICS[gen.num]`,
/// cloning inputs so callers keep their originals. Phase 1 wires Champions
/// (gen 0); other gens are not yet ported (see ShowdownPort-NOTES.md).
func calculateShowdown(_ gen: ShowdownGeneration, _ attacker: ShowdownPokemon,
                       _ defender: ShowdownPokemon, _ move: ShowdownMove,
                       _ field: ShowdownField? = nil) -> ShowdownResult {
    let f = field?.clone() ?? ShowdownField()
    switch gen.num {
    case 0:
        return calculateChampions(gen, attacker.clone(), defender.clone(), move.clone(), f)
    default:
        preconditionFailure("Showdown calc: generation \(gen.num) is not yet ported (only Champions/gen 0).")
    }
}

// MARK: - calculateChampions

func calculateChampions(_ gen: ShowdownGeneration, _ attacker: ShowdownPokemon,
                        _ defender: ShowdownPokemon, _ move: ShowdownMove,
                        _ field: ShowdownField) -> ShowdownResult {
    // #region Initial

    checkAirLock(attacker, field)
    checkAirLock(defender, field)
    checkForecast(attacker, field.weather)
    checkForecast(defender, field.weather)
    checkItem(attacker, field.isMagicRoom)
    checkItem(defender, field.isMagicRoom)
    checkRawStatChanges(attacker, field.attackerSide.isPowerTrick, field.isWonderRoom)
    checkRawStatChanges(defender, field.defenderSide.isPowerTrick, field.isWonderRoom)
    checkSeedBoost(attacker, field)
    checkSeedBoost(defender, field)

    computeFinalStats(gen, attacker, defender, field, [.def, .spd, .spe])

    checkIntimidate(gen, attacker, defender)
    checkIntimidate(gen, defender, attacker)

    if move.named("Meteor Beam", "Electro Shot") {
        attacker.boosts.spa += attacker.hasAbility("Contrary") ? -1 : 1
        attacker.boosts.spa = min(6, max(-6, attacker.boosts.spa))
    }

    computeFinalStats(gen, attacker, defender, field, [.atk, .spa])

    checkInfiltrator(attacker, field.defenderSide)
    checkInfiltrator(defender, field.attackerSide)

    var result = ShowdownResult()

    if move.category == .status {
        return result
    }

    if move.named("Shell Side Arm")
        && getShellSideArmCategory(attacker, defender, field.isWonderRoom) == .physical {
        move.category = .physical
        move.flags["contact"] = 1
    }

    let breaksProtect = move.breaksProtect
        || (attacker.hasAbility("Unseen Fist", "Piercing Drill") && move.hasFlag("contact"))

    if field.defenderSide.isProtected && !breaksProtect {
        return result
    }

    if move.name == "Pain Split" {
        let average = Int(floor(Double(attacker.curHP() + defender.curHP()) / 2))
        result.damage = .fixed(max(0, defender.curHP() - average))
        return result
    }

    let defenderAbilityIgnored = defender.hasAbility(
        "Aura Guard", "Armor Tail", "Aroma Veil", "Battle Armor",
        "Big Pecks", "Bulletproof", "Clear Body", "Contrary",
        "Damp", "Disguise", "Dry Skin", "Earth Eater", "Eelevate",
        "Filter", "Flash Fire", "Flower Veil", "Fluffy",
        "Friend Guard", "Fur Coat", "Grass Pelt", "Guard Dog",
        "Heatproof", "Heavy Metal", "Hyper Cutter", "Illuminate",
        "Immunity", "Inner Focus", "Insomnia", "Keen Eye", "Leaf Guard",
        "Levitate", "Light Metal", "Lightning Rod", "Limber",
        "Magic Bounce", "Magma Armor", "Marvel Scale", "Mirror Armor",
        "Motor Drive", "Multiscale", "Oblivious", "Overcoat", "Own Tempo",
        "Punk Rock", "Purifying Salt", "Queenly Majesty", "Sand Veil",
        "Sap Sipper", "Shell Armor", "Shield Dust", "Snow Cloak",
        "Solid Rock", "Soundproof", "Sticky Hold", "Storm Drain", "Sturdy",
        "Sweet Veil", "Tangled Feet", "Telepathy", "Thermal Exchange",
        "Thick Fat", "Unaware", "Vital Spirit", "Volt Absorb",
        "Water Absorb", "Water Bubble", "Water Veil", "White Smoke")

    let attackerIgnoresAbility = attacker.hasAbility("Mold Breaker")

    if defenderAbilityIgnored && attackerIgnoresAbility {
        defender.ability = ""
    }

    // Merciless does not ignore Shell Armor: a poisoned target with Shell Armor
    // will not be crit.
    let isCritical = !defender.hasAbility("Shell Armor", "Battle Armor")
        && (move.isCrit || (attacker.hasAbility("Merciless") && defender.hasStatus(.psn, .tox)))
        && move.timesUsed == 1

    var type = move.type
    if move.originalName == "Weather Ball" {
        let isMegaSol = attacker.hasAbility("Mega Sol")
        type = (field.hasWeather(.sun, .harshSunshine) || isMegaSol) ? .fire
            : field.hasWeather(.rain, .heavyRain) ? .water
            : field.hasWeather(.sand) ? .rock
            : field.hasWeather(.hail, .snow) ? .ice
            : .normal
    } else if move.originalName == "Terrain Pulse" && sdIsGrounded(attacker, field) {
        type = field.hasTerrain(.electric) ? .electric
            : field.hasTerrain(.grassy) ? .grass
            : field.hasTerrain(.misty) ? .fairy
            : field.hasTerrain(.psychic) ? .psychic
            : .normal
    } else if move.named("Aura Wheel") {
        if attacker.named("Morpeko") {
            type = .electric
        } else if attacker.named("Morpeko-Hangry") {
            type = .dark
        }
    } else if move.named("Raging Bull") {
        if attacker.named("Tauros-Paldea-Combat") {
            type = .fighting
        } else if attacker.named("Tauros-Paldea-Blaze") {
            type = .fire
        } else if attacker.named("Tauros-Paldea-Aqua") {
            type = .water
        }
        field.defenderSide.isReflect = false
        field.defenderSide.isLightScreen = false
        field.defenderSide.isAuroraVeil = false
    } else if move.named("Brick Break", "Psychic Fangs") {
        field.defenderSide.isReflect = false
        field.defenderSide.isLightScreen = false
        field.defenderSide.isAuroraVeil = false
    }

    if attacker.hasAbility("Electromorphosis") && attacker.abilityOn {
        field.attackerSide.isCharge = true
    }

    var hasAteAbilityTypeChange = false
    let noTypeChange = move.named("Weather Ball", "Terrain Pulse", "Struggle")

    if !noTypeChange {
        let normal = type == .normal
        var isAerilate = false, isDragonize = false, isPixilate = false, isRefrigerate = false
        var isLiquidVoice = false
        if attacker.hasAbility("Aerilate") && normal {
            isAerilate = true; type = .flying
        } else if attacker.hasAbility("Dragonize") && normal {
            isDragonize = true; type = .dragon
        } else if attacker.hasAbility("Liquid Voice") && move.hasFlag("sound") {
            isLiquidVoice = true; type = .water
        } else if attacker.hasAbility("Pixilate") && normal {
            isPixilate = true; type = .fairy
        } else if attacker.hasAbility("Refrigerate") && normal {
            isRefrigerate = true; type = .ice
        }
        if isAerilate || isDragonize || isPixilate || isRefrigerate {
            hasAteAbilityTypeChange = true
        }
        _ = isLiquidVoice
    }

    move.type = type

    let isGhostRevealed = attacker.hasAbility("Scrappy")

    let type1Effectiveness = getMoveEffectiveness(
        gen, move, defender.types[0],
        isGhostRevealed: isGhostRevealed, isGravity: field.isGravity, isRingTarget: false)
    let type2Effectiveness = defender.types.count > 1
        ? getMoveEffectiveness(
            gen, move, defender.types[1],
            isGhostRevealed: isGhostRevealed, isGravity: field.isGravity, isRingTarget: false)
        : 1.0

    var typeEffectiveness = type1Effectiveness * type2Effectiveness

    if typeEffectiveness == 0 && move.hasType(.ground)
        && defender.hasItem("Iron Ball") && !defender.hasAbility("Klutz") {
        typeEffectiveness = 1
    }

    if typeEffectiveness == 0 {
        return result
    }

    if (move.named("Steel Roller") && field.terrain == nil)
        || (move.named("Poltergeist") && (defender.item == nil || defender.item!.isEmpty)) {
        return result
    }

    if (move.hasType(.grass) && defender.hasAbility("Sap Sipper"))
        || (move.hasType(.fire) && defender.hasAbility("Flash Fire"))
        || (move.hasType(.water) && defender.hasAbility("Dry Skin", "Water Absorb"))
        || (move.hasType(.electric) && defender.hasAbility("Lightning Rod", "Motor Drive", "Volt Absorb"))
        || (move.hasType(.ground) && !field.isGravity && defender.hasAbility("Levitate", "Eelevate"))
        || (move.hasFlag("bullet") && defender.hasAbility("Bulletproof"))
        || (move.hasFlag("sound") && !move.named("Clangorous Soul") && defender.hasAbility("Soundproof"))
        || (move.priority > 0 && defender.hasAbility("Queenly Majesty", "Armor Tail"))
        || (move.hasType(.ground) && defender.hasAbility("Earth Eater")) {
        return result
    }

    if move.hasType(.ground) && !field.isGravity && defender.hasItem("Air Balloon") {
        return result
    }

    if move.priority > 0 && field.hasTerrain(.psychic) && sdIsGrounded(defender, field) {
        return result
    }

    let fixedDamage = handleFixedDamageMoves(attacker, move)
    if fixedDamage != 0 {
        if attacker.hasAbility("Parental Bond") {
            result.damage = .matrix([[fixedDamage], [fixedDamage]])
        } else {
            result.damage = .fixed(fixedDamage)
        }
        return result
    }

    if move.named("Final Gambit") {
        result.damage = .fixed(attacker.curHP())
        return result
    }

    // #endregion
    // #region Base Power

    let basePower = calculateBasePowerChampions(
        gen, attacker, defender, move, field, hasAteAbilityTypeChange)
    if basePower == 0 {
        return result
    }

    // #endregion
    // #region (Special) Attack
    let attack = calculateAttackChampions(gen, attacker, defender, move, field, isCritical)
    // #endregion

    // #region (Special) Defense
    let defense = calculateDefenseChampions(gen, attacker, defender, move, field, isCritical)
    // #endregion

    // #region Damage

    let baseDamage = calculateBaseDamageChampions(
        gen, attacker, defender, basePower, attack, defense, move, field, isCritical)

    if attacker.hasAbility("Gale Wings") && move.hasType(.flying)
        && attacker.curHP() == attacker.maxHP() {
        move.priority = 1
    }

    // the random factor is applied between the crit mod and the stab mod, so
    // don't apply anything below this until we're inside the loop
    var stabMod = getStabMod(attacker, move)

    let applyBurn = attacker.hasStatus(.brn) && move.category == .physical
        && !attacker.hasAbility("Guts") && !move.named("Facade")

    let finalMods = calculateFinalModsChampions(
        gen, attacker, defender, move, field, isCritical, typeEffectiveness)

    var protect = false
    if field.defenderSide.isProtected
        && (attacker.hasAbility("Unseen Fist", "Piercing Drill") && move.hasFlag("contact")) {
        protect = true
    }

    let finalMod = chainMods(finalMods, 41, 131072)

    let isSpread = field.gameType != .singles
        && ["allAdjacent", "allAdjacentFoes"].contains(move.target)

    var childDamage: [Int]? = nil
    if attacker.hasAbility("Parental Bond") && move.hits == 1 && !isSpread {
        let child = attacker.clone()
        child.ability = "Parental Bond (Child)"
        _ = checkMultihitBoost(gen, child, defender, move, field)
        if case let .rolls(r) = calculateChampions(gen, child, defender, move, field).damage {
            childDamage = r
        }
    }

    var damage = [Int]()
    for i in 0..<16 {
        damage.append(getFinalDamage(
            baseDamage, i, typeEffectiveness, applyBurn, stabMod, finalMod, protect))
    }
    result.damage = childDamage != nil ? .matrix([damage, childDamage!]) : .rolls(damage)

    if move.timesUsed > 1 || move.hits > 1 {
        var numAttacks = 1
        if move.timesUsed > 1 {
            numAttacks = move.timesUsed
        } else {
            numAttacks = move.hits
        }
        var usedItems = (false, false)
        var damageMatrix = [damage]
        var times = 1
        while times < numAttacks {
            usedItems = checkMultihitBoost(
                gen, attacker, defender, move, field, usedItems.0, usedItems.1)
            let newAttack = calculateAttackChampions(gen, attacker, defender, move, field, isCritical)
            let newDefense = calculateDefenseChampions(gen, attacker, defender, move, field, isCritical)
            // Check if lost -ate ability. Typing stays the same, only boost is lost.
            hasAteAbilityTypeChange = hasAteAbilityTypeChange
                && attacker.hasAbility("Aerilate", "Dragonize", "Pixilate", "Refrigerate")

            if move.timesUsed > 1 {
                stabMod = getStabMod(attacker, move)
            }

            let newBasePower = calculateBasePowerChampions(
                gen, attacker, defender, move, field, hasAteAbilityTypeChange, hit: times + 1)
            let newBaseDamage = calculateBaseDamageChampions(
                gen, attacker, defender, newBasePower, newAttack, newDefense, move, field, isCritical)
            let newFinalMods = calculateFinalModsChampions(
                gen, attacker, defender, move, field, isCritical, typeEffectiveness, hitCount: times)
            let newFinalMod = chainMods(newFinalMods, 41, 131072)

            var damageArray = [Int]()
            for i in 0..<16 {
                damageArray.append(getFinalDamage(
                    newBaseDamage, i, typeEffectiveness, applyBurn, stabMod, newFinalMod, protect))
            }
            damageMatrix.append(damageArray)
            times += 1
        }
        result.damage = .matrix(damageMatrix)
    }

    // #endregion

    return result
}

// MARK: - Base Power

func calculateBasePowerChampions(_ gen: ShowdownGeneration, _ attacker: ShowdownPokemon,
                                 _ defender: ShowdownPokemon, _ move: ShowdownMove,
                                 _ field: ShowdownField, _ hasAteAbilityTypeChange: Bool,
                                 hit: Int = 1) -> Int {
    let turnOrder = attacker.stats.spe > defender.stats.spe ? "first" : "last"

    var basePower: Int

    switch move.name {
    case "Payback":
        basePower = move.bp * (turnOrder == "last" ? 2 : 1)
    case "Electro Ball":
        if defender.stats.spe == 0 {
            basePower = 40
        } else {
            let r = attacker.stats.spe / defender.stats.spe
            basePower = r >= 4 ? 150 : r >= 3 ? 120 : r >= 2 ? 80 : r >= 1 ? 60 : 40
        }
    case "Gyro Ball":
        if attacker.stats.spe == 0 {
            basePower = 1
        } else {
            basePower = min(150, (25 * defender.stats.spe) / attacker.stats.spe + 1)
        }
    case "Punishment":
        basePower = min(200, 60 + 20 * countBoosts(defender.boosts))
    case "Low Kick", "Grass Knot":
        let w = getWeight(defender)
        basePower = w >= 200 ? 120 : w >= 100 ? 100 : w >= 50 ? 80 : w >= 25 ? 60 : w >= 10 ? 40 : 20
    case "Hex", "Infernal Parade":
        basePower = move.bp * (defender.status != .none ? 2 : 1)
    case "Barb Barrage":
        basePower = move.bp * (defender.hasStatus(.psn, .tox) ? 2 : 1)
    case "Heavy Slam", "Heat Crash":
        let wr = getWeight(attacker) / getWeight(defender)
        basePower = wr >= 5 ? 120 : wr >= 4 ? 100 : wr >= 3 ? 80 : wr >= 2 ? 60 : 40
    case "Stored Power", "Power Trip":
        basePower = 20 + 20 * countBoosts(attacker.boosts)
    case "Acrobatics":
        basePower = move.bp * ((attacker.item == nil || attacker.item!.isEmpty) ? 2 : 1)
    case "Assurance":
        basePower = move.bp * (defender.hasAbility("Parental Bond (Child)") ? 2 : 1)
    case "Smelling Salts":
        basePower = move.bp * (defender.hasStatus(.par) ? 2 : 1)
    case "Weather Ball":
        basePower = move.bp * ((field.weather != nil || attacker.hasAbility("Mega Sol")) ? 2 : 1)
    case "Terrain Pulse":
        basePower = move.bp * ((sdIsGrounded(attacker, field) && field.terrain != nil) ? 2 : 1)
    case "Rising Voltage":
        basePower = move.bp * ((sdIsGrounded(defender, field) && field.hasTerrain(.electric)) ? 2 : 1)
    case "Fling":
        basePower = ShowdownItems.flingPower(attacker.item)
    case "Eruption", "Water Spout":
        basePower = max(1, Int(floor(Double(150 * attacker.curHP()) / Double(attacker.maxHP()))))
    case "Flail", "Reversal":
        let p = Int(floor(Double(48 * attacker.curHP()) / Double(attacker.maxHP())))
        basePower = p <= 1 ? 200 : p <= 4 ? 150 : p <= 9 ? 100 : p <= 16 ? 80 : p <= 32 ? 40 : 20
    case "Triple Axel":
        // Triple Axel's damage increases after each consecutive hit (20, 40, 60).
        basePower = hit * 20
    case "Hard Press":
        var bp = 100 * Int(floor(Double(defender.curHP() * 4096) / Double(defender.maxHP())))
        bp = Int(floor(Double(Int(floor(Double(100 * bp + 2048 - 1) / 4096))) / 100))
        basePower = bp == 0 ? 1 : bp
    default:
        basePower = move.bp
    }

    if basePower == 0 {
        return 0
    }
    let bpMods = calculateBPModsChampions(
        gen, attacker, defender, move, field, basePower, hasAteAbilityTypeChange, turnOrder, hit)
    return OF16(max(1, pokeRound(Double(basePower * chainMods(bpMods, 41, 2097152)) / 4096)))
}

func calculateBPModsChampions(_ gen: ShowdownGeneration, _ attacker: ShowdownPokemon,
                              _ defender: ShowdownPokemon, _ move: ShowdownMove,
                              _ field: ShowdownField, _ basePower: Int,
                              _ hasAteAbilityTypeChange: Bool, _ turnOrder: String,
                              _ hit: Int) -> [Int] {
    var bpMods = [Int]()

    // Move effects
    let defenderItem = (defender.item != nil && defender.item != "") ? defender.item : defender.disabledItem
    var resistedKnockOffDamage = (defenderItem == nil || defenderItem!.isEmpty)

    // Only applies when the Pokemon holds the Mega Stone matching its species
    // (or when it's already a Mega-Evolution).
    if !resistedKnockOffDamage, let di = defenderItem {
        resistedKnockOffDamage = ShowdownItems.isHeldMegaStone(di, speciesName: defender.name)
    }

    // Resist Knock Off damage if the item was already knocked off.
    if !resistedKnockOffDamage && hit > 1 && !defender.hasAbility("Sticky Hold") {
        resistedKnockOffDamage = true
    }

    if (move.named("Facade") && attacker.hasStatus(.brn, .par, .psn, .tox))
        || (move.named("Venoshock") && defender.hasStatus(.psn, .tox))
        || (move.named("Lash Out") && countBoosts(attacker.boosts) < 0) {
        bpMods.append(8192)
    } else if move.named("Expanding Force") && sdIsGrounded(attacker, field) && field.hasTerrain(.psychic) {
        move.target = "allAdjacentFoes"
        bpMods.append(6144)
    } else if (move.named("Knock Off") && !resistedKnockOffDamage)
        || (move.named("Misty Explosion") && sdIsGrounded(attacker, field) && field.hasTerrain(.misty))
        || (move.named("Grav Apple") && field.isGravity) {
        bpMods.append(6144)
    } else if move.named("Solar Beam", "Solar Blade")
        && field.hasWeather(.rain, .sand, .hail, .snow) && !attacker.hasAbility("Mega Sol") {
        bpMods.append(2048)
    }

    if field.attackerSide.isHelpingHand {
        bpMods.append(6144)
    }

    // Field effects
    let terrainMultiplier = 5325
    if sdIsGrounded(attacker, field) {
        if (field.hasTerrain(.electric) && move.hasType(.electric))
            || (field.hasTerrain(.grassy) && move.hasType(.grass))
            || (field.hasTerrain(.psychic) && move.hasType(.psychic)) {
            bpMods.append(terrainMultiplier)
        }
    }
    if sdIsGrounded(defender, field) {
        if (field.hasTerrain(.misty) && move.hasType(.dragon))
            || (field.hasTerrain(.grassy) && move.named("Bulldoze", "Earthquake")) {
            bpMods.append(2048)
        }
    }

    // Abilities
    // Use BasePower after moves with custom BP to determine if Technician should boost.
    if (attacker.hasAbility("Technician") && basePower <= 60)
        || (attacker.hasAbility("Mega Launcher") && move.hasFlag("pulse"))
        || (attacker.hasAbility("Strong Jaw") && move.hasFlag("bite"))
        || (attacker.hasAbility("Steely Spirit") && move.hasType(.steel))
        || (attacker.hasAbility("Sharpness") && move.hasFlag("slicing")) {
        bpMods.append(6144)
    }

    if field.attackerSide.isCharge && move.hasType(.electric) {
        bpMods.append(8192)
    }

    let aura = "\(move.type.rawValue) Aura"
    let isAttackerAura = attacker.hasAbility(aura)
    let isDefenderAura = defender.hasAbility(aura)
    let isFieldFairyAura = field.isFairyAura && move.type == .fairy
    let isFieldDarkAura = field.isDarkAura && move.type == .dark
    if isAttackerAura || isDefenderAura || isFieldFairyAura || isFieldDarkAura {
        bpMods.append(5448)
    }

    if (attacker.hasAbility("Sheer Force") && (move.secondaries || move.named("Electro Shot")))
        || (attacker.hasAbility("Sand Force") && field.hasWeather(.sand) && move.hasType(.rock, .ground, .steel))
        || (attacker.hasAbility("Analytic")
            && (turnOrder != "first" || field.defenderSide.isSwitching == "out" || attacker.abilityOn))
        || (attacker.hasAbility("Tough Claws") && move.hasFlag("contact"))
        || (attacker.hasAbility("Punk Rock") && move.hasFlag("sound")) {
        bpMods.append(5325)
    }

    if attacker.hasAbility("Rivalry") && ![attacker.gender, defender.gender].contains("N") {
        if attacker.gender == defender.gender {
            bpMods.append(5120)
        } else {
            bpMods.append(3072)
        }
    }

    // The -ate abilities already changed move typing earlier.
    if hasAteAbilityTypeChange {
        bpMods.append(4915)
    }

    if (attacker.hasAbility("Reckless") && (move.recoil != nil || move.hasCrashDamage))
        || (attacker.hasAbility("Iron Fist") && move.hasFlag("punch")) {
        bpMods.append(4915)
    }

    if defender.hasAbility("Dry Skin") && move.hasType(.fire) {
        bpMods.append(5120)
    }

    if attacker.hasAbility("Supreme Overlord"), let fainted = attacker.alliesFainted, fainted > 0 {
        let powMod = [4096, 4506, 4915, 5325, 5734, 6144]
        bpMods.append(powMod[min(5, fainted)])
    }

    // Items
    if attacker.hasItem("\(move.type.rawValue) Gem") {
        bpMods.append(5325)
    } else if let item = attacker.item, move.hasType(ShowdownItems.itemBoostType(item)) {
        bpMods.append(4915)
    } else if (attacker.hasItem("Muscle Band") && move.category == .physical)
        || (attacker.hasItem("Wise Glasses") && move.category == .special) {
        bpMods.append(4505)
    }

    return bpMods
}

// MARK: - Attack

func calculateAttackChampions(_ gen: ShowdownGeneration, _ attacker: ShowdownPokemon,
                              _ defender: ShowdownPokemon, _ move: ShowdownMove,
                              _ field: ShowdownField, _ isCritical: Bool = false) -> Int {
    var attack: Int
    let attackSource = move.named("Foul Play") ? defender : attacker
    let attackStat: ShowdownStat = move.named("Body Press")
        ? (field.isWonderRoom ? .spd : .def)
        : (move.category == .special ? .spa : .atk)
    let boosts = attackSource.boosts[attackStat]
    if boosts == 0 || (isCritical && boosts < 0) {
        attack = attackSource.rawStats[attackStat]
    } else if defender.hasAbility("Unaware") {
        attack = attackSource.rawStats[attackStat]
    } else {
        attack = getModifiedStat(attackSource.rawStats[attackStat], boosts)
    }

    // Unlike all other attack modifiers, Hustle gets applied directly.
    if attacker.hasAbility("Hustle") && move.category == .physical {
        attack = pokeRound(Double(attack * 3) / 2)
    }

    let atMods = calculateAtModsChampions(gen, attacker, defender, move, field)
    return OF16(max(1, pokeRound(Double(attack * chainMods(atMods, 410, 131072)) / 4096)))
}

func calculateAtModsChampions(_ gen: ShowdownGeneration, _ attacker: ShowdownPokemon,
                              _ defender: ShowdownPokemon, _ move: ShowdownMove,
                              _ field: ShowdownField) -> [Int] {
    var atMods = [Int]()

    if attacker.hasAbility("Solar Power") && field.hasWeather(.sun) && move.category == .special {
        atMods.append(6144)
    } else if (attacker.hasAbility("Guts") && attacker.status != .none && move.category == .physical)
        || (attacker.curHP() <= attacker.maxHP() / 3
            && ((attacker.hasAbility("Overgrow") && move.hasType(.grass))
                || (attacker.hasAbility("Blaze") && move.hasType(.fire))
                || (attacker.hasAbility("Torrent") && move.hasType(.water))
                || (attacker.hasAbility("Swarm") && move.hasType(.bug))))
        || (move.category == .special && attacker.abilityOn && attacker.hasAbility("Plus", "Minus")) {
        atMods.append(6144)
    } else if attacker.hasAbility("Flash Fire") && attacker.abilityOn && move.hasType(.fire) {
        atMods.append(6144)
    } else if attacker.hasAbility("Fire Mane") && move.hasType(.fire) {
        atMods.append(6144)
    } else if (attacker.hasAbility("Water Bubble") && move.hasType(.water))
        || (attacker.hasAbility("Huge Power", "Pure Power") && move.category == .physical) {
        atMods.append(8192)
    } else if attacker.hasAbility("Stakeout") && attacker.abilityOn {
        atMods.append(8192)
    }

    if (defender.hasAbility("Thick Fat") && move.hasType(.fire, .ice))
        || (defender.hasAbility("Water Bubble") && move.hasType(.fire))
        || (defender.hasAbility("Purifying Salt") && move.hasType(.ghost)) {
        atMods.append(2048)
    }

    if defender.hasAbility("Heatproof") && move.hasType(.fire) {
        atMods.append(2048)
    }

    if attacker.hasItem("Light Ball") && attacker.name.contains("Pikachu") {
        atMods.append(8192)
    }

    return atMods
}

// MARK: - Defense

func calculateDefenseChampions(_ gen: ShowdownGeneration, _ attacker: ShowdownPokemon,
                               _ defender: ShowdownPokemon, _ move: ShowdownMove,
                               _ field: ShowdownField, _ isCritical: Bool = false) -> Int {
    var defense: Int
    let hitsPhysical = move.overrideDefensiveStat == "def" || move.category == .physical
    let defenseStat: ShowdownStat = hitsPhysical ? .def : .spd

    let boosts = defender.boosts[defenseStat]
    if boosts == 0 || (isCritical && boosts > 0) || move.ignoreDefensive {
        defense = defender.rawStats[defenseStat]
    } else if attacker.hasAbility("Unaware") {
        defense = defender.rawStats[defenseStat]
    } else {
        defense = getModifiedStat(defender.rawStats[defenseStat], boosts)
    }

    // Unlike all other defense modifiers, the Sandstorm/Snow boost is applied directly.
    if !attacker.hasAbility("Mega Sol") {
        if field.hasWeather(.sand) && defender.hasType(.rock) && !hitsPhysical {
            defense = pokeRound(Double(defense * 3) / 2)
        }
        if field.hasWeather(.snow) && defender.hasType(.ice) && hitsPhysical {
            defense = pokeRound(Double(defense * 3) / 2)
        }
    }

    let dfMods = calculateDfModsChampions(gen, attacker, defender, move, field, isCritical, hitsPhysical)
    return OF16(max(1, pokeRound(Double(defense * chainMods(dfMods, 410, 131072)) / 4096)))
}

func calculateDfModsChampions(_ gen: ShowdownGeneration, _ attacker: ShowdownPokemon,
                              _ defender: ShowdownPokemon, _ move: ShowdownMove,
                              _ field: ShowdownField, _ isCritical: Bool = false,
                              _ hitsPhysical: Bool = false) -> [Int] {
    var dfMods = [Int]()
    if defender.hasAbility("Marvel Scale") && defender.status != .none && hitsPhysical {
        dfMods.append(6144)
    } else if defender.hasAbility("Grass Pelt") && field.hasTerrain(.grassy) && hitsPhysical {
        dfMods.append(6144)
    } else if defender.hasAbility("Fur Coat") && hitsPhysical {
        dfMods.append(8192)
    }
    return dfMods
}

// MARK: - Base Damage

func calculateBaseDamageChampions(_ gen: ShowdownGeneration, _ attacker: ShowdownPokemon,
                                  _ defender: ShowdownPokemon, _ basePower: Int,
                                  _ attack: Int, _ defense: Int, _ move: ShowdownMove,
                                  _ field: ShowdownField, _ isCritical: Bool = false) -> Int {
    var baseDamage = getBaseDamage(attacker.level, basePower, attack, defense)
    let isSpread = field.gameType != .singles
        && ["allAdjacent", "allAdjacentFoes"].contains(move.target)
    if isSpread {
        baseDamage = pokeRound(Double(OF32(baseDamage * 3072)) / 4096)
    }

    if attacker.hasAbility("Parental Bond (Child)") {
        baseDamage = pokeRound(Double(OF32(baseDamage * 1024)) / 4096)
    }

    let isMegaSol = attacker.hasAbility("Mega Sol")
    if ((field.hasWeather(.sun) || isMegaSol) && move.hasType(.fire))
        || ((field.hasWeather(.rain) && !isMegaSol) && move.hasType(.water)) {
        baseDamage = pokeRound(Double(OF32(baseDamage * 6144)) / 4096)
    } else if ((field.hasWeather(.sun) || isMegaSol) && move.hasType(.water))
        || (field.hasWeather(.rain) && move.hasType(.fire)) {
        baseDamage = pokeRound(Double(OF32(baseDamage * 2048)) / 4096)
    }

    if isCritical {
        baseDamage = OF32(Int(floor(Double(baseDamage) * 1.5)))
    }

    return baseDamage
}

// MARK: - Final Mods

func calculateFinalModsChampions(_ gen: ShowdownGeneration, _ attacker: ShowdownPokemon,
                                 _ defender: ShowdownPokemon, _ move: ShowdownMove,
                                 _ field: ShowdownField, _ isCritical: Bool = false,
                                 _ typeEffectiveness: Double, hitCount: Int = 0) -> [Int] {
    var finalMods = [Int]()

    if field.defenderSide.isReflect && move.category == .physical
        && !isCritical && !field.defenderSide.isAuroraVeil {
        // doesn't stack with Aurora Veil
        finalMods.append(field.gameType != .singles ? 2732 : 2048)
    } else if field.defenderSide.isLightScreen && move.category == .special
        && !isCritical && !field.defenderSide.isAuroraVeil {
        finalMods.append(field.gameType != .singles ? 2732 : 2048)
    }
    if field.defenderSide.isAuroraVeil && !isCritical {
        finalMods.append(field.gameType != .singles ? 2732 : 2048)
    }

    if attacker.hasAbility("Sniper") && isCritical {
        finalMods.append(6144)
    }

    if defender.hasAbility("Multiscale")
        && defender.curHP() == defender.maxHP()
        && hitCount == 0
        && (!field.defenderSide.isSR && (field.defenderSide.spikes == 0 || defender.hasType(.flying)))
        && !attacker.hasAbility("Parental Bond (Child)") {
        finalMods.append(2048)
    }

    let halveContactMoveDmg = defender.hasAbility("Fluffy") || defender.hasAbility("Aura Guard")
    if halveContactMoveDmg && move.hasFlag("contact") && !attacker.hasAbility("Long Reach") {
        finalMods.append(2048)
    } else if defender.hasAbility("Punk Rock") && move.hasFlag("sound") {
        finalMods.append(2048)
    }

    if defender.hasAbility("Solid Rock", "Filter") && typeEffectiveness > 1 {
        finalMods.append(3072)
    }

    if field.defenderSide.isFriendGuard {
        finalMods.append(3072)
    }

    if defender.hasAbility("Fluffy") && move.hasType(.fire) {
        finalMods.append(8192)
    }

    if attacker.hasItem("Expert Belt") && typeEffectiveness > 1 {
        finalMods.append(4915)
    } else if attacker.hasItem("Life Orb") {
        finalMods.append(5324)
    } else if attacker.hasItem("Metronome"), (move.timesUsedWithMetronome ?? 0) >= 1 {
        let timesUsedWithMetronome = move.timesUsedWithMetronome ?? 0
        if timesUsedWithMetronome <= 4 {
            finalMods.append(4096 + timesUsedWithMetronome * 819)
        } else {
            finalMods.append(8192)
        }
    }

    if move.hasType(ShowdownItems.berryResistType(defender.item))
        && (typeEffectiveness > 1 || move.hasType(.normal))
        && hitCount == 0
        && !attacker.hasAbility("Unnerve") {
        finalMods.append(defender.hasAbility("Ripen") ? 1024 : 2048)
    }

    return finalMods
}
