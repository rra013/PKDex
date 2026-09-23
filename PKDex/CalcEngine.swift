//
//  CalcEngine.swift
//  PKDex
//
//  Both damage engines as pure, main-actor-free functions.
//
//  This is a *verbatim* relocation of `DamageCalcVM.computeSingleResult` — the
//  legacy branch and the Champions/Showdown branch — with three substitutions
//  and no arithmetic changes:
//
//    * `attacker` / `defender` are `CalcSnapshot` instead of `CalcSide`
//    * the view model's global toggles come from `FieldSnapshot`
//    * it returns the numeric `CalcOutcome`; the display fields
//      (`effectivenessLabel`, `effectivenessColor`, `hitsToKO` text) stay in
//      the view model, since `Color` has no business in a solver
//
//  Every modifier is read in the same order and combined with the same
//  operations as before. If a number moves, that's a bug, not a refactor —
//  the existing damage suites (the nine `BattleTier` files,
//  `DamageCalcMegaEvolutionTests`, `AbilityTests`, `BattleItemsTests`,
//  `TypeChartTests`) all run through here and are the parity gate.
//

import Foundation

nonisolated enum CalcEngine {

    // MARK: - Entry point

    /// Evaluates one move, mirroring `computeSingleResult`'s precedence: the
    /// faithful Champions port wins when it can represent the matchup, the
    /// legacy engine handles everything else.
    ///
    /// This is the solver's single door in. Keeping the precedence here rather
    /// than at the call site means a solve and the on-screen result can't
    /// disagree about which engine answered.
    static func evaluate(
        move: MoveSnapshot,
        attacker: CalcSnapshot,
        defender: CalcSnapshot,
        field: FieldSnapshot
    ) -> CalcOutcome {
        if let champions = evaluateChampions(move: move, attacker: attacker,
                                            defender: defender, field: field) {
            return champions
        }
        return evaluateLegacy(move: move, attacker: attacker,
                              defender: defender, field: field)
    }

    // MARK: - Legacy engine

    /// Runs the legacy damage formula for one move.
    ///
    /// Mirrors `computeSingleResult`'s legacy branch exactly. Status moves and
    /// empty sides are the caller's problem — this assumes a real matchup, as
    /// the original did.
    static func evaluateLegacy(
        move: MoveSnapshot,
        attacker: CalcSnapshot,
        defender: CalcSnapshot,
        field: FieldSnapshot
    ) -> CalcOutcome {
        let moveType = move.type
        let movePower = move.power ?? 0
        let isPhysical = move.isPhysical
        let isContact = move.makesContact
        let stab = attacker.types.contains(moveType)
        let stabBonus = stab ? 1.5 : 1.0
        let burnReduction = (field.burn && isPhysical) ? 0.5 : 1.0
        let typeEff = computeTypeEffectiveness(moveType: moveType,
                                               defenderTypes: defender.types)
        let weatherMult = field.weather.moveDamageMultiplier(moveType: moveType)

        let itemMods = computeItemModifiers(
            attackerItem: attacker.effectiveHeldItem,
            defenderItem: defender.effectiveHeldItem,
            isPhysical: isPhysical,
            typeEffectiveness: typeEff,
            moveType: moveType
        )

        // Mold Breaker (and Teravolt / Turboblaze) suppresses the defender's
        // ability for modifier purposes during this move.
        let moldBreaker = attacker.effectiveAbility == "mold-breaker"
        let abilityMods = computeAbilityModifiers(
            attackerAbility: attacker.effectiveAbility,
            defenderAbility: defender.effectiveAbility,
            moveType: moveType,
            movePower: movePower,
            isPhysical: isPhysical,
            isContact: isContact,
            isSTAB: stab,
            typeEffectiveness: typeEff,
            weather: field.weather,
            attackerAtFullHP: attacker.atFullHP,
            defenderAtFullHP: defender.atFullHP,
            defenderTypes: defender.types,
            terrain: field.terrain,
            isSpread: field.multi,
            moldBreaker: moldBreaker
        )

        let baseAtk = isPhysical ? attacker.atk : attacker.spAtk
        let itemAtkMult = isPhysical ? itemMods.atkMultiplier : itemMods.spAtkMultiplier
        let effectiveAtk = Int(floor(Double(baseAtk) * itemAtkMult))

        let effectiveDef: Int
        if isPhysical {
            let snowMult = field.weather.snowDefMultiplier(defenderTypes: defender.types)
            effectiveDef = Int(floor(Double(defender.def) * snowMult * itemMods.defMultiplier))
        } else {
            let sandMult = field.weather.sandSpDefMultiplier(defenderTypes: defender.types)
            effectiveDef = Int(floor(Double(defender.spDef) * sandMult * itemMods.spDefMultiplier))
        }

        let terrainMult = field.terrain.moveDamageMultiplier(moveType: moveType)

        let raw = calcDamageRange(
            level: attacker.level, movePower: movePower,
            userAtk: effectiveAtk, defenderDef: effectiveDef,
            multi: field.multi,
            weatherMult: weatherMult, glaiveRush: field.glaiveRush,
            crit: field.crit, critMultiplier: 1.5,
            stabBonus: stabBonus, typeEffect: typeEff,
            burnReduction: burnReduction, abilityMods: abilityMods,
            zMoveBypass: field.zMoveBypass
        )

        let im = itemMods.damageMult * terrainMult
        let dMin = floor(raw.min * im)
        let dMax = floor(raw.max * im)

        let eff = abilityMods.typeEffOverride ?? typeEff
        // STAB is true on a natural type match OR when an ability grants it
        // (Protean / Libero).
        let hasSTAB = stab || abilityMods.stabOverride != nil

        return CalcOutcome(
            damageMin: dMin,
            damageMax: dMax,
            defenderHP: defender.hp,
            effectiveness: eff,
            isSTAB: hasSTAB,
            // The legacy formula yields a min/max pair, never per-roll values.
            rolls: nil
        )
    }

    // MARK: - Champions engine (vendored @smogon/calc port)

    /// Computes an outcome via the vendored `champions.ts` port
    /// (`calculateShowdown`, gen 0). Returns nil — signalling the caller to use
    /// the legacy engine — whenever the matchup can't be faithfully
    /// represented: a side not in Champions mode, a status move, or a
    /// species/move absent from the bundled Champions data.
    ///
    /// The guard chain is load-bearing, not defensive. `calculateShowdown`
    /// `preconditionFailure`s on any generation other than 0, so a solver loop
    /// that reached it with a non-Champions request would crash rather than
    /// fall back. Widen these guards only alongside the port.
    static func evaluateChampions(
        move: MoveSnapshot,
        attacker: CalcSnapshot,
        defender: CalcSnapshot,
        field: FieldSnapshot
    ) -> CalcOutcome? {
        guard attacker.championsMode, defender.championsMode else { return nil }
        guard !move.isStatus else { return nil }

        let gen = ShowdownGen0.shared
        guard let atkSpecies = showdownSpecies(gen, for: attacker),
              let defSpecies = showdownSpecies(gen, for: defender),
              gen.move(toID(move.name)) != nil else { return nil }

        let atk = makeShowdownPokemon(gen, side: attacker, species: atkSpecies,
                                      moveType: move.type, isAttacker: true,
                                      field: field)
        let def = makeShowdownPokemon(gen, side: defender, species: defSpecies,
                                      moveType: move.type, isAttacker: false,
                                      field: field)
        let smove = ShowdownMove(gen, move.name, ability: atk.ability,
                                 item: atk.item, isCrit: field.crit)
        let sfield = makeShowdownField(attacker: attacker, defender: defender,
                                       field: field)

        let result = calculateShowdown(gen, atk, def, smove, sfield)
        let damage = damageRange(result.damage)
        guard damage.max > 0 else { return nil }

        // Apply the toggles the Champions pipeline doesn't model itself.
        let post = (field.glaiveRush ? 2.0 : 1.0)
            * (field.zMoveBypass ? 0.25 : 1.0)
            * field.miscMultiplier

        return CalcOutcome(
            damageMin: floor(Double(damage.min) * post),
            damageMax: floor(Double(damage.max) * post),
            // The port's own HP, not the snapshot's: Champions mons are fixed
            // at level 50 / 31 IVs and the port computes max HP itself.
            defenderHP: def.rawStats.hp,
            effectiveness: computeTypeEffectiveness(moveType: move.type,
                                                    defenderTypes: defender.types),
            isSTAB: attacker.types.contains(move.type),
            rolls: damage.rolls.map { $0.map { Int(floor(Double($0) * post)) } }
        )
    }

    /// A side's final Speed as the Champions port computes it: stat stages,
    /// Choice Scarf / Iron Ball, Tailwind, weather and terrain speed
    /// abilities, Unburden, Quick Feet, Protosynthesis / Quark Drive, and
    /// paralysis. Returns nil off the Champions path, for the same reason
    /// `evaluateChampions` does: the port only has Champions data.
    ///
    /// Callers fall back to `CalcSnapshot.speed` (stages only) rather than a
    /// hand-rolled copy of these rules. The app already has several speed
    /// calculations, and they disagree.
    static func finalSpeed(_ side: CalcSnapshot, field: FieldSnapshot) -> Int? {
        guard side.championsMode else { return nil }
        let gen = ShowdownGen0.shared
        guard let species = showdownSpecies(gen, for: side) else { return nil }
        // `moveType` only picks a Plate for the generic type-boost item, which
        // doesn't touch Speed. Not the attacker, so the global Burn toggle
        // stays off.
        let pokemon = makeShowdownPokemon(gen, side: side, species: species,
                                          moveType: "Normal", isAttacker: false,
                                          field: field)
        // `makeShowdownField` puts `attacker`'s Tailwind on `attackerSide`.
        let sfield = makeShowdownField(attacker: side, defender: side, field: field)
        return getFinalSpeed(gen, pokemon, sfield, sfield.attackerSide)
    }

    /// Resolves the Showdown species for a side, honoring an active Mega. Megas
    /// are looked up through the ported `getForme`, which maps the held stone
    /// suffix (…ite / …ite Y) — or Dragon Ascent for Rayquaza — to the correct
    /// forme in the base species' `otherFormes`. Returns nil (→ legacy fallback)
    /// when the resolved species isn't in the bundled Champions data, e.g. a
    /// restricted Mega like Mewtwo/Rayquaza that isn't in the regulation set.
    static func showdownSpecies(_ gen: ShowdownGeneration,
                                for side: CalcSnapshot) -> ShowdownSpecies? {
        // Damage-calc UI path: base species + a resolved Mega form + held stone.
        // `heldItem` rather than `effectiveHeldItem` — the stone is what names
        // the forme, and a stone-based Mega reads as item-less by then.
        if side.megaForm != nil {
            let stone = side.heldItem != .none ? side.heldItem.rawValue : nil
            return resolveMegaSpecies(gen, baseName: side.species.name,
                                      stone: stone, moves: side.moves)
        }

        // Normal case: the name is a base (or already-correct) species.
        if let s = gen.species(toID(side.species.name)) { return s }

        // Battle-sim path: participants are fed as a synthetic Mega `PKMNStats`
        // (e.g. "Mega Charizard Y") with no `megaActive` flag. Recover the real
        // Showdown forme from the app's MegaForms table via the triggering stone.
        if let mf = MegaForms.all.first(where: { $0.displayName == side.species.name }) {
            return resolveMegaSpecies(gen, baseName: mf.speciesKey,
                                      stone: mf.stone?.rawValue, moves: side.moves)
        }
        return nil
    }

    /// Resolves a Mega's Showdown species record by running the ported `getForme`
    /// off the base species and its triggering stone (or Dragon Ascent). Returns
    /// nil when the base or forme isn't in the bundled Champions data.
    static func resolveMegaSpecies(_ gen: ShowdownGeneration, baseName: String,
                                   stone: String?,
                                   moves: [MoveSnapshot]) -> ShowdownSpecies? {
        guard let base = gen.species(toID(baseName)) else { return nil }
        let hasDragonAscent = moves.contains { $0.name == "Dragon Ascent" }
        let formeName = ShowdownPokemon.getForme(
            gen, base.name, item: stone, moveName: hasDragonAscent ? "Dragon Ascent" : nil)
        return gen.species(toID(formeName))
    }

    /// Collapses a `ShowdownDamageValue` into a total (min, max) range, keeping
    /// the per-roll values when the port produced them.
    ///
    /// `rolls` is non-nil only for the `.rolls` case. `.fixed` has no spread to
    /// report, and a multi-hit / Parental Bond `.matrix` is summed per hit —
    /// the row minima don't co-occur as one roll of the whole move, so exposing
    /// them as rolls would misstate the KO chance.
    static func damageRange(_ value: ShowdownDamageValue) -> (min: Int, max: Int, rolls: [Int]?) {
        switch value {
        case .fixed(let v):
            return (v, v, nil)
        case .rolls(let rolls):
            return (rolls.min() ?? 0, rolls.max() ?? 0, rolls)
        case .matrix(let rows):
            var mn = 0, mx = 0
            for row in rows {
                mn += row.min() ?? 0
                mx += row.max() ?? 0
            }
            return (mn, mx, nil)
        }
    }

    /// Builds a Champions (`gen 0`) `ShowdownPokemon` from a snapshot. EVs pass
    /// through as the 0–32 stat-point value the Champions formula expects; stat
    /// stages become boosts; a global Burn toggle is applied to the attacker.
    static func makeShowdownPokemon(_ gen: ShowdownGeneration, side: CalcSnapshot,
                                    species: ShowdownSpecies, moveType: String,
                                    isAttacker: Bool,
                                    field: FieldSnapshot) -> ShowdownPokemon {
        let evs = ShowdownStats(hp: side.evHP, atk: side.evAtk, def: side.evDef,
                                spa: side.evSpAtk, spd: side.evSpDef, spe: side.evSpeed)
        let boosts = ShowdownStats(hp: 0, atk: side.atkStage, def: side.defStage,
                                   spa: side.spAtkStage, spd: side.spDefStage, spe: side.speedStage)
        let ability = side.effectiveAbility.map { formatAbilityName($0) }
        let item = showdownItemName(side.effectiveHeldItem, moveType: moveType)
        // Per-mon status wins; the legacy global Burn toggle still applies to the
        // attacker for back-compat when no explicit status is set.
        let status: ShowdownStatus = side.status != .none
            ? side.status
            : ((isAttacker && field.burn) ? .brn : .none)

        // Champions Pokemon are always level 50 with 31 IVs, so max HP is fixed.
        let maxHP = calcHP(base: species.baseStats.hp, iv: 31, ev: 0, level: 50)
        let pct = max(1, min(100, side.currentHPPercent))
        let curHP = pct >= 100 ? nil : max(1, maxHP * pct / 100)

        return ShowdownPokemon(
            gen, species.name, species: species,
            ability: ability, abilityOn: side.abilityOn, item: item, nature: side.nature.name,
            evs: evs, boosts: boosts, curHP: curHP, status: status)
    }

    /// Maps the app's `HeldItem` to the Showdown item name the port recognises.
    /// The generic "Type-Boost (1.2x)" resolves to the Plate matching the move's
    /// type so the port's 1.2× same-type boost applies to this move.
    static func showdownItemName(_ item: HeldItem, moveType: String) -> String? {
        guard item != .none else { return nil }
        if item == .typeBoost { return typePlateName(moveType) }
        return item.rawValue
    }

    static func typePlateName(_ type: String) -> String {
        switch type {
        case "Normal":   return "Silk Scarf"
        case "Fire":     return "Flame Plate"
        case "Water":    return "Splash Plate"
        case "Electric": return "Zap Plate"
        case "Grass":    return "Meadow Plate"
        case "Ice":      return "Icicle Plate"
        case "Fighting": return "Fist Plate"
        case "Poison":   return "Toxic Plate"
        case "Ground":   return "Earth Plate"
        case "Flying":   return "Sky Plate"
        case "Psychic":  return "Mind Plate"
        case "Bug":      return "Insect Plate"
        case "Rock":     return "Stone Plate"
        case "Ghost":    return "Spooky Plate"
        case "Dragon":   return "Draco Plate"
        case "Dark":     return "Dread Plate"
        case "Steel":    return "Iron Plate"
        case "Fairy":    return "Pixie Plate"
        default:         return "Silk Scarf"
        }
    }

    /// Builds a `ShowdownField` from the global modifiers plus each side's
    /// conditions. The Multi-hit toggle switches to Doubles so genuinely-spread
    /// moves take the 0.75× reduction. `attacker`/`defender` map to the field's
    /// attacker/defender sides so screens, Helping Hand, hazards, etc. land on
    /// the correct half.
    static func makeShowdownField(attacker: CalcSnapshot, defender: CalcSnapshot,
                                 field: FieldSnapshot) -> ShowdownField {
        let sfield = ShowdownField()
        sfield.gameType = field.multi ? .doubles : .singles
        sfield.isGravity = field.gravity
        sfield.isWonderRoom = field.wonderRoom
        sfield.isMagicRoom = field.magicRoom

        switch field.weather {
        case .none: sfield.weather = nil
        case .sun:  sfield.weather = .sun
        case .rain: sfield.weather = .rain
        case .sand: sfield.weather = .sand
        case .snow: sfield.weather = .snow
        }
        switch field.terrain {
        case .none:     sfield.terrain = nil
        case .electric: sfield.terrain = .electric
        case .grassy:   sfield.terrain = .grassy
        case .misty:    sfield.terrain = .misty
        case .psychic:  sfield.terrain = .psychic
        }

        // Attacker-side conditions.
        sfield.attackerSide.isHelpingHand = attacker.isHelpingHand
        sfield.attackerSide.isTailwind = attacker.isTailwind

        // Defender-side conditions (reduce/condition the incoming hit).
        let d = sfield.defenderSide
        d.isReflect = defender.isReflect
        d.isLightScreen = defender.isLightScreen
        d.isAuroraVeil = defender.isAuroraVeil
        d.isFriendGuard = defender.isFriendGuard
        d.isProtected = defender.isProtected
        d.isSR = defender.isStealthRock
        d.spikes = max(0, min(3, defender.spikesLayers))
        return sfield
    }
}

// MARK: - Display mapping

extension CalcOutcome {

    /// The label the calc UI shows for an effectiveness multiplier.
    /// Unchanged from the view model's inline version.
    var effectivenessLabel: String {
        switch effectiveness {
        case 0:    return "Immune"
        case 0.25: return "1/4x"
        case 0.5:  return "1/2x"
        case 1:    return "1x"
        case 2:    return "2x"
        case 4:    return "4x"
        default:   return String(format: "%.2fx", effectiveness)
        }
    }
}
