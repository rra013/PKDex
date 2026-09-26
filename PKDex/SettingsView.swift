//
//  SettingsView.swift
//  PKDex
//
//  Created by Rishi Anand on 4/16/26.
//

import SwiftUI
import SwiftData

struct SettingsView: View {
    @AppStorage("defaultGeneration") private var defaultGeneration: String = PokedexFilter.champions.rawValue
    @AppStorage(TabLayout.orderKey) private var tabOrderRaw = ""
    @AppStorage(TabLayout.hiddenKey) private var hiddenTabsRaw = ""
    @AppStorage("defaultTab") private var defaultTabRaw: String = AppTab.monIndex.rawValue
    @AppStorage("appAccentColor") private var accentColorRaw: String = AppAccentColor.blue.rawValue
    @AppStorage("appAppearance") private var appearanceRaw: String = AppAppearance.system.rawValue
    /// Defaults to `latest`, the same fallback `ChampionsRegulation.current`
    /// uses, so before anything is stored the picker shows the format the
    /// app is actually using.
    @AppStorage(ChampionsRegulation.userDefaultsKey) private var championsRegulationRaw: String = ChampionsRegulation.latest.rawValue
    @Environment(\.modelContext) private var modelContext

    @State private var showResetConfirmation = false
    @State private var showRedownloadConfirmation = false
    @State private var isRedownloading = false
    @State private var redownloadStatus: String?
    /// Size of Team Search's cached tournament data; nil until measured.
    @State private var teamSearchCacheBytes: Int?

    private var tabLayout: TabLayout {
        TabLayout(orderRaw: tabOrderRaw, hiddenRaw: hiddenTabsRaw)
    }

    private var shownTabsSummary: String {
        let shown = tabLayout.visible.count
        let total = AppTab.allUserTabs.count
        return shown == total ? "All shown" : "\(shown) of \(total) shown"
    }

    var body: some View {
        NavigationStack {
            Form {
                // MARK: - Appearance
                Section {
                    Picker("Appearance", selection: $appearanceRaw) {
                        ForEach(AppAppearance.allCases) { mode in
                            Text(mode.label).tag(mode.rawValue)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Accent Color")
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 6), spacing: 12) {
                            ForEach(AppAccentColor.allCases) { accent in
                                Circle()
                                    .fill(accent.color)
                                    .frame(width: 32, height: 32)
                                    .overlay {
                                        if accentColorRaw == accent.rawValue {
                                            Image(systemName: "checkmark")
                                                .font(.caption.bold())
                                                .foregroundStyle(.white)
                                        }
                                    }
                                    .onTapGesture { accentColorRaw = accent.rawValue }
                                    .accessibilityLabel(accent.label)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Appearance")
                }

                // MARK: - Tabs
                Section {
                    NavigationLink {
                        TabSettingsView()
                    } label: {
                        LabeledContent("Arrange Tabs", value: shownTabsSummary)
                    }

                    Picker("Open To", selection: $defaultTabRaw) {
                        ForEach(tabLayout.visible) { tab in
                            Label(tab.label, systemImage: tab.icon).tag(tab.rawValue)
                        }
                    }
                } header: {
                    Text("Tabs")
                } footer: {
                    Text("Choose which tabs appear and in what order, and which one the app opens to.")
                }

                // MARK: - Default Generation
                Section {
                    Picker("Default Generation", selection: $defaultGeneration) {
                        ForEach(PokedexFilter.allCases) { filter in
                            Text(filter.title).tag(filter.rawValue)
                        }
                    }
                } header: {
                    Text("Default Generation")
                } footer: {
                    Text("Sets the default filter for the Mon Index. When Champions is selected, the Damage Calculator will also default to Champions Mode.")
                }

                // MARK: - Champions Regulation
                Section {
                    Picker("Active Regulation", selection: $championsRegulationRaw) {
                        ForEach(ChampionsRegulation.allCases) { reg in
                            HStack {
                                Text(reg.displayName)
                                Spacer()
                                if let window = Self.legalWindowString(for: reg) {
                                    Text(window)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .tag(reg.rawValue)
                        }
                    }
                } header: {
                    Text("Champions Regulation")
                } footer: {
                    Text("Switches the roster, learnsets, and validation rules used by the Mon Index, Set Builder, and Battle Simulator. New installs default to the latest regulation (by start date). Reopen any Champions screen after switching to pick up the new format.")
                }

                // MARK: - Data Management
                Section("Data Management") {
                    Button {
                        showRedownloadConfirmation = true
                    } label: {
                        HStack {
                            Label("Redownload Pokemon & Move Data", systemImage: "arrow.trianglehead.2.counterclockwise")
                            Spacer()
                            if isRedownloading {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isRedownloading)

                    if let status = redownloadStatus {
                        Text(status)
                            .font(.caption)
                            .foregroundStyle(status.contains("Failed") ? .red : .secondary)
                    }

                    Button {
                        Task {
                            try? await TeamCorpusStore.shared.clearCache()
                            try? await SmogonUsageStore.shared.clearCache()
                            teamSearchCacheBytes = await teamSearchCacheSize()
                        }
                    } label: {
                        HStack {
                            Label("Clear Team Search Data", systemImage: "trash")
                            Spacer()
                            if let bytes = teamSearchCacheBytes {
                                Text(bytes.formatted(.byteCount(style: .file)))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .disabled(teamSearchCacheBytes == 0)

                    Button("Reset All Data", role: .destructive) {
                        showResetConfirmation = true
                    }
                    .disabled(isRedownloading)
                }

                // MARK: - Disclaimers
                Section("About") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("PK Reference")
                            .font(.headline)

                        Text("This app is a fan-made reference tool for competitive Pokemon. It is not affiliated with, endorsed by, or associated with Nintendo, The Pokemon Company, or Game Freak.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text("Pokemon and all related names, characters, and imagery are trademarks and copyrights of their respective owners.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text("Damage calculations follow Smogon's damage calculator for Champions and the Gen V+ formula otherwise, and may not be exact in every edge case.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text("Data from PokeAPI, Serebii and Limitless. The damage calculator is ported from Smogon's, and the RNG tools from PokéFinder and EonTimer.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text("PK Reference is free software under the GNU General Public License, version 3 or later, and comes with no warranty. The license and source code are under Acknowledgements & Licenses.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)

                    NavigationLink {
                        AcknowledgementsView()
                    } label: {
                        Label("Acknowledgements & Licenses", systemImage: "doc.text")
                    }
                }
            }
            .navigationTitle("Settings")
            .task { teamSearchCacheBytes = await teamSearchCacheSize() }
            .confirmationDialog(
                "Redownload Data",
                isPresented: $showRedownloadConfirmation,
                titleVisibility: .visible
            ) {
                Button("Redownload") {
                    Task { await performRedownload() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will redownload all Pokemon and Move data from PokeAPI. Your saved spreads and teams will not be affected.")
            }
            .confirmationDialog(
                "Reset All Data",
                isPresented: $showResetConfirmation,
                titleVisibility: .visible
            ) {
                Button("Reset", role: .destructive) {
                    performReset()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will restore the app to a fresh install state, deleting all downloaded data, saved spreads, teams, and preferences. The app will re-sync on next launch.")
            }
        }
    }

    private func performRedownload() async {
        isRedownloading = true
        redownloadStatus = "Clearing old data…"

        try? modelContext.delete(model: PKMN.self)
        try? modelContext.delete(model: Gen8Pokemon.self)
        try? modelContext.delete(model: Gen9Pokemon.self)
        try? modelContext.delete(model: PKMNStats.self)
        try? modelContext.delete(model: MoveData.self)
        try? modelContext.save()

        let container = modelContext.container

        do {
            redownloadStatus = "Downloading Pokedex data…"
            let pokeSync = PokeSyncManager(modelContainer: container)
            try await pokeSync.refreshPokedex()
            UserDefaults.standard.set(true, forKey: "hasCompletedInitialSync")

            redownloadStatus = "Downloading stats & moves…"
            let calcSync = CalcDataSyncManager(modelContainer: container)
            try await calcSync.syncCalcData()
            UserDefaults.standard.set(true, forKey: "hasCompletedCalcSyncV4")

            redownloadStatus = "Data updated successfully."
        } catch {
            redownloadStatus = "Failed: \(error.localizedDescription)"
        }

        isRedownloading = false
    }

    /// "Apr 8 – Jun 16, 2026" style window for a regulation, or `nil` when
    /// neither bound is recorded in its JSON. Used by the regulation picker
    /// so users can see at-a-glance which format covers which dates.
    private static func legalWindowString(for reg: ChampionsRegulation) -> String? {
        let period = reg.legalPeriod
        if period.from == nil && period.until == nil { return nil }
        let fmt = legalWindowDateFormatter
        let from = period.from.map { fmt.string(from: $0) } ?? "?"
        let until = period.until.map { fmt.string(from: $0) } ?? "TBD"
        return "\(from) – \(until)"
    }

    private static let legalWindowDateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "MMM d, yyyy"
        return df
    }()

    private func performReset() {
        if let bundleID = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
        }
        try? modelContext.delete(model: PKMN.self)
        try? modelContext.delete(model: Gen8Pokemon.self)
        try? modelContext.delete(model: Gen9Pokemon.self)
        try? modelContext.delete(model: PKMNStats.self)
        try? modelContext.delete(model: MoveData.self)
        try? modelContext.delete(model: SavedSpread.self)
        try? modelContext.delete(model: SavedTeam.self)
        try? modelContext.save()
        Task {
            try? await TeamCorpusStore.shared.clearCache()
            try? await SmogonUsageStore.shared.clearCache()
            teamSearchCacheBytes = 0
        }
    }

    /// Team Search's tournament teams plus its Smogon usage stats.
    private func teamSearchCacheSize() async -> Int {
        let teams = await TeamCorpusStore.shared.cacheSize()
        let usage = await SmogonUsageStore.shared.cacheSize()
        return teams + usage
    }
}

// MARK: - Arrange Tabs

/// Reorders and hides tabs. Each row's switch hides or shows its tab, and
/// Reorder shows the drag handles. The two can't share a mode: a list in
/// edit mode ignores taps on its rows' switches.
private struct TabSettingsView: View {
    @AppStorage(TabLayout.orderKey) private var tabOrderRaw = ""
    @AppStorage(TabLayout.hiddenKey) private var hiddenTabsRaw = ""
    @AppStorage("defaultTab") private var defaultTabRaw: String = AppTab.monIndex.rawValue
    @Environment(\.horizontalSizeClass) private var hSize
    @State private var editMode: EditMode = .inactive

    private var layout: TabLayout {
        get { TabLayout(orderRaw: tabOrderRaw, hiddenRaw: hiddenTabsRaw) }
        nonmutating set {
            tabOrderRaw = newValue.orderRaw
            hiddenTabsRaw = newValue.hiddenRaw
            defaultTabRaw = newValue.launchTab(for: defaultTabRaw).rawValue
        }
    }

    var body: some View {
        List {
            Section {
                ForEach(layout.order) { tab in
                    Toggle(isOn: Binding(
                        get: { !layout.hidden.contains(tab) },
                        set: { layout.setHidden(tab, !$0) }
                    )) {
                        row(for: tab)
                    }
                    .disabled(editMode.isEditing || !layout.canHide(tab))
                }
                .onMove { layout.move(fromOffsets: $0, toOffset: $1) }
            } footer: {
                Text("Tap Reorder, then drag tabs to change the order. With more than five tabs, iPhone shows the first four in the tab bar and the rest under More. Settings always comes last, and at least one other tab stays shown.")
            }
        }
        .environment(\.editMode, $editMode)
        .toolbar {
            Button(editMode.isEditing ? "Done" : "Reorder") {
                withAnimation { editMode = editMode.isEditing ? .inactive : .active }
            }
            .fontWeight(editMode.isEditing ? .semibold : .regular)
        }
        .navigationTitle("Arrange Tabs")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(for tab: AppTab) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(tab.label)
                // Only a compact tab bar splits into bar and More.
                if hSize == .compact, let note = placementNote(for: tab) {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } icon: {
            Image(systemName: tab.icon)
        }
    }

    private func placementNote(for tab: AppTab) -> String? {
        switch layout.compactPlacement(of: tab) {
        case .tabBar: return "In tab bar"
        case .more:   return "Under More"
        case .hidden: return nil
        }
    }
}
