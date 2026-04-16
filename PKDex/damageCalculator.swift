//
//  damageCalculator.swift
//  PKDex
//
//  Created by Rishi Anand on 4/14/26.
//

import SwiftUI
import SwiftData

// MARK: - Data

let allTypes = ["Normal","Fire","Water","Electric","Grass","Ice","Fighting","Poison",
                "Ground","Flying","Psychic","Bug","Rock","Ghost","Dragon","Dark","Steel","Fairy"]

let typeEffectivenessChart: [String: [String: Double]] = [
    "Normal":   ["Rock": 0.5, "Ghost": 0, "Steel": 0.5],
    "Fire":     ["Fire": 0.5, "Water": 0.5, "Grass": 2, "Ice": 2, "Bug": 2, "Rock": 0.5, "Dragon": 0.5, "Steel": 2],
    "Water":    ["Fire": 2, "Water": 0.5, "Grass": 0.5, "Ground": 2, "Rock": 2, "Dragon": 0.5],
    "Electric": ["Water": 2, "Electric": 0.5, "Grass": 0.5, "Ground": 0, "Flying": 2, "Dragon": 0.5],
    "Grass":    ["Fire": 0.5, "Water": 2, "Grass": 0.5, "Poison": 0.5, "Ground": 2, "Flying": 0.5, "Bug": 0.5, "Rock": 2, "Dragon": 0.5, "Steel": 0.5],
    "Ice":      ["Water": 0.5, "Grass": 2, "Ice": 0.5, "Ground": 2, "Flying": 2, "Dragon": 2, "Steel": 0.5],
    "Fighting": ["Normal": 2, "Ice": 2, "Poison": 0.5, "Flying": 0.5, "Psychic": 0.5, "Bug": 0.5, "Rock": 2, "Ghost": 0, "Dark": 2, "Steel": 2, "Fairy": 0.5],
    "Poison":   ["Grass": 2, "Poison": 0.5, "Ground": 0.5, "Rock": 0.5, "Ghost": 0.5, "Steel": 0, "Fairy": 2],
    "Ground":   ["Fire": 2, "Electric": 2, "Grass": 0.5, "Poison": 2, "Flying": 0, "Bug": 0.5, "Rock": 2, "Steel": 2],
    "Flying":   ["Electric": 0.5, "Grass": 2, "Fighting": 2, "Bug": 2, "Rock": 0.5, "Steel": 0.5],
    "Psychic":  ["Fighting": 2, "Poison": 2, "Psychic": 0.5, "Dark": 0, "Steel": 0.5],
    "Bug":      ["Fire": 0.5, "Grass": 2, "Fighting": 0.5, "Flying": 0.5, "Psychic": 2, "Ghost": 0.5, "Dark": 2, "Steel": 0.5, "Fairy": 0.5],
    "Rock":     ["Fire": 2, "Ice": 2, "Fighting": 0.5, "Ground": 0.5, "Flying": 2, "Bug": 2, "Steel": 0.5],
    "Ghost":    ["Normal": 0, "Psychic": 2, "Ghost": 2, "Dark": 0.5],
    "Dragon":   ["Dragon": 2, "Steel": 0.5, "Fairy": 0],
    "Dark":     ["Fighting": 0.5, "Psychic": 2, "Ghost": 2, "Dark": 0.5, "Fairy": 0.5],
    "Steel":    ["Fire": 0.5, "Water": 0.5, "Electric": 0.5, "Ice": 2, "Rock": 2, "Steel": 0.5, "Fairy": 2],
    "Fairy":    ["Fire": 0.5, "Fighting": 2, "Poison": 0.5, "Dragon": 2, "Dark": 2, "Steel": 0.5]
]

// MARK: - Damage Engine (Gen V+ formula)

private func pokeFloor(_ value: Int, _ modifier: Double) -> Int {
    if modifier == 1.0 { return value }
    return Int(floor(Double(value) * modifier))
}

func calcDamageRange(
    level: Int, movePower: Int, userAtk: Int, defenderDef: Int,
    multi: Bool, parentalBond: Bool,
    weatherMult: Double, glaiveRush: Bool,
    crit: Bool, critMultiplier: Double,
    stabBonus: Double, typeEffect: Double,
    burnReduction: Double, abilityMods: AbilityModResult,
    zMoveBypass: Bool
) -> (min: Double, max: Double) {
    guard movePower > 0 && userAtk > 0 && defenderDef > 0 else { return (0, 0) }

    let effectiveAtk = Int(floor(Double(userAtk) * abilityMods.atkMultiplier))
    let effectiveDef = Int(floor(Double(defenderDef) * abilityMods.defMultiplier))
    let effectivePower = Int(floor(Double(movePower) * abilityMods.powerMultiplier))

    let scaledLevel = (2 * level / 5) + 2
    var base = scaledLevel * effectivePower * effectiveAtk / max(effectiveDef, 1)
    base = base / 50 + 2

    if multi        { base = pokeFloor(base, 0.75) }
    if parentalBond { base = pokeFloor(base, 1.25) }
    base = pokeFloor(base, weatherMult)
    if glaiveRush   { base = pokeFloor(base, 2.0) }
    if crit         { base = pokeFloor(base, abilityMods.critMultiplierOverride ?? critMultiplier) }

    let minBase = base * 85 / 100
    let maxBase = base

    func applyPostRandom(_ d: Int) -> Int {
        var v = d
        v = pokeFloor(v, abilityMods.stabOverride ?? stabBonus)
        v = pokeFloor(v, abilityMods.typeEffOverride ?? typeEffect)
        v = pokeFloor(v, burnReduction)
        v = pokeFloor(v, abilityMods.finalMultiplier)
        if zMoveBypass { v = pokeFloor(v, 0.25) }
        return v
    }

    return (Double(applyPostRandom(minBase)), Double(applyPostRandom(maxBase)))
}

func computeTypeEffectiveness(moveType: String, defenderTypes: [String]) -> Double {
    var mult = 1.0
    let chart = typeEffectivenessChart[moveType] ?? [:]
    for dt in defenderTypes {
        mult *= chart[dt] ?? 1.0
    }
    return mult
}

// MARK: - Side Model

@Observable
class CalcSide {
    var pokemon: PKMNStats?
    var searchText: String = ""
    var nature: Nature = allNatures.first(where: { $0.id == "adamant" })!
    var level: Int = 50
    var selectedAbility: String?
    var heldItem: HeldItem = .none
    var atFullHP: Bool = true
    var loadedSpreadName: String?

    // Moves (4 slots)
    var moves: [MoveData?] = [nil, nil, nil, nil]
    var moveSearchTexts: [String] = ["", "", "", ""]
    var filterLegalMoves: Bool = true

    /// When true, EVs use the Champions 0-32 scale and IVs are fixed at 31.
    var championsMode: Bool = false

    var evHP: Int = 0
    var evAtk: Int = 0
    var evDef: Int = 0
    var evSpAtk: Int = 0
    var evSpDef: Int = 0
    var evSpeed: Int = 0

    var ivHP: Int = 31
    var ivAtk: Int = 31
    var ivDef: Int = 31
    var ivSpAtk: Int = 31
    var ivSpDef: Int = 31
    var ivSpeed: Int = 31

    var atkStage: Int = 0
    var defStage: Int = 0
    var spAtkStage: Int = 0
    var spDefStage: Int = 0
    var speedStage: Int = 0

    var evPerStatMax: Int { championsMode ? championsMaxEVPerStat : maxEVPerStat }
    var evTotalMax: Int { championsMode ? championsMaxTotalEVs : maxTotalEVs }
    var totalEVs: Int { evHP + evAtk + evDef + evSpAtk + evSpDef + evSpeed }

    func maxAllowedEV(excluding current: Int) -> Int {
        let othersTotal = totalEVs - current
        return min(evPerStatMax, max(0, evTotalMax - othersTotal))
    }

    func cappedEVBinding(_ kp: ReferenceWritableKeyPath<CalcSide, Int>) -> Binding<Int> {
        Binding(
            get: { self[keyPath: kp] },
            set: { newVal in
                let cap = self.maxAllowedEV(excluding: self[keyPath: kp])
                self[keyPath: kp] = max(0, min(newVal, cap))
            }
        )
    }

    // MARK: - Save / Load Spreads

    func toSavedSpread(name: String) -> SavedSpread {
        SavedSpread(
            name: name,
            pokemonID: pokemon?.id,
            pokemonName: pokemon?.name,
            abilityName: selectedAbility,
            itemRawValue: heldItem != .none ? heldItem.rawValue : nil,
            championsMode: championsMode,
            natureID: nature.id,
            level: level,
            evHP: evHP, evAtk: evAtk, evDef: evDef,
            evSpAtk: evSpAtk, evSpDef: evSpDef, evSpeed: evSpeed,
            ivHP: ivHP, ivAtk: ivAtk, ivDef: ivDef,
            ivSpAtk: ivSpAtk, ivSpDef: ivSpDef, ivSpeed: ivSpeed,
            moveID1: moves[0]?.id, moveID2: moves[1]?.id,
            moveID3: moves[2]?.id, moveID4: moves[3]?.id
        )
    }

    func loadSpread(_ spread: SavedSpread, allPokemon: [PKMNStats], allMoves: [MoveData]) {
        if let pid = spread.pokemonID {
            if let match = allPokemon.first(where: { $0.id == pid }) {
                pokemon = match
            }
        }
        selectedAbility = spread.abilityName
        heldItem = spread.itemRawValue.flatMap { HeldItem(rawValue: $0) } ?? .none
        championsMode = spread.championsMode
        nature = allNatures.first(where: { $0.id == spread.natureID }) ?? allNatures[0]
        level = spread.level
        evHP = spread.evHP; evAtk = spread.evAtk; evDef = spread.evDef
        evSpAtk = spread.evSpAtk; evSpDef = spread.evSpDef; evSpeed = spread.evSpeed
        ivHP = spread.ivHP; ivAtk = spread.ivAtk; ivDef = spread.ivDef
        ivSpAtk = spread.ivSpAtk; ivSpDef = spread.ivSpDef; ivSpeed = spread.ivSpeed

        let moveIDs = [spread.moveID1, spread.moveID2, spread.moveID3, spread.moveID4]
        for i in 0..<4 {
            if let mid = moveIDs[i] {
                moves[i] = allMoves.first(where: { $0.id == mid })
            } else {
                moves[i] = nil
            }
            moveSearchTexts[i] = ""
        }

        loadedSpreadName = spread.name
    }

    private func formulaEV(_ stored: Int) -> Int {
        championsMode ? championsEVToMain(stored) : stored
    }

    private func formulaIV(_ stored: Int) -> Int {
        championsMode ? 31 : stored
    }

    func setChampionsMode(_ on: Bool) {
        guard on != championsMode else { return }
        if on {
            evHP    = evHP * 32 / 252
            evAtk   = evAtk * 32 / 252
            evDef   = evDef * 32 / 252
            evSpAtk = evSpAtk * 32 / 252
            evSpDef = evSpDef * 32 / 252
            evSpeed = evSpeed * 32 / 252
            ivHP = 31; ivAtk = 31; ivDef = 31
            ivSpAtk = 31; ivSpDef = 31; ivSpeed = 31
            championsMode = true
        } else {
            evHP    = championsEVToMain(evHP)
            evAtk   = championsEVToMain(evAtk)
            evDef   = championsEVToMain(evDef)
            evSpAtk = championsEVToMain(evSpAtk)
            evSpDef = championsEVToMain(evSpDef)
            evSpeed = championsEVToMain(evSpeed)
            championsMode = false
        }
    }

    var types: [String] {
        guard let p = pokemon else { return ["Normal"] }
        var t = [p.type1]
        if let t2 = p.type2 { t.append(t2) }
        return t
    }

    var hp: Int {
        guard let p = pokemon else { return 1 }
        return calcHP(base: p.baseHP, iv: formulaIV(ivHP), ev: formulaEV(evHP), level: level)
    }
    var atk: Int {
        guard let p = pokemon else { return 1 }
        return Int(Double(calcStat(base: p.baseAtk, iv: formulaIV(ivAtk), ev: formulaEV(evAtk), level: level, natureMod: nature.modifier(for: .atk))) * statStageMultiplier(stage: atkStage))
    }
    var def: Int {
        guard let p = pokemon else { return 1 }
        return Int(Double(calcStat(base: p.baseDef, iv: formulaIV(ivDef), ev: formulaEV(evDef), level: level, natureMod: nature.modifier(for: .def))) * statStageMultiplier(stage: defStage))
    }
    var spAtk: Int {
        guard let p = pokemon else { return 1 }
        return Int(Double(calcStat(base: p.baseSpAtk, iv: formulaIV(ivSpAtk), ev: formulaEV(evSpAtk), level: level, natureMod: nature.modifier(for: .spAtk))) * statStageMultiplier(stage: spAtkStage))
    }
    var spDef: Int {
        guard let p = pokemon else { return 1 }
        return Int(Double(calcStat(base: p.baseSpDef, iv: formulaIV(ivSpDef), ev: formulaEV(evSpDef), level: level, natureMod: nature.modifier(for: .spDef))) * statStageMultiplier(stage: spDefStage))
    }
    var speed: Int {
        guard let p = pokemon else { return 1 }
        return Int(Double(calcStat(base: p.baseSpeed, iv: formulaIV(ivSpeed), ev: formulaEV(evSpeed), level: level, natureMod: nature.modifier(for: .speed))) * statStageMultiplier(stage: speedStage))
    }
}

// MARK: - Per-Move Result

struct MoveResult: Identifiable {
    let id = UUID()
    let move: MoveData
    let damageMin: Double
    let damageMax: Double
    let minPercent: Double
    let maxPercent: Double
    let hitsToKO: String
    let effectiveness: Double
    let effectivenessLabel: String
    let effectivenessColor: Color
    let isSTAB: Bool
}

// MARK: - View Model

@MainActor
@Observable
class DamageCalcVM {
    var side1 = CalcSide()
    var side2 = CalcSide()

    // Global modifiers
    var crit: Bool = false
    var burn: Bool = false
    var multi: Bool = false
    var parentalBond: Bool = false
    var glaiveRush: Bool = false
    var zMoveBypass: Bool = false
    var weather: WeatherCondition = .none
    var miscMultiplier: Double = 1.0

    // MARK: Computed Results

    var side1Results: [MoveResult] {
        computeResults(attacker: side1, defender: side2)
    }

    var side2Results: [MoveResult] {
        computeResults(attacker: side2, defender: side1)
    }

    private func computeResults(attacker: CalcSide, defender: CalcSide) -> [MoveResult] {
        attacker.moves.compactMap { $0 }.map { move in
            computeSingleResult(move: move, attacker: attacker, defender: defender)
        }
    }

    private func computeSingleResult(move: MoveData, attacker: CalcSide, defender: CalcSide) -> MoveResult {
        let moveType = move.type
        let movePower = move.power ?? 0
        let isPhysical = move.damageClass == "physical"
        let isContact = move.makesContact
        let stab = attacker.types.contains(moveType)
        let stabBonus = stab ? 1.5 : 1.0
        let burnReduction = (burn && isPhysical) ? 0.5 : 1.0
        let typeEff = computeTypeEffectiveness(moveType: moveType, defenderTypes: defender.types)
        let weatherMult = weather.moveDamageMultiplier(moveType: moveType)

        let itemMods = computeItemModifiers(
            attackerItem: attacker.heldItem,
            defenderItem: defender.heldItem,
            isPhysical: isPhysical,
            typeEffectiveness: typeEff,
            moveType: moveType
        )

        let abilityMods = computeAbilityModifiers(
            attackerAbility: attacker.selectedAbility,
            defenderAbility: defender.selectedAbility,
            moveType: moveType,
            movePower: movePower,
            isPhysical: isPhysical,
            isContact: isContact,
            isSTAB: stab,
            typeEffectiveness: typeEff,
            weather: weather,
            attackerAtFullHP: attacker.atFullHP,
            defenderAtFullHP: defender.atFullHP
        )

        let baseAtk = isPhysical ? attacker.atk : attacker.spAtk
        let itemAtkMult = isPhysical ? itemMods.atkMultiplier : itemMods.spAtkMultiplier
        let effectiveAtk = Int(floor(Double(baseAtk) * itemAtkMult))

        let effectiveDef: Int
        if isPhysical {
            let snowMult = weather.snowDefMultiplier(defenderTypes: defender.types)
            effectiveDef = Int(floor(Double(defender.def) * snowMult * itemMods.defMultiplier))
        } else {
            let sandMult = weather.sandSpDefMultiplier(defenderTypes: defender.types)
            effectiveDef = Int(floor(Double(defender.spDef) * sandMult * itemMods.spDefMultiplier))
        }

        let raw = calcDamageRange(
            level: attacker.level, movePower: movePower,
            userAtk: effectiveAtk, defenderDef: effectiveDef,
            multi: multi, parentalBond: parentalBond,
            weatherMult: weatherMult, glaiveRush: glaiveRush,
            crit: crit, critMultiplier: 1.5,
            stabBonus: stabBonus, typeEffect: typeEff,
            burnReduction: burnReduction, abilityMods: abilityMods,
            zMoveBypass: zMoveBypass
        )

        let im = itemMods.damageMult
        let dMin = floor(raw.min * im)
        let dMax = floor(raw.max * im)
        let minPct = defender.hp > 0 ? min(dMin / Double(defender.hp) * 100, 999) : 0
        let maxPct = defender.hp > 0 ? min(dMax / Double(defender.hp) * 100, 999) : 0

        let hitsToKO: String = {
            guard maxPct > 0 else { return "--" }
            let minHits = Int(ceil(100.0 / maxPct))
            let maxHits = minPct > 0 ? Int(ceil(100.0 / minPct)) : 0
            if minHits == maxHits { return "\(minHits)HKO" }
            return "\(minHits)-\(maxHits)HKO"
        }()

        let eff = abilityMods.typeEffOverride ?? typeEff
        let effLabel: String = {
            switch eff {
            case 0:    return "Immune"
            case 0.25: return "1/4x"
            case 0.5:  return "1/2x"
            case 1:    return "1x"
            case 2:    return "2x"
            case 4:    return "4x"
            default:   return String(format: "%.2fx", eff)
            }
        }()
        let effColor: Color = {
            switch eff {
            case 0:          return .gray
            case 0.25, 0.5:  return .blue
            case 1:          return .primary
            case 2:          return .orange
            case 4:          return .red
            default:         return .primary
            }
        }()

        // STAB is true if natural type match OR ability grants it (Protean/Libero)
        let hasSTAB = stab || abilityMods.stabOverride != nil

        return MoveResult(
            move: move,
            damageMin: dMin, damageMax: dMax,
            minPercent: minPct, maxPercent: maxPct,
            hitsToKO: hitsToKO,
            effectiveness: eff,
            effectivenessLabel: effLabel,
            effectivenessColor: effColor,
            isSTAB: hasSTAB
        )
    }

    // MARK: Move Search

    func filteredMoves(for side: CalcSide, slotIndex: Int, allMoves: [MoveData], allPokemon: [PKMNStats]) -> [MoveData] {
        let q = side.moveSearchTexts[slotIndex].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }

        var pool = allMoves
        if side.filterLegalMoves, let pkmn = side.pokemon {
            var legalIDs = Set(pkmn.learnableMoveIDs)
            if legalIDs.isEmpty {
                if let base = allPokemon.first(where: { $0.speciesID == pkmn.speciesID && !$0.isForm }) {
                    legalIDs = Set(base.learnableMoveIDs)
                }
            }
            pool = pool.filter { legalIDs.contains($0.id) }
        }
        return pool.filter { $0.name.lowercased().contains(q) }.prefix(25).map { $0 }
    }
}

// MARK: - Type Colors

let typeColorMap: [String: Color] = [
    "Normal": Color(.systemGray), "Fire": Color(.systemRed),
    "Water": Color(.systemBlue), "Electric": Color(.systemYellow),
    "Grass": Color(.systemGreen), "Ice": Color(.systemCyan),
    "Fighting": Color(.systemBrown), "Poison": Color(.systemPurple),
    "Ground": Color(.brown), "Flying": Color(.systemTeal),
    "Psychic": Color(.systemPink), "Bug": Color(.systemGreen).opacity(0.7),
    "Rock": Color(.brown).opacity(0.8), "Ghost": Color(.systemIndigo),
    "Dragon": Color(.systemIndigo).opacity(0.8), "Dark": Color(.darkGray),
    "Steel": Color(.systemGray2), "Fairy": Color(.systemPink).opacity(0.7),
]

// MARK: - Main View

struct DamageCalculatorView: View {
    @State private var vm = DamageCalcVM()
    @Query(sort: \PKMNStats.name) private var allPokemon: [PKMNStats]
    @Query(sort: \MoveData.name) private var allMoves: [MoveData]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if allPokemon.isEmpty {
                        SyncingCard()
                    } else {
                        ResultCard(vm: vm)
                        SideCard(title: "Pokemon 1", icon: "circle.fill", side: vm.side1, allPokemon: allPokemon, allMoves: allMoves, vm: vm)
                        SideCard(title: "Pokemon 2", icon: "circle.fill", side: vm.side2, allPokemon: allPokemon, allMoves: allMoves, vm: vm)
                        ModifiersCard(vm: vm)
                    }
                }
                .padding()
            }
            .navigationTitle("Damage Calc")
            .background(Color(.systemGroupedBackground))
        }
    }
}

// MARK: - Syncing Placeholder

private struct SyncingCard: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Downloading Pokemon & move data...")
                .font(.subheadline).foregroundStyle(.secondary)
            Text("This only happens once.")
                .font(.caption).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity).padding(40)
        .background(.background, in: RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Result Card

private struct ResultCard: View {
    var vm: DamageCalcVM

    var body: some View {
        CalcSection(title: "Results", icon: "bolt.fill") {
            // Active modifier badges
            HStack(spacing: 6) {
                if vm.weather != .none {
                    InfoBadge(text: vm.weather.rawValue, color: .cyan)
                }
                if vm.crit { InfoBadge(text: "Crit", color: .orange) }
                if vm.burn { InfoBadge(text: "Burn", color: .red) }
                if let a1 = vm.side1.selectedAbility, !a1.isEmpty {
                    InfoBadge(text: formatAbilityName(a1), color: .orange)
                }
                if let a2 = vm.side2.selectedAbility, !a2.isEmpty {
                    InfoBadge(text: formatAbilityName(a2), color: .purple)
                }
                if vm.side1.heldItem != .none {
                    InfoBadge(text: vm.side1.heldItem.rawValue, color: .green)
                }
                if vm.side2.heldItem != .none {
                    InfoBadge(text: vm.side2.heldItem.rawValue, color: .mint)
                }
                Spacer()
            }

            if vm.side1.pokemon != nil && vm.side2.pokemon != nil {
                DirectionResultsView(
                    attackerName: vm.side1.pokemon?.name ?? "???",
                    defenderName: vm.side2.pokemon?.name ?? "???",
                    defenderHP: vm.side2.hp,
                    results: vm.side1Results
                )

                Divider()

                DirectionResultsView(
                    attackerName: vm.side2.pokemon?.name ?? "???",
                    defenderName: vm.side1.pokemon?.name ?? "???",
                    defenderHP: vm.side1.hp,
                    results: vm.side2Results
                )
            } else {
                Text("Select two Mons to see results")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
        }
    }
}

private struct DirectionResultsView: View {
    let attackerName: String
    let defenderName: String
    let defenderHP: Int
    let results: [MoveResult]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 4) {
                Text(attackerName).font(.subheadline.bold())
                Image(systemName: "arrow.right").font(.caption).foregroundStyle(.secondary)
                Text(defenderName).font(.subheadline.bold())
                Spacer()
                Text("\(defenderHP) HP")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }

            if results.isEmpty {
                Text("No moves selected")
                    .font(.caption).foregroundStyle(.tertiary)
            } else {
                ForEach(results) { result in
                    MoveResultRow(result: result)
                }
            }
        }
    }
}

private struct MoveResultRow: View {
    let result: MoveResult

    private var isStatus: Bool { result.move.damageClass == "status" }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(result.move.name)
                    .font(.subheadline.bold())
                    .lineLimit(1)
                TypeBadge(type: result.move.type)
                DamageClassBadge(damageClass: result.move.damageClass)
                if result.isSTAB && !isStatus {
                    Text("STAB")
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .foregroundStyle(.yellow)
                        .background(Color.yellow.opacity(0.2), in: Capsule())
                }
                Spacer()
                if !isStatus {
                    Text(result.effectivenessLabel)
                        .font(.caption.bold())
                        .foregroundStyle(result.effectivenessColor)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(result.effectivenessColor.opacity(0.15), in: Capsule())
                    Text(result.hitsToKO)
                        .font(.caption.bold())
                        .foregroundStyle(.red)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.red.opacity(0.15), in: Capsule())
                }
            }

            if isStatus {
                Text("Status move — no damage")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                HStack(spacing: 4) {
                    Text("\(String(format: "%.0f", result.damageMin))-\(String(format: "%.0f", result.damageMax))")
                        .font(.caption.monospacedDigit())
                    Text("(\(String(format: "%.1f", result.minPercent))% - \(String(format: "%.1f", result.maxPercent))%)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Spacer()
                }

                PercentageBar(minPct: result.minPercent, maxPct: result.maxPercent)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct InfoBadge: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text)
            .font(.caption2.bold())
            .padding(.horizontal, 6).padding(.vertical, 2)
            .foregroundStyle(color)
            .background(color.opacity(0.15), in: Capsule())
    }
}

private struct PercentageBar: View {
    let minPct: Double
    let maxPct: Double
    private func barColor(_ pct: Double) -> Color {
        if pct >= 100 { return .red }
        if pct >= 50  { return .orange }
        return .green
    }
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color(.systemFill)).frame(height: 10)
                let w = geo.size.width
                let minX = min(minPct / 100 * w, w)
                let maxX = min(maxPct / 100 * w, w)
                Capsule()
                    .fill(LinearGradient(colors: [barColor(minPct), barColor(maxPct)],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(maxX, 8), height: 10)
                RoundedRectangle(cornerRadius: 2)
                    .fill(.white).frame(width: 3, height: 14)
                    .offset(x: max(minX - 1.5, 0))
            }
        }
        .frame(height: 14)
    }
}

// MARK: - Pokemon Side Card

private struct SideCard: View {
    let title: String
    let icon: String
    @Bindable var side: CalcSide
    let allPokemon: [PKMNStats]
    let allMoves: [MoveData]
    var vm: DamageCalcVM

    @Query(sort: \SavedSpread.createdAt, order: .reverse) private var savedSpreads: [SavedSpread]
    @Environment(\.modelContext) private var modelContext
    @State private var showSaveSheet = false
    @State private var showLoadSheet = false

    private var filteredPokemon: [PKMNStats] {
        let q = side.searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }
        return allPokemon.filter { $0.name.lowercased().contains(q) || String($0.id).contains(q) }.prefix(20).map { $0 }
    }

    var body: some View {
        CalcSection(title: title, icon: icon) {
            // Pokemon Picker
            VStack(alignment: .leading, spacing: 8) {
                if let p = side.pokemon {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.name).font(.title3.bold())
                            if p.isForm, let form = p.formName {
                                Text(form.split(separator: "-").map { $0.capitalized }.joined(separator: " "))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        TypeBadge(type: p.type1)
                        if let t2 = p.type2 { TypeBadge(type: t2) }
                        Button { side.pokemon = nil; side.searchText = ""; side.selectedAbility = nil } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                    }

                    HStack(spacing: 12) {
                        StatMini(label: "HP", value: p.baseHP)
                        StatMini(label: "Atk", value: p.baseAtk)
                        StatMini(label: "Def", value: p.baseDef)
                        StatMini(label: "SpA", value: p.baseSpAtk)
                        StatMini(label: "SpD", value: p.baseSpDef)
                        StatMini(label: "Spe", value: p.baseSpeed)
                    }
                    .font(.caption2)
                } else {
                    TextField("Search Mons...", text: $side.searchText)
                        .textFieldStyle(.roundedBorder)

                    if !filteredPokemon.isEmpty {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(filteredPokemon) { p in
                                    Button {
                                        side.pokemon = p
                                        side.searchText = ""
                                        side.selectedAbility = p.ability1
                                        side.moves = [nil, nil, nil, nil]
                                        side.moveSearchTexts = ["", "", "", ""]
                                        side.loadedSpreadName = nil
                                    } label: {
                                        HStack {
                                            Text("#\(p.id)").foregroundStyle(.secondary).frame(width: 44, alignment: .leading)
                                            Text(p.name)
                                            Spacer()
                                            TypeBadge(type: p.type1)
                                            if let t2 = p.type2 { TypeBadge(type: t2) }
                                        }
                                        .padding(.vertical, 6).padding(.horizontal, 8)
                                    }
                                    .buttonStyle(.plain)
                                    Divider()
                                }
                            }
                        }
                        .frame(maxHeight: 200)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }

            // Moves section
            if side.pokemon != nil {
                Divider()
                MoveSlotsSection(side: side, allMoves: allMoves, allPokemon: allPokemon, vm: vm)
            }

            // Save / Load Spreads
            Divider()
            if let spreadName = side.loadedSpreadName {
                HStack(spacing: 6) {
                    Image(systemName: "bookmark.fill")
                        .font(.caption2).foregroundStyle(.red)
                    Text(spreadName)
                        .font(.caption.bold()).foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        side.loadedSpreadName = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                }
            }
            HStack {
                Button { showSaveSheet = true } label: {
                    Label("Save Spread", systemImage: "square.and.arrow.down")
                        .font(.caption)
                }
                .buttonStyle(.bordered).tint(.red)

                Button { showLoadSheet = true } label: {
                    Label("Load", systemImage: "tray.and.arrow.up")
                        .font(.caption)
                }
                .buttonStyle(.bordered).tint(.secondary)
                .disabled(savedSpreads.isEmpty)
            }

            if let pkmn = side.pokemon {
                Divider()

                // Ability Picker
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Ability").font(.caption).foregroundStyle(.secondary)
                        Picker("Ability", selection: $side.selectedAbility) {
                            Text("None").tag(String?.none)
                            ForEach(pkmn.allAbilities, id: \.self) { a in
                                Text(formatAbilityName(a)).tag(Optional(a))
                            }
                        }
                        .labelsHidden()
                    }
                    Spacer()
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Item").font(.caption).foregroundStyle(.secondary)
                        Picker("Item", selection: $side.heldItem) {
                            ForEach(HeldItem.allCases) { item in
                                Text(item.rawValue).tag(item)
                            }
                        }
                        .labelsHidden()
                    }
                }

                Toggle("At Full HP", isOn: $side.atFullHP)
                    .font(.subheadline)

                // Level + Nature
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Level").font(.caption).foregroundStyle(.secondary)
                        TextField("Lv", value: $side.level, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            #endif
                    }
                    Spacer()
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Nature").font(.caption).foregroundStyle(.secondary)
                        Picker("Nature", selection: $side.nature) {
                            ForEach(allNatures) { n in
                                Text("\(n.name) \(n.summary)").tag(n)
                            }
                        }
                        .labelsHidden()
                    }
                }

                // Champions Mode Toggle
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Champions Mode", isOn: Binding(
                        get: { side.championsMode },
                        set: { side.setChampionsMode($0) }
                    ))
                    .font(.subheadline)
                    .tint(.red)

                    if side.championsMode {
                        Text("EVs: 0-32 scale (32 = max). IVs fixed at 31.")
                            .font(.caption).foregroundStyle(.secondary)
                    }

                    HStack {
                        let pct = side.evTotalMax > 0
                            ? Double(side.totalEVs) / Double(side.evTotalMax)
                            : 0
                        Text("\(side.totalEVs)/\(side.evTotalMax) EVs")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(side.totalEVs > side.evTotalMax ? .red : .secondary)
                        ProgressView(value: min(pct, 1.0))
                            .tint(pct >= 1.0 ? .red : .accentColor)
                            .frame(maxWidth: 80)
                        Spacer()
                        Button("Reset") {
                            side.evHP = 0; side.evAtk = 0; side.evDef = 0
                            side.evSpAtk = 0; side.evSpDef = 0; side.evSpeed = 0
                        }
                        .font(.caption)
                        .buttonStyle(.bordered)
                        .tint(.secondary)
                    }
                }

                let evStep = side.championsMode ? 1 : 4
                DisclosureGroup("EVs (\(side.totalEVs)/\(side.evTotalMax))") {
                    CappedEVRow(label: "HP", side: side, keyPath: \.evHP, step: evStep)
                    CappedEVRow(label: "Atk", side: side, keyPath: \.evAtk, step: evStep)
                    CappedEVRow(label: "Def", side: side, keyPath: \.evDef, step: evStep)
                    CappedEVRow(label: "Sp.Atk", side: side, keyPath: \.evSpAtk, step: evStep)
                    CappedEVRow(label: "Sp.Def", side: side, keyPath: \.evSpDef, step: evStep)
                    CappedEVRow(label: "Speed", side: side, keyPath: \.evSpeed, step: evStep)
                }
                .font(.subheadline)

                if !side.championsMode {
                    DisclosureGroup("IVs") {
                        EVIVRow(label: "HP", value: $side.ivHP, range: 0...31, step: 1)
                        EVIVRow(label: "Atk", value: $side.ivAtk, range: 0...31, step: 1)
                        EVIVRow(label: "Def", value: $side.ivDef, range: 0...31, step: 1)
                        EVIVRow(label: "Sp.Atk", value: $side.ivSpAtk, range: 0...31, step: 1)
                        EVIVRow(label: "Sp.Def", value: $side.ivSpDef, range: 0...31, step: 1)
                        EVIVRow(label: "Speed", value: $side.ivSpeed, range: 0...31, step: 1)
                    }
                    .font(.subheadline)
                }

                DisclosureGroup("Stat Stages") {
                    StageRow(label: "Atk", stage: $side.atkStage)
                    StageRow(label: "Def", stage: $side.defStage)
                    StageRow(label: "Sp.Atk", stage: $side.spAtkStage)
                    StageRow(label: "Sp.Def", stage: $side.spDefStage)
                    StageRow(label: "Speed", stage: $side.speedStage)
                }
                .font(.subheadline)

                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Text("Final Stats").font(.caption.bold()).foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        StatMini(label: "HP", value: side.hp)
                        StatMini(label: "Atk", value: side.atk)
                        StatMini(label: "Def", value: side.def)
                        StatMini(label: "SpA", value: side.spAtk)
                        StatMini(label: "SpD", value: side.spDef)
                        StatMini(label: "Spe", value: side.speed)
                    }
                    .font(.caption2)
                }
            }
        }
        .sheet(isPresented: $showSaveSheet) {
            SaveSpreadSheet(side: side, modelContext: modelContext, isPresented: $showSaveSheet)
        }
        .sheet(isPresented: $showLoadSheet) {
            LoadSpreadSheet(side: side, spreads: savedSpreads, allPokemon: allPokemon, allMoves: allMoves, modelContext: modelContext, isPresented: $showLoadSheet)
        }
    }
}

// MARK: - Move Slots Section

private struct MoveSlotsSection: View {
    @Bindable var side: CalcSide
    let allMoves: [MoveData]
    let allPokemon: [PKMNStats]
    var vm: DamageCalcVM

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Moves").font(.subheadline.bold())
                Spacer()
                if side.pokemon != nil {
                    Toggle("Legal only", isOn: $side.filterLegalMoves)
                        .font(.caption)
                        .tint(.red)
                        .fixedSize()
                }
            }

            ForEach(0..<4, id: \.self) { index in
                MoveSlotView(index: index, side: side, allMoves: allMoves, allPokemon: allPokemon, vm: vm)
            }
        }
    }
}

private struct MoveSlotView: View {
    let index: Int
    @Bindable var side: CalcSide
    let allMoves: [MoveData]
    let allPokemon: [PKMNStats]
    var vm: DamageCalcVM

    var body: some View {
        if let move = side.moves[index] {
            HStack(spacing: 6) {
                Text("\(index + 1).").font(.caption).foregroundStyle(.tertiary)
                Text(move.name).font(.subheadline.bold()).lineLimit(1)
                TypeBadge(type: move.type)
                Text("\(move.power ?? 0) BP")
                    .font(.caption).foregroundStyle(.secondary)
                DamageClassBadge(damageClass: move.damageClass)
                Spacer()
                Button { side.moves[index] = nil } label: {
                    Image(systemName: "xmark.circle.fill").font(.caption).foregroundStyle(.secondary)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text("\(index + 1).").font(.caption).foregroundStyle(.tertiary)
                    TextField("Move \(index + 1)...", text: Binding(
                        get: { side.moveSearchTexts[index] },
                        set: { side.moveSearchTexts[index] = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .font(.subheadline)
                }

                let results = vm.filteredMoves(for: side, slotIndex: index, allMoves: allMoves, allPokemon: allPokemon)
                if !results.isEmpty {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(results) { move in
                                Button {
                                    side.moves[index] = move
                                    side.moveSearchTexts[index] = ""
                                } label: {
                                    HStack {
                                        Text(move.name)
                                        Spacer()
                                        TypeBadge(type: move.type)
                                        Text("\(move.power ?? 0) BP")
                                            .font(.caption).foregroundStyle(.secondary)
                                        DamageClassBadge(damageClass: move.damageClass)
                                    }
                                    .padding(.vertical, 4).padding(.horizontal, 8)
                                }
                                .buttonStyle(.plain)
                                Divider()
                            }
                        }
                    }
                    .frame(maxHeight: 150)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }
}

// MARK: - Modifiers Card

private struct ModifiersCard: View {
    @Bindable var vm: DamageCalcVM

    var body: some View {
        CalcSection(title: "Modifiers", icon: "slider.horizontal.3") {
            VStack(alignment: .leading, spacing: 6) {
                Text("Weather").font(.subheadline).foregroundStyle(.secondary)
                Picker("Weather", selection: $vm.weather) {
                    ForEach(WeatherCondition.allCases) { w in
                        Text(w.rawValue).tag(w)
                    }
                }
                .pickerStyle(.segmented)

                if vm.weather == .sand {
                    Text("Rock-type defenders get 1.5x Sp.Def in Sand")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if vm.weather == .snow {
                    Text("Ice-type defenders get 1.5x Def in Snow")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            HStack {
                ToggleBadge(label: "Crit", on: $vm.crit)
                ToggleBadge(label: "Burn", on: $vm.burn)
            }
            HStack {
                ToggleBadge(label: "Multi-hit", on: $vm.multi)
                ToggleBadge(label: "Parental Bond", on: $vm.parentalBond)
            }
            HStack {
                ToggleBadge(label: "Glaive Rush", on: $vm.glaiveRush)
                ToggleBadge(label: "Z-Move Bypass", on: $vm.zMoveBypass)
            }

            HStack {
                Text("Misc Multiplier").font(.subheadline)
                Spacer()
                TextField("x", value: $vm.miscMultiplier, format: .number)
                    .textFieldStyle(.roundedBorder).frame(width: 70)
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
            }
        }
    }
}

// MARK: - Save / Load Spread Sheets

private struct SaveSpreadSheet: View {
    var side: CalcSide
    var modelContext: ModelContext
    @Binding var isPresented: Bool
    @State private var name: String

    init(side: CalcSide, modelContext: ModelContext, isPresented: Binding<Bool>) {
        self.side = side
        self.modelContext = modelContext
        self._isPresented = isPresented
        self._name = State(initialValue: side.loadedSpreadName ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Spread Name") {
                    TextField("e.g. Physical Sweeper", text: $name)
                }
                Section("Summary") {
                    if let pkmn = side.pokemon {
                        LabeledContent("Pokemon", value: pkmn.name)
                    }
                    LabeledContent("Nature", value: side.nature.name)
                    LabeledContent("EVs", value: "\(side.evHP)/\(side.evAtk)/\(side.evDef)/\(side.evSpAtk)/\(side.evSpDef)/\(side.evSpeed)")
                    if !side.championsMode {
                        LabeledContent("IVs", value: "\(side.ivHP)/\(side.ivAtk)/\(side.ivDef)/\(side.ivSpAtk)/\(side.ivSpDef)/\(side.ivSpeed)")
                    }
                    if side.championsMode {
                        LabeledContent("Mode", value: "Champions")
                    }
                    let moveNames = side.moves.compactMap { $0?.name }
                    if !moveNames.isEmpty {
                        LabeledContent("Moves", value: moveNames.joined(separator: ", "))
                    }
                }
            }
            .navigationTitle("Save Spread")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let finalName = name.isEmpty ? "Untitled" : name
                        let spread = side.toSavedSpread(name: finalName)
                        modelContext.insert(spread)
                        side.loadedSpreadName = finalName
                        isPresented = false
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

private struct LoadSpreadSheet: View {
    var side: CalcSide
    let spreads: [SavedSpread]
    let allPokemon: [PKMNStats]
    let allMoves: [MoveData]
    var modelContext: ModelContext
    @Binding var isPresented: Bool

    var body: some View {
        NavigationStack {
            List {
                ForEach(spreads) { spread in
                    Button {
                        side.loadSpread(spread, allPokemon: allPokemon, allMoves: allMoves)
                        isPresented = false
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(spread.name).font(.headline)
                                Spacer()
                                if spread.championsMode {
                                    Text("Champions")
                                        .font(.caption2.bold())
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .foregroundStyle(.red)
                                        .background(Color.red.opacity(0.15), in: Capsule())
                                }
                            }
                            HStack(spacing: 8) {
                                if let pkmn = spread.pokemonName {
                                    Text(pkmn).font(.caption).foregroundStyle(.secondary)
                                }
                                Text(allNatures.first(where: { $0.id == spread.natureID })?.name ?? "")
                                    .font(.caption).foregroundStyle(.secondary)
                                if let ability = spread.abilityName {
                                    Text(formatAbilityName(ability))
                                        .font(.caption2)
                                        .padding(.horizontal, 4).padding(.vertical, 1)
                                        .foregroundStyle(.orange)
                                        .background(Color.orange.opacity(0.12), in: Capsule())
                                }
                                if let item = spread.itemRawValue {
                                    Text(item)
                                        .font(.caption2)
                                        .padding(.horizontal, 4).padding(.vertical, 1)
                                        .foregroundStyle(.green)
                                        .background(Color.green.opacity(0.12), in: Capsule())
                                }
                            }
                            Text("EVs: \(spread.evHP)/\(spread.evAtk)/\(spread.evDef)/\(spread.evSpAtk)/\(spread.evSpDef)/\(spread.evSpeed)")
                                .font(.caption.monospaced()).foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { indices in
                    for i in indices {
                        modelContext.delete(spreads[i])
                    }
                }
            }
            .navigationTitle("Load Spread")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    EditButton()
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { isPresented = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Reusable Components

private struct CalcSection<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: icon).font(.headline)
            Divider()
            content
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
    }
}

private struct DamageClassBadge: View {
    let damageClass: String
    private var label: String {
        switch damageClass {
        case "physical": return "Phys"
        case "special":  return "Spec"
        case "status":   return "Status"
        default:         return damageClass.capitalized
        }
    }
    private var color: Color {
        switch damageClass {
        case "physical": return .orange
        case "special":  return .indigo
        case "status":   return .gray
        default:         return .secondary
        }
    }
    var body: some View {
        Text(label)
            .font(.system(size: 9, weight: .semibold))
            .padding(.horizontal, 4).padding(.vertical, 1)
            .foregroundStyle(color)
            .background(color.opacity(0.15), in: Capsule())
    }
}

private struct TypeBadge: View {
    let type: String
    var body: some View {
        Text(type)
            .font(.caption2.bold())
            .padding(.horizontal, 8).padding(.vertical, 3)
            .foregroundStyle(.white)
            .background(typeColorMap[type] ?? .gray, in: Capsule())
    }
}

private struct StatMini: View {
    let label: String
    let value: Int
    var body: some View {
        VStack(spacing: 1) {
            Text(label).foregroundStyle(.secondary)
            Text("\(value)").bold()
        }
        .frame(maxWidth: .infinity)
    }
}

private struct CappedEVRow: View {
    let label: String
    var side: CalcSide
    let keyPath: ReferenceWritableKeyPath<CalcSide, Int>
    var step: Int = 4

    private var cap: Int {
        side.maxAllowedEV(excluding: side[keyPath: keyPath])
    }

    var body: some View {
        let perStatMax = side.evPerStatMax
        HStack {
            Text(label).frame(width: 55, alignment: .leading)
            Slider(value: Binding(
                get: { Double(side[keyPath: keyPath]) },
                set: { newVal in
                    let clamped = max(0, min(Int(newVal), cap))
                    side[keyPath: keyPath] = clamped
                    side.loadedSpreadName = nil
                }
            ), in: 0...Double(max(perStatMax, 1)), step: Double(step))
            .tint(.red)
            TextField("", value: Binding(
                get: { side[keyPath: keyPath] },
                set: { newVal in
                    let clamped = max(0, min(newVal, cap))
                    side[keyPath: keyPath] = clamped
                    side.loadedSpreadName = nil
                }
            ), format: .number)
                .textFieldStyle(.roundedBorder).frame(width: 50)
                #if os(iOS)
                .keyboardType(.numberPad)
                #endif
        }
    }
}

private struct EVIVRow: View {
    let label: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    var step: Int = 4

    var body: some View {
        HStack {
            Text(label).frame(width: 55, alignment: .leading)
            Slider(value: Binding(
                get: { Double(min(max(value, range.lowerBound), range.upperBound)) },
                set: { value = max(range.lowerBound, min(Int($0), range.upperBound)) }
            ), in: Double(range.lowerBound)...Double(range.upperBound), step: Double(step))
            .tint(.red)
            TextField("", value: Binding(
                get: { min(max(value, range.lowerBound), range.upperBound) },
                set: { value = max(range.lowerBound, min($0, range.upperBound)) }
            ), format: .number)
                .textFieldStyle(.roundedBorder).frame(width: 50)
                #if os(iOS)
                .keyboardType(.numberPad)
                #endif
        }
    }
}

private struct StageRow: View {
    let label: String
    @Binding var stage: Int
    var body: some View {
        HStack {
            Text(label).frame(width: 55, alignment: .leading)
            Stepper(value: $stage, in: -6...6) {
                Text(stage > 0 ? "+\(stage)" : "\(stage)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(stage > 0 ? .green : stage < 0 ? .red : .secondary)
            }
        }
    }
}

private struct ToggleBadge: View {
    let label: String
    @Binding var on: Bool
    var body: some View {
        Toggle(isOn: $on) { Text(label).font(.subheadline) }
            .toggleStyle(.button).buttonStyle(.bordered)
            .tint(on ? .red : .secondary).frame(maxWidth: .infinity)
    }
}

// MARK: - Helpers

func formatAbilityName(_ raw: String) -> String {
    raw.split(separator: "-").map { $0.capitalized }.joined(separator: " ")
}

// MARK: - Preview

#Preview {
    DamageCalculatorView()
        .modelContainer(for: [PKMNStats.self, MoveData.self])
}
