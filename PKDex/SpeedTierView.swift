//
//  SpeedTierView.swift
//  PKDex
//

import SwiftUI
import SwiftData

// MARK: - Speed Tier Calculation

enum SpeedBenchmark: String, CaseIterable, Identifiable {
    case maxBoosted   = "Max+ (252 EV, +Spe)"
    case maxNeutral   = "Max (252 EV, Neutral)"
    case uninvBoosted = "Uninvested+ (0 EV, +Spe)"
    case uninvNeutral = "Uninvested (0 EV, Neutral)"
    case minHindered  = "Min (0 EV, 0 IV, -Spe)"

    var id: String { rawValue }

    var ev: Int {
        switch self {
        case .maxBoosted, .maxNeutral: return 252
        case .uninvBoosted, .uninvNeutral, .minHindered: return 0
        }
    }

    var iv: Int {
        switch self {
        case .minHindered: return 0
        default: return 31
        }
    }

    var natureMod: Double {
        switch self {
        case .maxBoosted, .uninvBoosted: return 1.1
        case .maxNeutral, .uninvNeutral: return 1.0
        case .minHindered: return 0.9
        }
    }

    /// Champions-mode equivalent EV (0-32 scale)
    var championsEV: Int {
        switch self {
        case .maxBoosted, .maxNeutral: return 32
        case .uninvBoosted, .uninvNeutral, .minHindered: return 0
        }
    }
}

enum SpeedItemModifier: String, CaseIterable, Identifiable {
    case none = "None"
    case choiceScarf = "Choice Scarf (1.5x)"
    case ironBall = "Iron Ball (0.5x)"

    var id: String { rawValue }

    var multiplier: Double {
        switch self {
        case .none: return 1.0
        case .choiceScarf: return 1.5
        case .ironBall: return 0.5
        }
    }
}

enum SpeedAbilityModifier: String, CaseIterable, Identifiable {
    case none = "None"
    case swiftSwim = "Swift Swim / Chlorophyll / Sand Rush / Slush Rush (2x)"
    case unburden = "Unburden (2x)"
    case quickFeet = "Quick Feet (1.5x)"
    case slowStart = "Slow Start (0.5x)"
    case paralysis = "Paralysis (0.25x)"

    var id: String { rawValue }

    var multiplier: Double {
        switch self {
        case .none: return 1.0
        case .swiftSwim, .unburden: return 2.0
        case .quickFeet: return 1.5
        case .slowStart: return 0.5
        case .paralysis: return 0.25
        }
    }
}

struct SpeedEntry: Identifiable {
    let id = UUID()
    let pokemonName: String
    let pokemonID: Int
    let baseSpeed: Int
    let type1: String
    let type2: String?
    let finalSpeed: Int
}

/// Compute speed for a given benchmark configuration.
func computeBenchmarkSpeed(
    baseSpeed: Int, level: Int,
    benchmark: SpeedBenchmark,
    championsMode: Bool,
    itemMod: SpeedItemModifier,
    abilityMod: SpeedAbilityModifier
) -> Int {
    let ev = championsMode ? championsEVToMain(benchmark.championsEV) : benchmark.ev
    let iv = benchmark.iv
    let rawStat = calcStat(base: baseSpeed, iv: iv, ev: ev, level: level, natureMod: benchmark.natureMod)
    return Int(Double(rawStat) * itemMod.multiplier * abilityMod.multiplier)
}

/// Compute the user's custom speed from their CalcSide configuration.
func computeUserSpeed(side: CalcSide, itemMod: SpeedItemModifier, abilityMod: SpeedAbilityModifier) -> Int {
    let baseSpeed = side.speed // already accounts for EVs, IVs, nature, level, stages
    return Int(Double(baseSpeed) * itemMod.multiplier * abilityMod.multiplier)
}

// MARK: - Speed Tier View

struct SpeedTierView: View {
    @Query(sort: \PKMNStats.baseSpeed, order: .reverse) private var allPokemon: [PKMNStats]
    @Query(sort: \SavedSpread.createdAt, order: .reverse) private var savedSpreads: [SavedSpread]
    @Query(sort: \MoveData.name) private var allMoves: [MoveData]
    @AppStorage("defaultGeneration") private var defaultGeneration: String = PokedexFilter.champions.rawValue

    @State private var side = CalcSide()
    @State private var showLoadSpread = false

    // User's modifiers
    @State private var userItemMod: SpeedItemModifier = .none
    @State private var userAbilityMod: SpeedAbilityModifier = .none

    // Field (opponent) benchmark
    @State private var fieldBenchmark: SpeedBenchmark = .maxBoosted
    @State private var fieldItemMod: SpeedItemModifier = .none
    @State private var fieldAbilityMod: SpeedAbilityModifier = .none

    @State private var filterChampions = false
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            List {
                // User's Pokemon section
                Section("Your Pokemon") {
                    userPokemonSection
                }

                if side.pokemon != nil {
                    Section("Your Modifiers") {
                        Picker("Item", selection: $userItemMod) {
                            ForEach(SpeedItemModifier.allCases) { Text($0.rawValue).tag($0) }
                        }
                        Picker("Ability / Status", selection: $userAbilityMod) {
                            ForEach(SpeedAbilityModifier.allCases) { Text($0.rawValue).tag($0) }
                        }
                        HStack {
                            Text("Your Speed")
                            Spacer()
                            Text("\(userFinalSpeed)").font(.title2.bold().monospacedDigit())
                        }
                    }

                    Section("Opponent Benchmark") {
                        Picker("Investment", selection: $fieldBenchmark) {
                            ForEach(SpeedBenchmark.allCases) { Text($0.rawValue).tag($0) }
                        }
                        Picker("Item", selection: $fieldItemMod) {
                            ForEach(SpeedItemModifier.allCases) { Text($0.rawValue).tag($0) }
                        }
                        Picker("Ability / Status", selection: $fieldAbilityMod) {
                            ForEach(SpeedAbilityModifier.allCases) { Text($0.rawValue).tag($0) }
                        }
                        Toggle("Champions Roster Only", isOn: $filterChampions)
                            .tint(.red)
                    }

                    speedTierResults
                }
            }
            .navigationTitle("Speed Tiers")
            .searchable(text: $searchText, prompt: "Filter results...")
            .scrollDismissesKeyboard(.interactively)
            .sheet(isPresented: $showLoadSpread) {
                SpreadPickerSheet(savedSpreads: savedSpreads) { spread in
                    side.loadSpread(spread, allPokemon: Array(allPokemon), allMoves: Array(allMoves))
                    if spread.championsMode {
                        filterChampions = true
                    }
                }
            }
            .onAppear {
                if defaultGeneration == PokedexFilter.champions.rawValue {
                    filterChampions = true
                    if side.pokemon == nil {
                        side.setChampionsMode(true)
                    }
                }
            }
        }
    }

    // MARK: - User Pokemon Section

    @ViewBuilder
    private var userPokemonSection: some View {
        if let p = side.pokemon {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(p.name).font(.headline)
                    Text("Base Speed: \(p.baseSpeed)").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                TypeBadge(type: p.type1)
                if let t2 = p.type2 { TypeBadge(type: t2) }
                Button { side.pokemon = nil; side.searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
            }

            // Nature
            Picker("Nature", selection: $side.nature) {
                ForEach(allNatures) { n in
                    Text("\(n.name) \(n.summary)").tag(n)
                }
            }

            // Level
            HStack {
                Text("Level")
                Spacer()
                TextField("Lv", value: $side.level, format: .number)
                    .frame(width: 60)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    #if os(iOS)
                    .keyboardType(.numberPad)
                    #endif
            }

            // Speed EV
            HStack {
                Text("Speed EV")
                Spacer()
                Slider(value: Binding(
                    get: { Double(side.evSpeed) },
                    set: { side.evSpeed = max(0, min(Int($0), side.evPerStatMax)) }
                ), in: 0...Double(max(side.evPerStatMax, 1)), step: Double(side.championsMode ? 1 : 4))
                .tint(.red)
                .frame(maxWidth: 120)
                TextField("", value: Binding(
                    get: { side.evSpeed },
                    set: { side.evSpeed = max(0, min($0, side.evPerStatMax)) }
                ), format: .number)
                    .textFieldStyle(.roundedBorder).frame(width: 50)
                    #if os(iOS)
                    .keyboardType(.numberPad)
                    #endif
            }

            if !side.championsMode {
                HStack {
                    Text("Speed IV")
                    Spacer()
                    Slider(value: Binding(
                        get: { Double(side.ivSpeed) },
                        set: { side.ivSpeed = max(0, min(Int($0), 31)) }
                    ), in: 0...31, step: 1)
                    .tint(.red)
                    .frame(maxWidth: 120)
                    TextField("", value: Binding(
                        get: { side.ivSpeed },
                        set: { side.ivSpeed = max(0, min($0, 31)) }
                    ), format: .number)
                        .textFieldStyle(.roundedBorder).frame(width: 50)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                }
            }

            // Speed stage
            HStack {
                Text("Speed Stage")
                Spacer()
                Stepper(value: $side.speedStage, in: -6...6) {
                    Text(side.speedStage > 0 ? "+\(side.speedStage)" : "\(side.speedStage)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(side.speedStage > 0 ? .green : side.speedStage < 0 ? .red : .secondary)
                }
            }

            // Champions toggle
            Toggle("Champions Mode", isOn: Binding(
                get: { side.championsMode },
                set: { side.setChampionsMode($0) }
            )).tint(.red)

            Button("Load Saved Set") { showLoadSpread = true }
        } else {
            TextField("Search Mons...", text: $side.searchText)
            ForEach(filteredPokemonSearch) { p in
                Button {
                    side.pokemon = p
                    side.searchText = ""
                    side.selectedAbility = p.ability1
                } label: {
                    HStack {
                        Text("#\(p.id)").foregroundStyle(.secondary).frame(width: 44, alignment: .leading)
                        Text(p.name)
                        Spacer()
                        Text("Spe \(p.baseSpeed)").font(.caption).foregroundStyle(.secondary)
                        TypeBadge(type: p.type1)
                        if let t2 = p.type2 { TypeBadge(type: t2) }
                    }
                }
            }
            Button("Load Saved Set") { showLoadSpread = true }
        }
    }

    private var filteredPokemonSearch: [PKMNStats] {
        let q = side.searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }
        return allPokemon
            .filter { $0.name.lowercased().contains(q) || String($0.id).contains(q) }
            .prefix(20).map { $0 }
    }

    // MARK: - Speed Calculations

    private var userFinalSpeed: Int {
        computeUserSpeed(side: side, itemMod: userItemMod, abilityMod: userAbilityMod)
    }

    private var speedEntries: [SpeedEntry] {
        let level = side.level
        let pool: [PKMNStats]
        if filterChampions {
            pool = allPokemon.filter { championsRoster.contains($0.name) && !$0.isForm }
        } else {
            pool = allPokemon.filter { !$0.isForm }
        }

        // Deduplicate by speciesID (keep first, which has highest baseSpeed since sorted desc)
        var seen = Set<Int>()
        var deduplicated: [PKMNStats] = []
        for p in pool {
            if seen.insert(p.speciesID).inserted {
                deduplicated.append(p)
            }
        }

        let champMode = side.championsMode
        return deduplicated.map { p in
            let finalSpeed = computeBenchmarkSpeed(
                baseSpeed: p.baseSpeed, level: level,
                benchmark: fieldBenchmark, championsMode: champMode,
                itemMod: fieldItemMod, abilityMod: fieldAbilityMod
            )
            return SpeedEntry(pokemonName: p.name, pokemonID: p.id,
                              baseSpeed: p.baseSpeed,
                              type1: p.type1, type2: p.type2,
                              finalSpeed: finalSpeed)
        }
        .sorted { $0.finalSpeed > $1.finalSpeed }
    }

    private var filteredEntries: [SpeedEntry] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return speedEntries }
        return speedEntries.filter { $0.pokemonName.lowercased().contains(q) }
    }

    // MARK: - Speed Tier Results

    @ViewBuilder
    private var speedTierResults: some View {
        let mySpeed = userFinalSpeed
        let entries = filteredEntries
        let faster = entries.filter { $0.finalSpeed > mySpeed }
        let ties = entries.filter { $0.finalSpeed == mySpeed }
        let slower = entries.filter { $0.finalSpeed < mySpeed }

        if !faster.isEmpty {
            Section("Outsped By (\(faster.count))") {
                ForEach(faster) { entry in
                    SpeedRow(entry: entry, userSpeed: mySpeed)
                }
            }
        }

        if !ties.isEmpty {
            Section("Speed Ties (\(ties.count))") {
                ForEach(ties) { entry in
                    SpeedRow(entry: entry, userSpeed: mySpeed)
                }
            }
        }

        if !slower.isEmpty {
            Section("Outspeeds (\(slower.count))") {
                ForEach(slower) { entry in
                    SpeedRow(entry: entry, userSpeed: mySpeed)
                }
            }
        }
    }
}

// MARK: - Speed Row

private struct SpeedRow: View {
    let entry: SpeedEntry
    let userSpeed: Int

    var body: some View {
        HStack(spacing: 8) {
            Text("\(entry.finalSpeed)")
                .font(.subheadline.bold().monospacedDigit())
                .foregroundStyle(entry.finalSpeed > userSpeed ? .red :
                                 entry.finalSpeed == userSpeed ? .orange : .green)
                .frame(width: 40, alignment: .trailing)

            VStack(alignment: .leading, spacing: 1) {
                Text(entry.pokemonName).font(.subheadline).lineLimit(1)
                Text("Base \(entry.baseSpeed)")
                    .font(.caption2).foregroundStyle(.secondary)
            }

            Spacer()

            TypeBadge(type: entry.type1)
            if let t2 = entry.type2 { TypeBadge(type: t2) }
        }
    }
}

// MARK: - Spread Picker Sheet

private struct SpreadPickerSheet: View {
    let savedSpreads: [SavedSpread]
    let onSelect: (SavedSpread) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(savedSpreads, id: \.name) { spread in
                Button {
                    onSelect(spread)
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(spread.name).font(.headline)
                        if let pokeName = spread.pokemonName {
                            Text(pokeName).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Load a Set")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .overlay {
                if savedSpreads.isEmpty {
                    ContentUnavailableView("No Saved Sets", systemImage: "square.and.pencil",
                                          description: Text("Save a set from the Sets tab first."))
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Preview

#Preview {
    SpeedTierView()
        .modelContainer(for: [PKMNStats.self, MoveData.self, SavedSpread.self])
}
