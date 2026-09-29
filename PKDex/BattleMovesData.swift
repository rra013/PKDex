//
//  BattleMovesData.swift
//  PKDex
//
//  Loads `battle_moves.json`, the Battle Sim's move effect tables, into the
//  engine's types. `BattleMoveEffects` exposes the tables under the names
//  the engine has always used, so callers don't know they're data.
//
//  Loading is strict: a name that isn't one of the engine's kinds (a
//  misspelled status, stat or weather) fails the whole file, and
//  `BattleMovesDataTests` checks the bundled one loads.
//

import Foundation

/// The decoded tables, in the engine's types.
struct BattleMovesData {
    var firstTurnOnly: Set<String> = []
    var statChanges: [String: BattleStatChange] = [:]
    var statusInflicts: [String: BattleStatus] = [:]
    var confusionInflicts: Set<String> = []
    var weatherSetters: [String: WeatherCondition] = [:]
    var terrainSetters: [String: TerrainCondition] = [:]
    var hazardSetters: [String: BattleHazard] = [:]
    var protectFamily: Set<String> = []
    var pivotMoves: [String: BattleMoveEffects.PivotKind] = [:]
    var screenSetters: [String: BattleMoveEffects.ScreenKind] = [:]
    var roomSetters: [String: BattleMoveEffects.RoomKind] = [:]
    var hazardRemovers: [String: BattleMoveEffects.HazardRemoval] = [:]
    var ohkoMoves: Set<String> = []
    var trapMoves: Set<String> = []
    var ballisticMoves: Set<String> = []
    var soundMoves: Set<String> = []
    var contactMoves: Set<String> = []
    var chargeMoves: [String: BattleMoveEffects.ChargeBehavior] = [:]
    var invulnerabilityExceptions: [BattleMoveEffects.InvulnerabilityKind: Set<String>] = [:]
    var invulnerabilityDoubleDamage: [BattleMoveEffects.InvulnerabilityKind: Set<String>] = [:]
    var multiHitFallback: [String: (Int, Int)] = [:]
    var secondaryEffects: [String: SecondaryEffect] = [:]
    var selfStatChangesOnHit: [String: [(Nature.StatKey, Int)]] = [:]
    var setupMoves: Set<String> = []

    enum LoadError: Error, Equatable {
        /// A value in `table` (at `key`) isn't one of the engine's names.
        case unknownName(table: String, key: String, name: String)
        /// A stat change isn't a [stat, stages] pair, or a hit count isn't [min, max].
        case malformed(table: String, key: String)
    }

    /// The bundled `battle_moves.json`, or empty tables (and a debug
    /// assertion) if it can't be read.
    static func loadBundled() -> BattleMovesData {
        do {
            guard let url = Bundle.main.url(forResource: "battle_moves", withExtension: "json") else {
                throw CocoaError(.fileNoSuchFile)
            }
            return try decode(Data(contentsOf: url))
        } catch {
            print("[BattleMovesData] failed to read battle_moves.json: \(error)")
            assertionFailure("battle_moves.json didn't load: \(error)")
            return BattleMovesData()
        }
    }

    static func decode(_ data: Data) throws -> BattleMovesData {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let file = try decoder.decode(BattleMovesFile.self, from: data)

        var out = BattleMovesData()
        out.firstTurnOnly = Set(file.firstTurnOnly)
        out.statChanges = try file.statChanges.mapKeyed { key, entry in
            let stages = try Self.stages(entry.stages, table: "stat_changes", key: key)
            switch entry.target {
            case "self": return .selfMod(stages)
            case "opponent": return .opponentMod(stages)
            default: throw LoadError.unknownName(table: "stat_changes", key: key, name: entry.target)
            }
        }
        out.statusInflicts = try file.statusInflicts.mapKeyed { key, name in
            try Self.status(name, table: "status_inflicts", key: key)
        }
        out.confusionInflicts = Set(file.confusionInflicts)
        out.weatherSetters = try file.weatherSetters.mapKeyed { try kind($1, "weather_setters", $0) }
        out.terrainSetters = try file.terrainSetters.mapKeyed { try kind($1, "terrain_setters", $0) }
        out.hazardSetters = try file.hazardSetters.mapKeyed { try kind($1, "hazard_setters", $0) }
        out.protectFamily = Set(file.protectFamily)
        out.pivotMoves = try file.pivotMoves.mapKeyed { try kind($1, "pivot_moves", $0) }
        out.screenSetters = try file.screenSetters.mapKeyed { try kind($1, "screen_setters", $0) }
        out.roomSetters = try file.roomSetters.mapKeyed { try kind($1, "room_setters", $0) }
        out.hazardRemovers = try file.hazardRemovers.mapKeyed { try kind($1, "hazard_removers", $0) }
        out.ohkoMoves = Set(file.ohkoMoves)
        out.trapMoves = Set(file.trapMoves)
        out.ballisticMoves = Set(file.ballisticMoves)
        out.soundMoves = Set(file.soundMoves)
        out.contactMoves = Set(file.contactMoves)
        out.chargeMoves = try file.chargeMoves.mapKeyed { key, entry in
            BattleMoveEffects.ChargeBehavior(
                chargeLog: entry.chargeLog,
                skipInWeather: try entry.skipInWeather.map { try kind($0, "charge_moves", key) },
                selfBoostsOnCharge: try Self.stages(entry.selfBoostsOnCharge ?? [], table: "charge_moves", key: key),
                statusOnRelease: try Self.stages(entry.statusOnRelease ?? [], table: "charge_moves", key: key),
                invulnerabilityKind: try entry.invulnerability.map { try kind($0, "charge_moves", key) },
                bypassesProtect: entry.bypassesProtect ?? false)
        }
        out.invulnerabilityExceptions = try Self.byKind(file.invulnerabilityExceptions,
                                                        table: "invulnerability_exceptions")
        out.invulnerabilityDoubleDamage = try Self.byKind(file.invulnerabilityDoubleDamage,
                                                          table: "invulnerability_double_damage")
        out.multiHitFallback = try file.multiHitFallback.mapKeyed { key, hits in
            guard hits.count == 2 else { throw LoadError.malformed(table: "multi_hit_fallback", key: key) }
            return (hits[0], hits[1])
        }
        out.secondaryEffects = try file.secondaryEffects.mapKeyed { key, entry in
            let table = "secondary_effects"
            return SecondaryEffect(
                chance: entry.chance,
                status: try entry.status.map { try Self.status($0, table: table, key: key) },
                flinch: entry.flinch ?? false,
                targetDrops: try Self.stages(entry.targetDrops ?? [], table: table, key: key),
                selfBoosts: try Self.stages(entry.selfBoosts ?? [], table: table, key: key),
                setsHazardOnFoe: try entry.setsHazardOnFoe.map { try kind($0, table, key) },
                groundsTarget: entry.groundsTarget ?? false,
                curesTargetBurn: entry.curesTargetBurn ?? false,
                saltCureVolatile: entry.saltCureVolatile ?? false,
                requiresTargetBoost: entry.requiresTargetBoost ?? false)
        }
        out.selfStatChangesOnHit = try file.selfStatChangesOnHit.mapKeyed { key, stages in
            try Self.stages(stages, table: "self_stat_changes_on_hit", key: key)
        }
        out.setupMoves = Set(file.setupMoves)
        return out
    }

    // MARK: Names to kinds

    /// The case of `K` spelled `name` (its Swift case name, e.g. "stealthRock").
    private static func kind<K: CaseIterable>(_ name: String, _ table: String, _ key: String) throws -> K {
        guard let match = K.allCases.first(where: { String(describing: $0) == name }) else {
            throw LoadError.unknownName(table: table, key: key, name: name)
        }
        return match
    }

    private static func status(_ name: String, table: String, key: String) throws -> BattleStatus {
        guard let status = BattleStatus(rawValue: name), status != .none else {
            throw LoadError.unknownName(table: table, key: key, name: name)
        }
        return status
    }

    /// [[stat, stages], ...] pairs, in order.
    private static func stages(_ pairs: [[BattleMovesFile.StatOrStages]], table: String,
                               key: String) throws -> [(Nature.StatKey, Int)] {
        try pairs.map { pair in
            guard pair.count == 2, case .stat(let name) = pair[0], case .stages(let n) = pair[1] else {
                throw LoadError.malformed(table: table, key: key)
            }
            guard let stat = Nature.StatKey(rawValue: name) else {
                throw LoadError.unknownName(table: table, key: key, name: name)
            }
            return (stat, n)
        }
    }

    private static func byKind(_ lists: [String: [String]], table: String)
        throws -> [BattleMoveEffects.InvulnerabilityKind: Set<String>] {
        var out: [BattleMoveEffects.InvulnerabilityKind: Set<String>] = [:]
        for (name, moves) in lists {
            out[try kind(name, table, name)] = Set(moves)
        }
        return out
    }
}

private extension Dictionary where Key == String {
    /// `mapValues` whose transform also gets the key and can throw.
    func mapKeyed<T>(_ transform: (String, Value) throws -> T) rethrows -> [String: T] {
        var out: [String: T] = [:]
        for (key, value) in self { out[key] = try transform(key, value) }
        return out
    }
}

/// `battle_moves.json` as written: names and numbers only. `about` and
/// `notes` are for people and aren't read.
nonisolated private struct BattleMovesFile: Decodable, Sendable {
    let firstTurnOnly: [String]
    let statChanges: [String: StatChange]
    let statusInflicts: [String: String]
    let confusionInflicts: [String]
    let weatherSetters: [String: String]
    let terrainSetters: [String: String]
    let hazardSetters: [String: String]
    let protectFamily: [String]
    let pivotMoves: [String: String]
    let screenSetters: [String: String]
    let roomSetters: [String: String]
    let hazardRemovers: [String: String]
    let ohkoMoves: [String]
    let trapMoves: [String]
    let ballisticMoves: [String]
    let soundMoves: [String]
    let contactMoves: [String]
    let chargeMoves: [String: Charge]
    let invulnerabilityExceptions: [String: [String]]
    let invulnerabilityDoubleDamage: [String: [String]]
    let multiHitFallback: [String: [Int]]
    let secondaryEffects: [String: Secondary]
    let selfStatChangesOnHit: [String: [[StatOrStages]]]
    let setupMoves: [String]

    struct StatChange: Decodable, Sendable {
        let target: String
        let stages: [[StatOrStages]]
    }

    struct Charge: Decodable, Sendable {
        let chargeLog: String
        let skipInWeather: String?
        let selfBoostsOnCharge: [[StatOrStages]]?
        let statusOnRelease: [[StatOrStages]]?
        let invulnerability: String?
        let bypassesProtect: Bool?
    }

    struct Secondary: Decodable, Sendable {
        let chance: Int
        let status: String?
        let flinch: Bool?
        let targetDrops: [[StatOrStages]]?
        let selfBoosts: [[StatOrStages]]?
        let setsHazardOnFoe: String?
        let groundsTarget: Bool?
        let curesTargetBurn: Bool?
        let saltCureVolatile: Bool?
        let requiresTargetBoost: Bool?
    }

    /// One element of a [stat, stages] pair.
    enum StatOrStages: Decodable, Sendable {
        case stat(String)
        case stages(Int)

        init(from decoder: Decoder) throws {
            let value = try decoder.singleValueContainer()
            if let n = try? value.decode(Int.self) {
                self = .stages(n)
            } else {
                self = .stat(try value.decode(String.self))
            }
        }
    }
}
