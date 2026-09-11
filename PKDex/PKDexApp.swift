//
//  PKDexApp.swift
//  PKDex
//
//  Created by Rishi Anand on 4/13/26.
//

import SwiftUI
import SwiftData

@main
struct PokedexApp: App {
    @Environment(\.scenePhase) private var scenePhase

    let container: ModelContainer = {
        let schema = Schema([PKMN.self, Gen8Pokemon.self, Gen9Pokemon.self, PKMNStats.self, MoveData.self, SavedSpread.self, SavedTeam.self])
        let config = ModelConfiguration(schema: schema)

        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            // Schema changed and auto-migration failed -- delete the old store and retry.
            print("Migration failed, deleting old store: \(error)")
            let storeURL = config.url
            let related = [
                storeURL.appendingPathExtension("wal"),
                storeURL.appendingPathExtension("shm"),
            ]
            for url in [storeURL] + related {
                try? FileManager.default.removeItem(at: url)
            }
            // Clear sync flags so data re-downloads
            UserDefaults.standard.removeObject(forKey: "hasCompletedInitialSync")
            UserDefaults.standard.removeObject(forKey: "hasCompletedCalcSyncV3")
            UserDefaults.standard.removeObject(forKey: "hasCompletedCalcSyncV4")

            do {
                return try ModelContainer(for: schema, configurations: [config])
            } catch {
                fatalError("Could not create ModelContainer even after store reset: \(error)")
            }
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContainer(container)
                .task {
                    // Trigger the private helper function
                    await performStartupSync()
                }
        }
        .onChange(of: scenePhase) { _, newPhase in
            // The on-device Pokii LLM (~4 GB) is held resident on a shared
            // singleton once loaded and has no other teardown path, so a
            // backgrounded session gets jetsam-killed almost immediately on a
            // real device. Release it (and MLX's pooled Metal buffers) when we
            // leave the foreground; the AI builder reloads it lazily on return
            // via the idempotent `PokiiInferenceEngine.load()`.
            if newPhase == .background {
                PokiiInferenceEngine.shared.unload()
            }
        }
    }
    
    private func performStartupSync() async {
        let hasSynced = UserDefaults.standard.bool(forKey: "hasCompletedInitialSync")
        if !hasSynced {
            let syncManager = PokeSyncManager(modelContainer: container)
            do {
                print("Starting Pokedex sync...")
                try await syncManager.refreshPokedex()
                UserDefaults.standard.set(true, forKey: "hasCompletedInitialSync")
                print("Pokedex sync completed")
            } catch {
                print("Pokedex sync failed: \(error)")
            }
        }

        // Bumped to V4 when migrating off the stale `beta.pokeapi.co/graphql/v1beta`
        // endpoint to `graphql.pokeapi.co/v1beta2`, so existing installs
        // auto-resync and pick up Legends Z-A content (e.g. Mega Scovillain).
        let hasCalcData = UserDefaults.standard.bool(forKey: "hasCompletedCalcSyncV4")
        if !hasCalcData {
            let calcSync = CalcDataSyncManager(modelContainer: container)
            do {
                print("Starting calc data sync...")
                try await calcSync.syncCalcData()
                UserDefaults.standard.set(true, forKey: "hasCompletedCalcSyncV4")
                print("Calc data sync completed")
            } catch {
                print("Calc data sync failed: \(error)")
            }
        }

        await MainActor.run {
            BattleSimSeed.seedIfNeeded(modelContainer: container)
        }
    }
}
