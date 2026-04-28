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
    @AppStorage("enabledTabs") private var enabledTabsRaw: String = AppTab.defaultEnabledRaw
    @AppStorage("defaultTab") private var defaultTabRaw: String = AppTab.monIndex.rawValue
    @AppStorage("appAccentColor") private var accentColorRaw: String = AppAccentColor.blue.rawValue
    @AppStorage("appAppearance") private var appearanceRaw: String = AppAppearance.system.rawValue
    @Environment(\.modelContext) private var modelContext

    @State private var showResetConfirmation = false

    private var enabledTabSet: Set<String> {
        Set(enabledTabsRaw.split(separator: ",").map(String.init))
    }

    private func isTabEnabled(_ tab: AppTab) -> Bool {
        enabledTabSet.contains(tab.rawValue)
    }

    private func toggleTab(_ tab: AppTab) {
        var current = enabledTabsRaw.split(separator: ",").map(String.init)
        if let idx = current.firstIndex(of: tab.rawValue) {
            if current.count > 1 {
                current.remove(at: idx)
            }
        } else {
            current.append(tab.rawValue)
        }
        enabledTabsRaw = current.joined(separator: ",")

        if !current.contains(defaultTabRaw) {
            defaultTabRaw = current.first ?? AppTab.monIndex.rawValue
        }
    }

    private var enabledUserTabs: [AppTab] {
        let raw = enabledTabsRaw.split(separator: ",").map(String.init)
        return raw.compactMap { AppTab(rawValue: $0) }
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

                // MARK: - Tab Bar
                Section {
                    ForEach(AppTab.allUserTabs) { tab in
                        Toggle(isOn: Binding(
                            get: { isTabEnabled(tab) },
                            set: { _ in toggleTab(tab) }
                        )) {
                            Label(tab.label, systemImage: tab.icon)
                        }
                    }
                } header: {
                    Text("Visible Tabs")
                } footer: {
                    Text("At least one tab must remain enabled. Settings is always visible.")
                }

                // MARK: - Default Tab
                Section {
                    Picker("Open To", selection: $defaultTabRaw) {
                        ForEach(enabledUserTabs) { tab in
                            Label(tab.label, systemImage: tab.icon).tag(tab.rawValue)
                        }
                    }
                } header: {
                    Text("Default Tab")
                } footer: {
                    Text("The tab shown when the app launches.")
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

                // MARK: - Data Management
                Section("Data Management") {
                    Button("Reset All Data", role: .destructive) {
                        showResetConfirmation = true
                    }
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

                        Text("Damage calculations are based on the Gen V+ damage formula and may not be perfectly accurate in all edge cases.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text("Data sourced from PokeAPI.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Settings")
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
                Text("This will delete all downloaded data and saved spreads. The app will re-sync on next launch. Are you sure?")
            }
        }
    }

    private func performReset() {
        UserDefaults.standard.removeObject(forKey: "hasCompletedInitialSync")
        UserDefaults.standard.removeObject(forKey: "hasCompletedCalcSyncV3")
        try? modelContext.delete(model: PKMN.self)
        try? modelContext.delete(model: Gen8Pokemon.self)
        try? modelContext.delete(model: Gen9Pokemon.self)
        try? modelContext.delete(model: PKMNStats.self)
        try? modelContext.delete(model: MoveData.self)
        try? modelContext.save()
        print("App reset! Restart the app to re-sync.")
    }
}
