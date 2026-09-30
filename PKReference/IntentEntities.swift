//
//  IntentEntities.swift
//  PKReference
//
//  The things App Intents act on, and how Siri, Spotlight and Shortcuts
//  find them: Pokémon and moves by name, and a side's stats for the damage
//  calc from a short list (no investment, full investment, or a saved set
//  of that Pokémon). The store is read on the main actor, through
//  `IntentData`.
//

import AppIntents
import Foundation
import SwiftData

nonisolated enum IntentError: Error, CustomLocalizedStringResourceConvertible {
    case noData
    case notFound(String)
    case noTournamentData

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .noData:
            "PK Reference hasn't downloaded its Pokémon data yet. Open it once, with an internet connection."
        case .notFound(let what):
            "PK Reference couldn't find \(what)."
        case .noTournamentData:
            "PK Reference hasn't downloaded tournament teams yet. Open Team Search in the app once, with an internet connection."
        }
    }
}

// MARK: - Pokémon

nonisolated struct PokemonEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Pokémon"
    static let defaultQuery = PokemonQuery()

    /// `PKMNStats.id`: the Pokémon, or one of its forms.
    let id: Int
    /// As it's said: "Mega Charizard X".
    let name: String
    let speciesID: Int

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

nonisolated struct PokemonQuery: EntityStringQuery {
    func entities(for identifiers: [Int]) async throws -> [PokemonEntity] {
        try await IntentData.pokemonEntities(ids: identifiers)
    }

    func entities(matching string: String) async throws -> [PokemonEntity] {
        try await IntentData.pokemonEntities(matching: string)
    }

    /// The current regulation's roster.
    func suggestedEntities() async throws -> [PokemonEntity] {
        try await IntentData.rosterEntities()
    }
}

// MARK: - Moves

nonisolated struct MoveEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Move"
    static let defaultQuery = MoveQuery()

    /// `MoveData.id`.
    let id: Int
    let name: String
    /// "Ground · Physical · 100 power".
    let detail: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(detail)")
    }
}

/// Damaging moves only: the calc has nothing to say about the others.
nonisolated struct MoveQuery: EntityStringQuery {
    @IntentParameterDependency<CalculateDamageIntent>(\.$attacker) var calc

    func entities(for identifiers: [Int]) async throws -> [MoveEntity] {
        try await IntentData.moveEntities(ids: identifiers)
    }

    func entities(matching string: String) async throws -> [MoveEntity] {
        try await IntentData.moveEntities(matching: string)
    }

    /// The attacker's damaging moves, once it's chosen.
    func suggestedEntities() async throws -> [MoveEntity] {
        guard let attacker = calc?.attacker else { return [] }
        return try await IntentData.moveEntities(learnedBy: attacker.id)
    }
}

// MARK: - Stats

/// A side's stats in the damage calc. Siri asks for one for each side and
/// offers these, so the answer never rests on an assumption.
nonisolated struct StatsEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Stats"
    static let defaultQuery = StatsQuery()

    /// "none", "full", or "set:" and the saved set's encoded identifier.
    let id: String
    let title: String
    let subtitle: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(subtitle)")
    }

    static let noInvestment = StatsEntity(
        id: "none", title: "No investment",
        subtitle: "No EVs or stat points, a neutral nature, level 50")
    static let fullInvestment = StatsEntity(
        id: "full", title: "Full investment",
        subtitle: "Full EVs or stat points in the attacking stat, or HP and the matching defense; a neutral nature, level 50")

    var choice: StatChoice? {
        switch id {
        case "none": return .noInvestment
        case "full": return .fullInvestment
        default:
            guard id.hasPrefix("set:"),
                  let data = Data(base64Encoded: String(id.dropFirst("set:".count))),
                  let identifier = try? JSONDecoder().decode(PersistentIdentifier.self, from: data)
            else { return nil }
            return .savedSet(identifier)
        }
    }

    static func setID(_ identifier: PersistentIdentifier) -> String? {
        (try? JSONEncoder().encode(identifier)).map { "set:" + $0.base64EncodedString() }
    }
}

nonisolated struct StatsQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [StatsEntity] {
        try await IntentData.statsEntities(ids: identifiers)
    }
}

nonisolated struct AttackerStatsOptions: DynamicOptionsProvider {
    @IntentParameterDependency<CalculateDamageIntent>(\.$attacker) var calc

    func results() async throws -> [StatsEntity] {
        try await IntentData.statsChoices(for: calc?.attacker.id)
    }
}

nonisolated struct DefenderStatsOptions: DynamicOptionsProvider {
    @IntentParameterDependency<CalculateDamageIntent>(\.$defender) var calc

    func results() async throws -> [StatsEntity] {
        try await IntentData.statsChoices(for: calc?.defender.id)
    }
}

// MARK: - Reading the store

/// The App Intents' view of the store. Everything runs on the main actor,
/// where the shared container's context lives.
@MainActor
enum IntentData {
    static var storeContext: ModelContext { AppModelContainer.shared.mainContext }

    static func allPokemon(in store: ModelContext? = nil) throws -> [PKMNStats] {
        let context = store ?? storeContext
        let all = try context.fetch(FetchDescriptor<PKMNStats>())
        guard !all.isEmpty else { throw IntentError.noData }
        return all
    }

    static func pokemon(_ id: Int, in store: ModelContext? = nil) throws -> PKMNStats {
        let context = store ?? storeContext
        guard let match = try allPokemon(in: context).first(where: { $0.id == id }) else {
            throw IntentError.notFound("that Pokémon")
        }
        return match
    }

    static func entity(_ stats: PKMNStats) -> PokemonEntity {
        PokemonEntity(id: stats.id, name: IntentNames.spoken(name: stats.name, formName: stats.formName),
                      speciesID: stats.speciesID)
    }

    static func pokemonEntities(ids: [Int]) throws -> [PokemonEntity] {
        let all = try allPokemon()
        return ids.compactMap { id in all.first { $0.id == id }.map(entity) }
    }

    static func pokemonEntities(matching text: String) throws -> [PokemonEntity] {
        let all = try allPokemon()
        let candidates = all.map {
            IntentNames.Candidate(id: $0.id, keys: IntentNames.keys(name: $0.name, formName: $0.formName),
                                  length: $0.name.count)
        }
        return IntentNames.matches(text, in: candidates).compactMap { id in all.first { $0.id == id }.map(entity) }
    }

    static func rosterEntities() throws -> [PokemonEntity] {
        let roster = championsRoster
        return try allPokemon()
            .filter { !$0.isForm && roster.contains($0.name) }
            .sorted { $0.speciesID < $1.speciesID }
            .map(entity)
    }

    // Moves

    private static func damagingMoves() throws -> [MoveData] {
        try storeContext.fetch(FetchDescriptor<MoveData>(sortBy: [SortDescriptor(\.name)]))
            .filter { $0.damageClass != "status" }
    }

    static func entity(_ move: MoveData) -> MoveEntity {
        var detail = [move.type, move.damageClass.capitalized]
        if let power = move.power, power > 0 { detail.append("\(power) power") }
        return MoveEntity(id: move.id, name: move.name, detail: detail.joined(separator: " · "))
    }

    static func moveEntities(ids: [Int]) throws -> [MoveEntity] {
        let all = try damagingMoves()
        return ids.compactMap { id in all.first { $0.id == id }.map(entity) }
    }

    static func moveEntities(matching text: String) throws -> [MoveEntity] {
        let all = try damagingMoves()
        let candidates = all.map {
            IntentNames.Candidate(id: $0.id, keys: [IntentNames.key($0.name)], length: $0.name.count)
        }
        return IntentNames.matches(text, in: candidates).compactMap { id in all.first { $0.id == id }.map(entity) }
    }

    static func moveEntities(learnedBy pokemonID: Int) throws -> [MoveEntity] {
        let learnable = Set(try pokemon(pokemonID).learnableMoveIDs)
        return try damagingMoves().filter { learnable.contains($0.id) }.map(entity)
    }

    // Stats

    static func statsEntity(_ spread: SavedSpread) -> StatsEntity? {
        guard let id = StatsEntity.setID(spread.persistentModelID) else { return nil }
        var parts = ["Saved set"]
        if let ability = spread.abilityName { parts.append(formatAbilityName(ability)) }
        if let nature = allNatures.first(where: { $0.id == spread.natureID }) { parts.append(nature.name) }
        parts.append(spread.championsMode ? "Champions" : "Mainline")
        return StatsEntity(id: id, title: spread.name, subtitle: parts.joined(separator: " · "))
    }

    static func sets(for pokemonID: Int, in store: ModelContext? = nil) -> [SavedSpread] {
        let context = store ?? storeContext
        let descriptor = FetchDescriptor<SavedSpread>(
            predicate: #Predicate { $0.pokemonID == pokemonID },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        return (try? context.fetch(descriptor)) ?? []
    }

    /// No investment, full investment, then the Pokémon's saved sets,
    /// newest first.
    static func statsChoices(for pokemonID: Int?, in store: ModelContext? = nil) throws -> [StatsEntity] {
        let context = store ?? storeContext
        let sets = pokemonID.map { sets(for: $0, in: context) } ?? []
        return [.noInvestment, .fullInvestment] + sets.compactMap(statsEntity)
    }

    static func statsEntities(ids: [String]) throws -> [StatsEntity] {
        ids.compactMap { id in
            switch id {
            case StatsEntity.noInvestment.id: return .noInvestment
            case StatsEntity.fullInvestment.id: return .fullInvestment
            default:
                guard case .savedSet(let identifier) = StatsEntity(id: id, title: "", subtitle: "").choice,
                      let spread = try? storeContext.fetch(FetchDescriptor<SavedSpread>(
                          predicate: #Predicate { $0.persistentModelID == identifier })).first
                else { return nil }
                return statsEntity(spread)
            }
        }
    }
}
