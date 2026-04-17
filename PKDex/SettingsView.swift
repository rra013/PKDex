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
    @Environment(\.modelContext) private var modelContext

    @State private var showResetConfirmation = false

    var body: some View {
        NavigationStack {
            Form {
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
        UserDefaults.standard.removeObject(forKey: "hasCompletedCalcSyncV2")
        try? modelContext.delete(model: PKMN.self)
        try? modelContext.delete(model: Gen8Pokemon.self)
        try? modelContext.delete(model: Gen9Pokemon.self)
        try? modelContext.delete(model: PKMNStats.self)
        try? modelContext.delete(model: MoveData.self)
        try? modelContext.save()
        print("App reset! Restart the app to re-sync.")
    }
}
