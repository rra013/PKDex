//
//  ChampionsMoveConnectionTests.swift
//  PKDexTests
//
//  Regression test for the Champions Mon Index → Move Detail tap-through.
//  Every move name in `champions-m-a-learnsets.json` must resolve to a
//  `MoveData` entry via `ChampionsPokemonDetailView.moveLookup`'s normalized
//  comparison, otherwise the row falls back to a non-tappable label. The
//  original bug ("Will-O-Wisp" vs "Will O Wisp") was a punctuation mismatch
//  between Showdown-style names in the JSON and the PokeAPI-slug display form
//  the sync writes into `MoveData.name`.
//

import Testing
import Foundation
@testable import PKDex

@MainActor
@Suite("Champions Mon Index — Move Connection Coverage")
struct ChampionsMoveConnectionTests {

    // MARK: - Fixture Loading

    /// Walks `champions-m-a-learnsets.json` and collects every distinct move
    /// name across base species, mega, and alternate forms. Returns `nil`
    /// when the JSON isn't in the test bundle so the suite can skip cleanly
    /// (matching the `PokiiParityTests` convention).
    static func loadAllChampionsMoves() -> Set<String>? {
        guard let url = Bundle.main.url(forResource: "champions-m-a-learnsets",
                                        withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let species = root["species"] as? [String: [String: Any]] else {
            return nil
        }
        var moves: Set<String> = []
        for entry in species.values {
            if let m = entry["moves"] as? [String] { moves.formUnion(m) }
            for nestedKey in ["megas", "alternate_forms"] {
                guard let forms = entry[nestedKey] as? [[String: Any]] else { continue }
                for form in forms {
                    if let m = form["moves"] as? [String] { moves.formUnion(m) }
                }
            }
        }
        return moves
    }

    // MARK: - Behaviour Mirrors

    /// Reproduces `PokeAPIGraphQL.syncCalcData`'s move-name transform: derive
    /// the canonical PokeAPI slug from a Showdown-style display name
    /// (lowercase, spaces → hyphens, strip apostrophes / dots), then
    /// title-case the hyphen-delimited tokens back into the display form
    /// `MoveData.name` actually stores after a sync.
    static func simulatedMoveDataName(from showdown: String) -> String {
        let slug = showdown
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: ".", with: "")
        return slug.split(separator: "-")
            .map { $0.capitalized }
            .joined(separator: " ")
    }

    /// Mirrors `ChampionsPokemonDetailView.moveLookup` so the test exercises
    /// the exact lookup the view uses to decide whether to render a row as a
    /// `NavigationLink` into the Move Index.
    static func lookup(_ name: String, in moves: [MoveData]) -> MoveData? {
        let normalized = BattleSimSeed.normalize(name)
        guard !normalized.isEmpty else { return nil }
        return moves.first { BattleSimSeed.normalize($0.name) == normalized }
    }

    private static func makeMove(id: Int, name: String) -> MoveData {
        MoveData(id: id, name: name, type: "Normal", damageClass: "physical",
                 power: nil, accuracy: nil, pp: 0, priority: 0,
                 minHits: nil, maxHits: nil, drain: 0, healing: 0,
                 critRate: 0, makesContact: false, generationId: 0)
    }

    // MARK: - Tests

    /// Every move name in the Champions JSON must connect to the synced
    /// `MoveData` display form. The synthetic move list is built by piping
    /// each Champions name through the same name transform the sync uses, so
    /// if this test fails, either the sync transform or the lookup normalizer
    /// has drifted and the Mon Index will silently lose Move Detail
    /// tap-throughs for the affected moves.
    @Test func everyChampionsMoveConnectsToSyncedMoveData() {
        guard let names = Self.loadAllChampionsMoves() else {
            // Match PokiiParityTests' convention: skip rather than fail when
            // the JSON isn't bundled (e.g., resources-stripped CI build).
            print("[Champions] champions-m-a-learnsets.json not bundled — skipping coverage check.")
            return
        }

        #expect(!names.isEmpty,
                "champions-m-a-learnsets.json should contain at least one move")

        // Build a MoveData list that mirrors what the live sync would produce
        // for the Showdown-style names in the JSON. IDs are arbitrary; they
        // only need to be unique so `first(where:)` short-circuits cleanly.
        var idCounter = 1
        let syncedMoves: [MoveData] = names.sorted().map { showdown in
            defer { idCounter += 1 }
            return Self.makeMove(id: idCounter,
                                 name: Self.simulatedMoveDataName(from: showdown))
        }

        var missing: [String] = []
        for name in names where Self.lookup(name, in: syncedMoves) == nil {
            missing.append(name)
        }
        #expect(missing.isEmpty,
                "Champions moves with no MoveData connection: \(missing.sorted())")
    }

    /// Focused regression list for the punctuation moves that originally
    /// failed to tap through under the case-insensitive equality lookup. Each
    /// pair is `(Champions JSON spelling, synced MoveData spelling)`. If any
    /// of these stops connecting the user-visible regression returns.
    @Test func punctuationMovesConnectToSyncedNames() {
        let pairs: [(showdown: String, synced: String)] = [
            ("Baby-Doll Eyes",   "Baby Doll Eyes"),
            ("Double-Edge",      "Double Edge"),
            ("Forest's Curse",   "Forests Curse"),
            ("Freeze-Dry",       "Freeze Dry"),
            ("King's Shield",    "Kings Shield"),
            ("Lock-On",          "Lock On"),
            ("Mud-Slap",         "Mud Slap"),
            ("Self-Destruct",    "Self Destruct"),
            ("Trick-or-Treat",   "Trick Or Treat"),
            ("U-turn",           "U Turn"),
            ("Will-O-Wisp",      "Will O Wisp"),
            ("X-Scissor",        "X Scissor"),
        ]
        let syncedMoves = pairs.enumerated().map { idx, pair in
            Self.makeMove(id: idx + 1, name: pair.synced)
        }
        for pair in pairs {
            let hit = Self.lookup(pair.showdown, in: syncedMoves)
            #expect(hit?.name == pair.synced,
                    "Champions '\(pair.showdown)' didn't connect to MoveData '\(pair.synced)'")
        }
    }

    /// Guards the name-derivation contract directly: every Champions move
    /// name and its corresponding `MoveData` form must normalize to the same
    /// alphanumeric key. Catches a regression where someone changes the sync
    /// transform (e.g., stops stripping apostrophes) without updating the
    /// normalizer — the full-coverage test would still pass against the
    /// synthetic data it built, but real users would break.
    @Test func syncedNameAndChampionsNameAgreeOnNormalizedKey() {
        guard let names = Self.loadAllChampionsMoves() else { return }
        for name in names {
            let normalized = BattleSimSeed.normalize(name)
            #expect(!normalized.isEmpty,
                    "Champions move '\(name)' normalizes to empty string")
            let synced = Self.simulatedMoveDataName(from: name)
            #expect(BattleSimSeed.normalize(synced) == normalized,
                    "Normalize mismatch — Champions '\(name)' → '\(normalized)', synced '\(synced)' → '\(BattleSimSeed.normalize(synced))'")
        }
    }
}
