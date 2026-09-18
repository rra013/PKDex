//
//  CalcEngine.swift
//  PKDex
//
//  The legacy damage engine as a pure, main-actor-free function.
//
//  This is a *verbatim* relocation of `DamageCalcVM.computeSingleResult`'s
//  legacy branch, with three substitutions and no arithmetic changes:
//
//    * `attacker` / `defender` are `CalcSnapshot` instead of `CalcSide`
//    * the view model's global toggles come from `FieldSnapshot`
//    * it returns the numeric `CalcOutcome`; the display fields
//      (`effectivenessLabel`, `effectivenessColor`, `hitsToKO` text) stay in
//      the view model, since `Color` has no business in a solver
//
//  Every modifier is read in the same order and combined with the same
//  operations as before. If a number moves, that's a bug, not a refactor —
//  see `CalcEngineParityTests`, which runs both paths over the same inputs.
//
//  Scope: the legacy engine only. The Champions/Showdown path still lives on
//  `DamageCalcVM` because the vendored port's types (`ShowdownPokemon`,
//  `ShowdownField`, `ShowdownGen0`, …) are main-actor-isolated by the module
//  default and have to be opened up before that pipeline can be called from
//  here. That's the next step, and it's what the EV solver needs for
//  Champions matchups.
//

import Foundation

nonisolated enum CalcEngine {

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
