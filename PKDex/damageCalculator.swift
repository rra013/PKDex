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

    let effectiveAtk = Int(Double(userAtk) * abilityMods.atkMultiplier)
    let effectiveDef = Int(Double(defenderDef) * abilityMods.defMultiplier)
    let effectivePower = Int(Double(movePower) * abilityMods.powerMultiplier)

    let scaledLevel = (2 * level / 5) + 2
    let attackTerm = scaledLevel * effectivePower * effectiveAtk / max(effectiveDef, 1)
    var base = Double(attackTerm / 50 + 2)

    if multi         { base *= 0.75 }
    if parentalBond  { base *= 1.25 }
    base *= weatherMult
    if glaiveRush    { base *= 1.5 }
    if crit          { base *= abilityMods.critMultiplierOverride ?? critMultiplier }

    let effectiveStab = abilityMods.stabOverride ?? stabBonus
    base *= effectiveStab

    let effectiveTypeEff = abilityMods.typeEffOverride ?? typeEffect
    base *= effectiveTypeEff

    base *= burnReduction
    base *= abilityMods.finalMultiplier

    if zMoveBypass { base *= 0.25 }

    return (base * 0.85, base * 1.0)
}

func computeTypeEffectiveness(moveType: String, defenderTypes: [String]) -> Double {
    var mult = 1.0
    let chart = typeEffectivenessChart[moveType] ?? [:]
    for dt in defenderTypes {
        mult *= chart[dt] ?? 1.0
    }
    return mult
}

// MARK: - Side Model (Attacker or Defender)

@Observable
class CalcSide {
    var pokemon: PKMNStats?
    var searchText: String = ""
    var nature: Nature = allNatures.first(where: { $0.id == "adamant" })!
    var level: Int = 50
    var selectedAbility: String?
    var atFullHP: Bool = true

    /// When true, EVs use the Champions 0-32 scale and IVs are fixed at 31.
    var championsMode: Bool = false

    // EVs -- stored in whichever scale is active (0-252 normal, 0-32 champions)
    var evHP: Int = 0
    var evAtk: Int = 0
    var evDef: Int = 0
    var evSpAtk: Int = 0
    var evSpDef: Int = 0
    var evSpeed: Int = 0

    // IVs (ignored in Champions mode — always treated as 31)
    var ivHP: Int = 31
    var ivAtk: Int = 31
    var ivDef: Int = 31
    var ivSpAtk: Int = 31
    var ivSpDef: Int = 31
    var ivSpeed: Int = 31

    // Stat stages
    var atkStage: Int = 0
    var defStage: Int = 0
    var spAtkStage: Int = 0
    var spDefStage: Int = 0
    var speedStage: Int = 0

    // Scale-aware limits
    var evPerStatMax: Int { championsMode ? championsMaxEVPerStat : maxEVPerStat }
    var evTotalMax: Int { championsMode ? championsMaxTotalEVs : maxTotalEVs }
    var totalEVs: Int { evHP + evAtk + evDef + evSpAtk + evSpDef + evSpeed }

    /// Convert stored EV to main-series value for the stat formula.
    private func formulaEV(_ stored: Int) -> Int {
        championsMode ? championsEVToMain(stored) : stored
    }

    /// In Champions mode IVs are always 31.
    private func formulaIV(_ stored: Int) -> Int {
        championsMode ? 31 : stored
    }

    func setChampionsMode(_ on: Bool) {
        guard on != championsMode else { return }
        if on {
            // Scale EVs from main-series → Champions
            evHP    = evHP * 32 / 252
            evAtk   = evAtk * 32 / 252
            evDef   = evDef * 32 / 252
            evSpAtk = evSpAtk * 32 / 252
            evSpDef = evSpDef * 32 / 252
            evSpeed = evSpeed * 32 / 252
            // Lock IVs
            ivHP = 31; ivAtk = 31; ivDef = 31
            ivSpAtk = 31; ivSpDef = 31; ivSpeed = 31
            championsMode = true
        } else {
            // Scale EVs from Champions → main-series
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

// MARK: - View Model

@MainActor
@Observable
class DamageCalcVM {
    var attacker = CalcSide()
    var defender = CalcSide()

    var selectedMove: MoveData?
    var moveSearchText: String = ""
    var filterLegalMoves: Bool = true // Only show moves the attacker can learn

    // Modifiers
    var crit: Bool = false
    var burn: Bool = false
    var multi: Bool = false
    var parentalBond: Bool = false
    var glaiveRush: Bool = false
    var zMoveBypass: Bool = false
    var weather: WeatherCondition = .none
    var miscMultiplier: Double = 1.0

    var moveType: String { selectedMove?.type ?? "Normal" }
    var movePower: Int { selectedMove?.power ?? 0 }
    var isPhysical: Bool { (selectedMove?.damageClass ?? "physical") == "physical" }
    var isContact: Bool { selectedMove?.makesContact ?? false }

    var stab: Bool { attacker.types.contains(moveType) }
    var stabBonus: Double { stab ? 1.5 : 1.0 }
    var burnReduction: Double { (burn && isPhysical) ? 0.5 : 1.0 }

    var typeEffect: Double {
        computeTypeEffectiveness(moveType: moveType, defenderTypes: defender.types)
    }

    // Weather-adjusted stats
    var weatherMoveMult: Double {
        weather.moveDamageMultiplier(moveType: moveType)
    }

    var effectiveAtk: Int { isPhysical ? attacker.atk : attacker.spAtk }

    var effectiveDef: Int {
        if isPhysical {
            let baseDef = defender.def
            let snowMult = weather.snowDefMultiplier(defenderTypes: defender.types)
            return Int(Double(baseDef) * snowMult)
        } else {
            let baseSpDef = defender.spDef
            let sandMult = weather.sandSpDefMultiplier(defenderTypes: defender.types)
            return Int(Double(baseSpDef) * sandMult)
        }
    }

    var abilityMods: AbilityModResult {
        computeAbilityModifiers(
            attackerAbility: attacker.selectedAbility,
            defenderAbility: defender.selectedAbility,
            moveType: moveType,
            movePower: movePower,
            isPhysical: isPhysical,
            isContact: isContact,
            isSTAB: stab,
            typeEffectiveness: typeEffect,
            weather: weather,
            attackerAtFullHP: attacker.atFullHP,
            defenderAtFullHP: defender.atFullHP
        )
    }

    var result: (min: Double, max: Double) {
        calcDamageRange(
            level: attacker.level, movePower: movePower,
            userAtk: effectiveAtk, defenderDef: effectiveDef,
            multi: multi, parentalBond: parentalBond,
            weatherMult: weatherMoveMult, glaiveRush: glaiveRush,
            crit: crit, critMultiplier: 1.5,
            stabBonus: stabBonus, typeEffect: typeEffect,
            burnReduction: burnReduction, abilityMods: abilityMods,
            zMoveBypass: zMoveBypass
        )
    }

    var minPercent: Double {
        guard defender.hp > 0 else { return 0 }
        return min(result.min / Double(defender.hp) * 100, 999)
    }
    var maxPercent: Double {
        guard defender.hp > 0 else { return 0 }
        return min(result.max / Double(defender.hp) * 100, 999)
    }

    var hitsToKO: String {
        guard maxPercent > 0 else { return "--" }
        let minHits = Int(ceil(100.0 / maxPercent))
        let maxHits = minPercent > 0 ? Int(ceil(100.0 / minPercent)) : 0
        if minHits == maxHits { return "\(minHits)HKO" }
        return "\(minHits)-\(maxHits)HKO"
    }

    var effectivenessLabel: String {
        let eff = abilityMods.typeEffOverride ?? typeEffect
        switch eff {
        case 0:    return "Immune"
        case 0.25: return "1/4x"
        case 0.5:  return "1/2x"
        case 1:    return "1x"
        case 2:    return "2x"
        case 4:    return "4x"
        default:   return String(format: "%.2fx", eff)
        }
    }

    var effectivenessColor: Color {
        let eff = abilityMods.typeEffOverride ?? typeEffect
        switch eff {
        case 0:          return .gray
        case 0.25, 0.5:  return .blue
        case 1:          return .primary
        case 2:          return .orange
        case 4:          return .red
        default:         return .primary
        }
    }

    var summaryText: String {
        let atkName = attacker.pokemon?.name ?? "???"
        let defName = defender.pokemon?.name ?? "???"
        let moveName = selectedMove?.name ?? "???"
        return "\(atkName) \(moveName) vs. \(defName): \(String(format: "%.0f", result.min))-\(String(format: "%.0f", result.max)) (\(String(format: "%.1f", minPercent)) - \(String(format: "%.1f", maxPercent))%) -- \(hitsToKO)"
    }

    /// Returns moves filtered to the attacker's learnset (if enabled and a Pokemon is selected).
    func filteredMoves(from allMoves: [MoveData], allPokemon: [PKMNStats]) -> [MoveData] {
        let q = moveSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }

        var pool = allMoves
        if filterLegalMoves, let pkmn = attacker.pokemon {
            var legalIDs = Set(pkmn.learnableMoveIDs)
            // For alternate forms with no learnset, fall back to base species
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
                        SideCard(title: "Attacker", icon: "figure.fencing", side: vm.attacker, allPokemon: allPokemon, isAttacker: true)
                        MoveCard(vm: vm, allMoves: allMoves, allPokemon: allPokemon)
                        SideCard(title: "Defender", icon: "shield.fill", side: vm.defender, allPokemon: allPokemon, isAttacker: false)
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
        VStack(spacing: 14) {
            if vm.selectedMove != nil && vm.attacker.pokemon != nil && vm.defender.pokemon != nil {
                Text(vm.summaryText)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Label("Result", systemImage: "bolt.fill").font(.headline)
                Spacer()
                Text(vm.effectivenessLabel)
                    .font(.headline.bold())
                    .foregroundStyle(vm.effectivenessColor)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(vm.effectivenessColor.opacity(0.15), in: Capsule())
                if vm.movePower > 0 {
                    Text(vm.hitsToKO)
                        .font(.headline.bold()).foregroundStyle(.red)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Color.red.opacity(0.15), in: Capsule())
                }
            }

            Divider()

            HStack(spacing: 0) {
                damageColumn(label: "Min", value: vm.result.min, pct: vm.minPercent)
                Divider().frame(height: 44)
                damageColumn(label: "Max", value: vm.result.max, pct: vm.maxPercent)
            }

            PercentageBar(minPct: vm.minPercent, maxPct: vm.maxPercent)

            // Active modifier badges
            HStack(spacing: 6) {
                if vm.stab && vm.selectedMove != nil {
                    InfoBadge(text: "STAB", color: .yellow)
                }
                if vm.weather != .none {
                    InfoBadge(text: vm.weather.rawValue, color: .cyan)
                }
                if let atkA = vm.attacker.selectedAbility, !atkA.isEmpty {
                    InfoBadge(text: formatAbilityName(atkA), color: .orange)
                }
                if let defA = vm.defender.selectedAbility, !defA.isEmpty {
                    InfoBadge(text: formatAbilityName(defA), color: .purple)
                }
                if vm.attacker.championsMode {
                    InfoBadge(text: "Champions", color: .red)
                }
                Spacer()
            }
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
    }

    private func damageColumn(label: String, value: Double, pct: Double) -> some View {
        VStack(spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(String(format: "%.0f", value))
                .font(.system(size: 32, weight: .bold, design: .rounded))
            Text(String(format: "%.1f%%", pct))
                .font(.callout)
                .foregroundStyle(pct >= 100 ? .red : .secondary)
        }
        .frame(maxWidth: .infinity)
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
    let isAttacker: Bool

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
                    TextField("Search Pokemon...", text: $side.searchText)
                        .textFieldStyle(.roundedBorder)

                    if !filteredPokemon.isEmpty {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(filteredPokemon) { p in
                                    Button {
                                        side.pokemon = p
                                        side.searchText = ""
                                        side.selectedAbility = p.ability1
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

            if let pkmn = side.pokemon {
                Divider()

                // Ability Picker
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

                // Full HP toggle (for Multiscale etc.)
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
                        Text("\(side.totalEVs)/\(side.evTotalMax) EVs")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(side.totalEVs > side.evTotalMax ? .red : .secondary)
                        Spacer()
                        Button("Reset EVs") {
                            side.evHP = 0; side.evAtk = 0; side.evDef = 0
                            side.evSpAtk = 0; side.evSpDef = 0; side.evSpeed = 0
                        }
                        .font(.caption)
                        .buttonStyle(.bordered)
                        .tint(.secondary)
                    }
                }

                // EVs
                let evMax = side.evPerStatMax
                let evStep = side.championsMode ? 1 : 4
                DisclosureGroup("EVs (\(side.totalEVs)/\(side.evTotalMax))") {
                    EVIVRow(label: "HP", value: $side.evHP, range: 0...evMax, step: evStep)
                    EVIVRow(label: "Atk", value: $side.evAtk, range: 0...evMax, step: evStep)
                    EVIVRow(label: "Def", value: $side.evDef, range: 0...evMax, step: evStep)
                    EVIVRow(label: "Sp.Atk", value: $side.evSpAtk, range: 0...evMax, step: evStep)
                    EVIVRow(label: "Sp.Def", value: $side.evSpDef, range: 0...evMax, step: evStep)
                    EVIVRow(label: "Speed", value: $side.evSpeed, range: 0...evMax, step: evStep)
                }
                .font(.subheadline)

                // IVs — hidden in Champions mode (always 31)
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
    }
}

// MARK: - Move Card

private struct MoveCard: View {
    @Bindable var vm: DamageCalcVM
    let allMoves: [MoveData]
    let allPokemon: [PKMNStats]

    var body: some View {
        CalcSection(title: "Move", icon: "bolt.horizontal.fill") {
            if let move = vm.selectedMove {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(move.name).font(.title3.bold())
                            TypeBadge(type: move.type)
                        }
                        HStack(spacing: 16) {
                            Label("\(move.power ?? 0)", systemImage: "flame.fill")
                            Label(move.damageClass.capitalized, systemImage: move.damageClass == "physical" ? "figure.boxing" : "sparkles")
                            if let acc = move.accuracy { Label("\(acc)%", systemImage: "target") }
                            Label("\(move.pp) PP", systemImage: "circle.grid.2x2")
                        }
                        .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { vm.selectedMove = nil; vm.moveSearchText = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                }
            } else {
                HStack {
                    TextField("Search moves...", text: $vm.moveSearchText)
                        .textFieldStyle(.roundedBorder)
                }

                if vm.attacker.pokemon != nil {
                    Toggle("Legal moves only", isOn: $vm.filterLegalMoves)
                        .font(.caption)
                        .tint(.red)
                }

                let results = vm.filteredMoves(from: allMoves, allPokemon: allPokemon)
                if !results.isEmpty {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(results) { move in
                                Button {
                                    vm.selectedMove = move
                                    vm.moveSearchText = ""
                                } label: {
                                    HStack {
                                        Text(move.name)
                                        Spacer()
                                        TypeBadge(type: move.type)
                                        Text("\(move.power ?? 0) BP")
                                            .font(.caption).foregroundStyle(.secondary)
                                        Text(move.damageClass == "physical" ? "Phys" : "Spec")
                                            .font(.caption2)
                                            .padding(.horizontal, 6).padding(.vertical, 2)
                                            .background(move.damageClass == "physical" ? Color.orange.opacity(0.2) : Color.indigo.opacity(0.2), in: Capsule())
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
    }
}

// MARK: - Modifiers Card

private struct ModifiersCard: View {
    @Bindable var vm: DamageCalcVM

    var body: some View {
        CalcSection(title: "Modifiers", icon: "slider.horizontal.3") {
            // Weather
            VStack(alignment: .leading, spacing: 6) {
                Text("Weather").font(.subheadline).foregroundStyle(.secondary)
                Picker("Weather", selection: $vm.weather) {
                    ForEach(WeatherCondition.allCases) { w in
                        Text(w.rawValue).tag(w)
                    }
                }
                .pickerStyle(.segmented)

                if vm.weather != .none {
                    let mult = vm.weatherMoveMult
                    if mult != 1.0 {
                        Text("\(vm.weather.rawValue) \(mult > 1 ? "boosts" : "weakens") \(vm.moveType) moves (\(String(format: "%.1fx", mult)))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if vm.weather == .sand {
                        Text("Rock-type defenders get 1.5x Sp.Def in Sand")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if vm.weather == .snow {
                        Text("Ice-type defenders get 1.5x Def in Snow")
                            .font(.caption).foregroundStyle(.secondary)
                    }
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
