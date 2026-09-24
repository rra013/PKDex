//
//  CalcSnapshot.swift
//  PKDex
//
//  Sendable, main-actor-free value types describing a damage-calc matchup.
//
//  Why this exists: `CalcSide` is a reference type holding a `PKMNStats`
//  SwiftData model, and `DamageCalcVM` is `@MainActor`, so nothing about the
//  current calc can leave the main actor or be handed to a test without a
//  view model. That's fine for the calc screen — it recomputes a handful of
//  results per render — but it blocks the EV solver, whose combined defensive
//  solve sweeps a 64 x 64 grid of (HP, Def) values and needs thousands of
//  evaluations off the main thread.
//
//  Every type here is explicitly `nonisolated` for the same reason as
//  `ShowdownPaste.swift`: the module builds with `MainActor` default
//  isolation, which would otherwise pin even these pure structs.
//
//  Design note — snapshots hold *raw* inputs (base stats, EVs, IVs, nature,
//  stat stages), not finished stat totals. The solver's whole job is to vary
//  an EV and recompute, so it needs the inputs and the same stat formula the
//  UI uses. `atk` / `def` / ... below deliberately mirror `CalcSide`'s
//  accessors line for line, calling the same global `calcStat` / `calcHP` /
//  `statStageMultiplier`, so the two can't drift.
//
//  Phase 2.1a: these types and the `snapshot()` conversions only. Nothing
//  reads them yet — `evaluate()` and the `DamageCalcVM` delegation land in
//  2.1b, gated on parity tests.
//

import Foundation

// MARK: - Species

/// The species facts the damage formula needs, flattened off `PKMNStats` so
/// no SwiftData model crosses an isolation boundary.
nonisolated struct SpeciesSnapshot: Equatable, Sendable {
    var name: String
    var type1: String
    var type2: String?
    var baseHP: Int
    var baseAtk: Int
    var baseDef: Int
    var baseSpAtk: Int
    var baseSpDef: Int
    var baseSpeed: Int

    var types: [String] { [type1] + [type2].compactMap { $0 } }
}

// MARK: - Move

/// The move facts the damage formula needs, flattened off `MoveData`.
nonisolated struct MoveSnapshot: Equatable, Sendable, Identifiable {
    var id: Int
    var name: String
    var type: String
    /// "physical", "special" or "status".
    var damageClass: String
    var power: Int?
    var makesContact: Bool

    var isPhysical: Bool { damageClass == "physical" }
    var isStatus: Bool { damageClass == "status" }
}

// MARK: - Side

/// One side of a matchup: species, set, and the per-Pokemon / per-side
/// conditions the calc reads. Mirrors the damage-relevant surface of
/// `CalcSide`.
nonisolated struct CalcSnapshot: Equatable, Sendable {
    // Species & set
    var species: SpeciesSnapshot
    /// Resolved Mega form when one is active, else nil. Resolving happens at
    /// snapshot time (it needs the held item and move slots), so the solver
    /// never has to re-derive it.
    var megaForm: MegaForm?
    var nature: Nature
    var level: Int
    var selectedAbility: String?
    var heldItem: HeldItem
    var moves: [MoveSnapshot]

    /// Champions 0–32 stat-point scale rather than mainline 0–252 EVs.
    var championsMode: Bool
    var evHP = 0, evAtk = 0, evDef = 0, evSpAtk = 0, evSpDef = 0, evSpeed = 0
    var ivHP = 31, ivAtk = 31, ivDef = 31, ivSpAtk = 31, ivSpDef = 31, ivSpeed = 31
    var atkStage = 0, defStage = 0, spAtkStage = 0, spDefStage = 0, speedStage = 0

    // Per-Pokemon conditions
    var atFullHP = true
    var status: ShowdownStatus = .none
    var currentHPPercent = 100
    var abilityOn = false

    // Side conditions — defending
    var isReflect = false
    var isLightScreen = false
    var isAuroraVeil = false
    var isFriendGuard = false
    var isProtected = false
    var isStealthRock = false
    var spikesLayers = 0

    // Side conditions — attacking
    var isHelpingHand = false
    var isTailwind = false

    // MARK: Effective state (Mega-aware)
    //
    // These mirror `CalcSide`'s `effective*` accessors. Same precedence, same
    // fallbacks — a Mega's ability/typing/stats win while active, and a
    // stone-based Mega reads as item-less because the stone is consumed.

    var effectiveAbility: String? { megaForm?.ability ?? selectedAbility }

    var effectiveTypes: [String] {
        if let m = megaForm {
            return [m.type1] + [m.type2].compactMap { $0 }
        }
        return species.types
    }

    /// Kept under the same name `CalcSide` uses so call sites read alike.
    var types: [String] { effectiveTypes }

    var effectiveBaseAtk: Int   { megaForm?.baseAtk   ?? species.baseAtk }
    var effectiveBaseDef: Int   { megaForm?.baseDef   ?? species.baseDef }
    var effectiveBaseSpAtk: Int { megaForm?.baseSpAtk ?? species.baseSpAtk }
    var effectiveBaseSpDef: Int { megaForm?.baseSpDef ?? species.baseSpDef }
    var effectiveBaseSpeed: Int { megaForm?.baseSpeed ?? species.baseSpeed }

    var effectiveDisplayName: String { megaForm?.displayName ?? species.name }

    var effectiveHeldItem: HeldItem {
        if let m = megaForm, m.stone != nil { return .none }
        return heldItem
    }

    // MARK: Stat math
    //
    // Champions stores EVs on the 0–32 scale and pins IVs at 31, so both are
    // funnelled through the same translation `CalcSide` uses before they hit
    // the mainline formula.

    private func formulaEV(_ stored: Int) -> Int {
        championsMode ? championsEVToMain(stored) : stored
    }

    private func formulaIV(_ stored: Int) -> Int {
        championsMode ? 31 : stored
    }

    var hp: Int {
        calcHP(base: species.baseHP, iv: formulaIV(ivHP),
               ev: formulaEV(evHP), level: level)
    }

    /// Current HP when below full, as the same percentage-of-max conversion
    /// the Champions bridge uses. nil at full HP.
    var currentHP: Int? {
        let pct = max(1, min(100, currentHPPercent))
        return pct >= 100 ? nil : max(1, hp * pct / 100)
    }

    var atk: Int { stat(.atk) }
    var def: Int { stat(.def) }
    var spAtk: Int { stat(.spAtk) }
    var spDef: Int { stat(.spDef) }
    var speed: Int { stat(.speed) }

    /// Shared body for the five non-HP stats. `CalcSide` spells these out one
    /// by one; collapsing them here keeps the EV/IV/stage/nature wiring in a
    /// single place for the solver to reason about.
    private func stat(_ key: Nature.StatKey) -> Int {
        let base: Int
        let iv: Int
        let ev: Int
        let stage: Int
        switch key {
        case .atk:   base = effectiveBaseAtk;   iv = ivAtk;   ev = evAtk;   stage = atkStage
        case .def:   base = effectiveBaseDef;   iv = ivDef;   ev = evDef;   stage = defStage
        case .spAtk: base = effectiveBaseSpAtk; iv = ivSpAtk; ev = evSpAtk; stage = spAtkStage
        case .spDef: base = effectiveBaseSpDef; iv = ivSpDef; ev = evSpDef; stage = spDefStage
        case .speed: base = effectiveBaseSpeed; iv = ivSpeed; ev = evSpeed; stage = speedStage
        }
        let raw = calcStat(base: base, iv: formulaIV(iv), ev: formulaEV(ev),
                           level: level, natureMod: nature.modifier(for: key))
        return Int(Double(raw) * statStageMultiplier(stage: stage))
    }

    // MARK: Solver support

    /// Returns a copy with one EV changed. The solver's inner loop — kept
    /// here so it can't disagree with the stat accessors above.
    func settingEV(_ key: Nature.StatKey, to value: Int) -> CalcSnapshot {
        var copy = self
        switch key {
        case .atk:   copy.evAtk = value
        case .def:   copy.evDef = value
        case .spAtk: copy.evSpAtk = value
        case .spDef: copy.evSpDef = value
        case .speed: copy.evSpeed = value
        }
        return copy
    }

    /// HP has no `Nature.StatKey` case (no nature affects it), so it needs
    /// its own setter.
    func settingHPEV(to value: Int) -> CalcSnapshot {
        var copy = self
        copy.evHP = value
        return copy
    }

    /// The EV values worth trying for one stat, cheapest first.
    ///
    /// Only multiples of 4 change a mainline stat (the formula divides EVs by
    /// 4), so the mainline domain is 64 points rather than 253; Champions
    /// points are 0–32 and all meaningful. That's what makes an exhaustive
    /// scan viable and lets the solver skip monotonicity assumptions
    /// entirely.
    var evDomain: [Int] {
        championsMode
            ? Array(0...championsMaxEVPerStat)
            : Array(stride(from: 0, through: maxEVPerStat, by: 4))
    }

    var evPerStatMax: Int { championsMode ? championsMaxEVPerStat : maxEVPerStat }
    var evTotalMax: Int { championsMode ? championsMaxTotalEVs : maxTotalEVs }
    var totalEVs: Int { evHP + evAtk + evDef + evSpAtk + evSpDef + evSpeed }
}

// MARK: - Field

/// Global field state — the modifiers `DamageCalcVM` holds outside either
/// side.
nonisolated struct FieldSnapshot: Equatable, Sendable {
    var weather: WeatherCondition = .none
    var terrain: TerrainCondition = .none
    var crit = false
    var burn = false
    /// Spread move (doubles), which halves damage.
    var multi = false
    var glaiveRush = false
    var zMoveBypass = false
    var miscMultiplier: Double = 1.0
    var gravity = false
    var wonderRoom = false
    var magicRoom = false
}

// MARK: - Outcome

/// The result of one evaluation, as numbers rather than display strings.
///
/// `MoveResult` exists for the UI and carries a `hitsToKO` *String* plus
/// SwiftUI `Color`s, neither of which a solver can compare. This is the
/// numeric equivalent; `MoveResult` will be derived from it in 2.1b.
nonisolated struct CalcOutcome: Equatable, Sendable {
    /// Damage floor and ceiling. `Double` rather than `Int` to match the
    /// engines' own arithmetic exactly — both paths `floor()` a Double product
    /// and the legacy path never rounds to an integer.
    var damageMin: Double
    var damageMax: Double
    /// Defender's max HP, so percentages are derivable without the side.
    var defenderHP: Int
    var effectiveness: Double
    var isSTAB: Bool
    /// Per-roll damage, when the engine exposes it.
    ///
    /// Only the Showdown port produces real rolls (its `.rolls` case); the
    /// legacy engine computes a min/max pair and nothing in between. So
    /// roll-granularity constraints ("KOs on 15 of 16") are available on the
    /// Champions path only, and the solver has to fall back to the
    /// guaranteed-KO / guaranteed-survival predicates elsewhere.
    var rolls: [Int]?
    /// The defender's HP before this hit, when it isn't at full. nil means
    /// full HP, so outcomes built without it behave exactly as before.
    var defenderCurrentHP: Int? = nil

    /// HP the hit has to get through: current HP when known, else max HP.
    /// Percentages stay relative to max HP, as the calc displays them; only
    /// the KO / survival checks use this.
    var hpBeforeHit: Int { defenderCurrentHP ?? defenderHP }

    var minPercent: Double {
        defenderHP > 0 ? min(damageMin / Double(defenderHP) * 100, 999) : 0
    }
    var maxPercent: Double {
        defenderHP > 0 ? min(damageMax / Double(defenderHP) * 100, 999) : 0
    }

    /// True when even the lowest roll KOs from the defender's current HP.
    var isGuaranteedOHKO: Bool {
        hpBeforeHit > 0 && damageMin >= Double(hpBeforeHit)
    }
    /// True when even the highest roll leaves the defender standing.
    var isGuaranteedSurvival: Bool {
        hpBeforeHit > 0 && damageMax < Double(hpBeforeHit)
    }

    /// Fraction of rolls that KO from current HP. nil without rolls.
    var ohkoChance: Double? {
        guard let rolls, !rolls.isEmpty, hpBeforeHit > 0 else { return nil }
        return Double(rolls.filter { $0 >= hpBeforeHit }.count) / Double(rolls.count)
    }

    /// The hit-count label the calc UI displays, e.g. "2HKO" or "2-3HKO".
    /// Reproduces the existing formatting exactly, percentages and all, so
    /// moving it out of the view model can't change what's on screen.
    var hitsToKOText: String {
        let maxPct = maxPercent
        let minPct = minPercent
        guard maxPct > 0 else { return "--" }
        let minHits = Int(ceil(100.0 / maxPct))
        let maxHits = minPct > 0 ? Int(ceil(100.0 / minPct)) : 0
        if minHits == maxHits { return "\(minHits)HKO" }
        return "\(minHits)-\(maxHits)HKO"
    }
}

// MARK: - Snapshotting

extension MoveData {
    /// Flattens this SwiftData model into a `Sendable` value.
    @MainActor
    func snapshot() -> MoveSnapshot {
        MoveSnapshot(id: id, name: name, type: type, damageClass: damageClass,
                     power: power, makesContact: makesContact)
    }
}

extension PKMNStats {
    @MainActor
    func speciesSnapshot() -> SpeciesSnapshot {
        SpeciesSnapshot(name: name, type1: type1, type2: type2,
                        baseHP: baseHP, baseAtk: baseAtk, baseDef: baseDef,
                        baseSpAtk: baseSpAtk, baseSpDef: baseSpDef,
                        baseSpeed: baseSpeed)
    }
}

extension CalcSide {
    /// Captures this side as a `Sendable` value.
    ///
    /// Returns nil when no species is selected — the calc UI tolerates an
    /// empty side (every stat falls back to 1), but there's nothing
    /// meaningful to solve against, so the solver requires a real species
    /// rather than silently working on a phantom 1/1/1 statline.
    ///
    /// `megaActive` is resolved through `activeMegaForm` here, so the
    /// snapshot already reflects whether the Mega prerequisites hold.
    @MainActor
    func snapshot() -> CalcSnapshot? {
        guard let pokemon else { return nil }
        return CalcSnapshot(
            species: pokemon.speciesSnapshot(),
            megaForm: activeMegaForm,
            nature: nature,
            level: level,
            selectedAbility: selectedAbility,
            heldItem: heldItem,
            moves: moves.compactMap { $0?.snapshot() },
            championsMode: championsMode,
            evHP: evHP, evAtk: evAtk, evDef: evDef,
            evSpAtk: evSpAtk, evSpDef: evSpDef, evSpeed: evSpeed,
            ivHP: ivHP, ivAtk: ivAtk, ivDef: ivDef,
            ivSpAtk: ivSpAtk, ivSpDef: ivSpDef, ivSpeed: ivSpeed,
            atkStage: atkStage, defStage: defStage,
            spAtkStage: spAtkStage, spDefStage: spDefStage, speedStage: speedStage,
            atFullHP: atFullHP,
            status: status,
            currentHPPercent: currentHPPercent,
            abilityOn: abilityOn,
            isReflect: isReflect,
            isLightScreen: isLightScreen,
            isAuroraVeil: isAuroraVeil,
            isFriendGuard: isFriendGuard,
            isProtected: isProtected,
            isStealthRock: isStealthRock,
            spikesLayers: spikesLayers,
            isHelpingHand: isHelpingHand,
            isTailwind: isTailwind
        )
    }
}

extension DamageCalcVM {
    /// Captures the global field state as a `Sendable` value.
    @MainActor
    func fieldSnapshot() -> FieldSnapshot {
        FieldSnapshot(
            weather: weather,
            terrain: terrain,
            crit: crit,
            burn: burn,
            multi: multi,
            glaiveRush: glaiveRush,
            zMoveBypass: zMoveBypass,
            miscMultiplier: miscMultiplier,
            gravity: gravity,
            wonderRoom: wonderRoom,
            magicRoom: magicRoom
        )
    }
}
