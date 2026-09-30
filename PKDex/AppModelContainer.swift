//
//  AppModelContainer.swift
//  PKDex
//
//  The app's SwiftData store, created once and shared: the windows use it,
//  and so do the App Intents that Siri, Spotlight and Shortcuts run, often
//  with no window open.
//

import Foundation
import SwiftData

nonisolated enum AppModelContainer {
    static let shared: ModelContainer = {
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
}
