//
//  BattleMovesDataTests.swift
//  PKDexTests
//
//  Covers `battle_moves.json` and its loader: the bundled file loads every
//  table, its keys are in the normalized form the engine looks moves up by
//  (so none can silently never match), a few entries decode to the right
//  effects, and a bad name or pair fails the file instead of being dropped.
//  When the tables moved from Swift to JSON (2026-09-28), all 22 were
//  checked identical to the Swift ones.
//

import Testing
import Foundation
@testable import PKDex

@MainActor
@Suite("Battle Moves Data")
struct BattleMovesDataTests {

    private func bundled() throws -> Data {
        let url = try #require(Bundle.main.url(forResource: "battle_moves", withExtension: "json"))
        return try Data(contentsOf: url)
    }

    @Test("The bundled file loads every table")
    func bundledFileLoads() throws {
        let data = try BattleMovesData.decode(bundled())
        #expect(data.statChanges.count == 44)
        #expect(data.secondaryEffects.count == 88)
        #expect(data.chargeMoves.count == 14)
        #expect(data.contactMoves.count > 90)
        #expect(BattleMoveEffects.statChanges.count == data.statChanges.count)
    }

    @Test("Every key is a normalized move name")
    func keysAreNormalized() throws {
        let json = try #require(try JSONSerialization.jsonObject(with: bundled()) as? [String: Any])
        for (table, value) in json where table != "about" && table != "notes" {
            let keys: [String]
            if let list = value as? [String] {
                keys = list
            } else if let dict = value as? [String: Any], table.hasPrefix("invulnerability") {
                keys = dict.values.flatMap { $0 as? [String] ?? [] }
            } else {
                keys = (value as? [String: Any])?.keys.map { $0 } ?? []
            }
            for key in keys {
                #expect(BattleSimSeed.normalize(key) == key, "\(table): \(key)")
            }
        }
    }

    @Test("Entries decode to the engine's effects")
    func spotChecks() throws {
        guard case .selfMod(let dance) = try #require(BattleMoveEffects.statChanges["swordsdance"]) else {
            Issue.record("Swords Dance isn't a self boost"); return
        }
        #expect(dance.map(\.0) == [.atk] && dance.map(\.1) == [2])

        let flamethrower = try #require(BattleMoveEffects.secondaryEffects["flamethrower"])
        #expect(flamethrower.chance == 10 && flamethrower.status == .burn)

        let solarBeam = try #require(BattleMoveEffects.chargeMoves["solarbeam"])
        #expect(solarBeam.skipInWeather == .sun)
        let phantomForce = try #require(BattleMoveEffects.chargeMoves["phantomforce"])
        #expect(phantomForce.invulnerabilityKind == .vanished && phantomForce.bypassesProtect)

        #expect(BattleMoveEffects.pivotMoves["uturn"] == .damage)
        #expect(BattleMoveEffects.hazardSetters["stealthrock"] == .stealthRock)
        #expect(BattleMoveEffects.weatherSetters["raindance"] == .rain)
        #expect(BattleMoveEffects.multiHitFallback["bulletseed"].map { [$0.0, $0.1] } == [2, 5])
    }

    // MARK: Bad files

    /// The bundled file with `table`'s entries replaced by `entries`.
    private func file(replacing table: String, with entries: Any) throws -> Data {
        var json = try #require(try JSONSerialization.jsonObject(with: bundled()) as? [String: Any])
        json[table] = entries
        return try JSONSerialization.data(withJSONObject: json)
    }

    @Test("An unknown kind fails the file")
    func unknownName() throws {
        let data = try file(replacing: "weather_setters", with: ["sunnyday": "sunshine"])
        #expect(throws: BattleMovesData.LoadError.unknownName(
            table: "weather_setters", key: "sunnyday", name: "sunshine")) {
            try BattleMovesData.decode(data)
        }
    }

    @Test("An unknown stat fails the file")
    func unknownStat() throws {
        let data = try file(replacing: "self_stat_changes_on_hit", with: ["overheat": [["spa", -2]]])
        #expect(throws: BattleMovesData.LoadError.unknownName(
            table: "self_stat_changes_on_hit", key: "overheat", name: "spa")) {
            try BattleMovesData.decode(data)
        }
    }

    @Test("A malformed stage pair fails the file")
    func malformedPair() throws {
        let data = try file(replacing: "self_stat_changes_on_hit", with: ["overheat": [[-2, "spAtk"]]])
        #expect(throws: BattleMovesData.LoadError.malformed(table: "self_stat_changes_on_hit", key: "overheat")) {
            try BattleMovesData.decode(data)
        }
    }
}
