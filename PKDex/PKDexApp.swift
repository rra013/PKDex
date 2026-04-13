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
    // Sets up the database container for your models
    // Make sure to include both Gen8 and Gen9 models here
    let container = try! ModelContainer(for: PKMN.self, Gen8Pokemon.self, Gen9Pokemon.self)

    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContainer(container)
                .task {
                    // Trigger the private helper function
                    await performStartupSync()
                }
        }
    }
    
    private func performStartupSync() async {
        let hasSynced = UserDefaults.standard.bool(forKey: "hasCompletedInitialSync")
        if hasSynced { return }

        let syncManager = PokeSyncManager(modelContainer: container)

        do {
            print("🚀 Starting isolated background sync...")
            try await syncManager.refreshPokedex()

            UserDefaults.standard.set(true, forKey: "hasCompletedInitialSync")
            print("✅ Sync Completed")
        } catch {
            print("❌ Sync failed: \(error)")
        }
    }
}
