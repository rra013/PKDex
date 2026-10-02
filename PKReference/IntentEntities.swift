//
//  IntentEntities.swift
//  PKReference
//
//  The things App Intents act on, and how Siri, Spotlight and Shortcuts
//  find them: Pokémon and moves by name; a side's stats for the damage calc
//  and a Pokémon's Speed for Compare Speed, each from a short list (no
//  investment, full investment, or a saved set of that Pokémon); and
//  Champions regulations. Saved sets and teams are in `SavedIntents.swift`.
//  The store is read on the main actor, through `IntentData`.
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

    /// "none", "full", "boosted", or "set:" and the saved set's encoded
    /// identifier.
    let id: String
    let title: String
    let subtitle: String
    /// Other ways to say it, for answering Siri's question: "max def".
    var synonyms: [String] = []

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(subtitle)", image: nil,
                              synonyms: synonyms.map { "\($0)" })
    }

    static let noInvestment = StatsEntity(
        id: "none", title: "No investment",
        subtitle: "No EVs or stat points, a neutral nature, level 50",
        synonyms: ["Uninvested", "No EVs", "No stat points"])
    static let fullInvestment = StatsEntity(
        id: "full", title: "Full investment",
        subtitle: "Full EVs or stat points in the attacking stat, or HP and the matching defense; a neutral nature, level 50",
        synonyms: ["Max", "Maxed", "Max attack", "Max special attack", "Max defense", "Max def",
                   "Max special defense", "Max bulk", "Fully invested"])
    static let fullInvestmentBoostingNature = StatsEntity(
        id: "boosted", title: "Full investment and a boosting nature",
        subtitle: "As full investment, with a nature that raises that stat: Adamant or Modest attacking, Bold or Calm defending; level 50",
        synonyms: ["Max with a plus nature", "Max plus", "Max with nature", "Max boosted",
                   "Adamant", "Modest", "Bold", "Calm"])

    static let fixed = [noInvestment, fullInvestment, fullInvestmentBoostingNature]

    var choice: StatChoice? {
        switch id {
        case "none": return .noInvestment
        case "full": return .fullInvestment
        case "boosted": return .fullInvestmentBoostingNature
        default: return StoredID.set(from: id).map { .savedSet($0) }
        }
    }

    static func setID(_ identifier: PersistentIdentifier) -> String? {
        StoredID.text(identifier).map { "set:" + $0 }
    }
}

nonisolated struct StatsQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [StatsEntity] {
        try await IntentData.statsEntities(ids: identifiers)
    }

    /// "max def" is full investment; a saved set by its name.
    func entities(matching string: String) async throws -> [StatsEntity] {
        await IntentData.statsEntities(matching: string)
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

/// A saved set's or team's identifier as text, for an entity's id.
nonisolated enum StoredID {
    static func text(_ identifier: PersistentIdentifier) -> String? {
        // Sorted keys, so the same set always gets the same text.
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return (try? encoder.encode(identifier))?.base64EncodedString()
    }

    static func identifier(_ text: String) -> PersistentIdentifier? {
        Data(base64Encoded: text).flatMap { try? JSONDecoder().decode(PersistentIdentifier.self, from: $0) }
    }

    /// A saved set among a side's stat choices: "set:" and its identifier.
    static func set(from choiceID: String) -> PersistentIdentifier? {
        guard choiceID.hasPrefix("set:") else { return nil }
        return identifier(String(choiceID.dropFirst("set:".count)))
    }
}

// MARK: - Speed

/// A Pokémon's Speed in Compare Speed. As in the calc, Siri asks for each
/// Pokémon's and offers these.
nonisolated struct SpeedStatsEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Speed"
    static let defaultQuery = SpeedStatsQuery()

    /// "none", "full", "fast", or "set:" and the saved set's encoded
    /// identifier.
    let id: String
    let title: String
    let subtitle: String
    /// Other ways to say it, for answering Siri's question: "max Speed".
    var synonyms: [String] = []

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(subtitle)", image: nil,
                              synonyms: synonyms.map { "\($0)" })
    }

    static let noInvestment = SpeedStatsEntity(
        id: "none", title: "No investment",
        subtitle: "No Speed EVs or stat points, a neutral nature, level 50",
        synonyms: ["Uninvested", "No Speed EVs", "No stat points"])
    static let fullInvestment = SpeedStatsEntity(
        id: "full", title: "Full investment",
        subtitle: "Full Speed EVs or stat points, a neutral nature, level 50",
        synonyms: ["Max", "Max Speed", "Maxed", "Fully invested"])
    static let fullInvestmentSpeedNature = SpeedStatsEntity(
        id: "fast", title: "Full investment and a Speed nature",
        subtitle: "Full Speed EVs or stat points and a nature that raises Speed, level 50",
        synonyms: ["Max Speed with a plus nature", "Max plus", "Max with nature", "Jolly", "Timid", "Fastest"])

    static let fixed = [noInvestment, fullInvestment, fullInvestmentSpeedNature]

    var choice: SpeedChoice? {
        switch id {
        case "none": return .noInvestment
        case "full": return .fullInvestment
        case "fast": return .fullInvestmentSpeedNature
        default: return StoredID.set(from: id).map { .savedSet($0) }
        }
    }
}

nonisolated struct SpeedStatsQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [SpeedStatsEntity] {
        await IntentData.speedStatsEntities(ids: identifiers)
    }

    /// "max Speed" is full investment; a saved set by its name.
    func entities(matching string: String) async throws -> [SpeedStatsEntity] {
        await IntentData.speedStatsEntities(matching: string)
    }
}

nonisolated struct FirstSpeedOptions: DynamicOptionsProvider {
    @IntentParameterDependency<CompareSpeedIntent>(\.$first) var comparison

    func results() async throws -> [SpeedStatsEntity] {
        await IntentData.speedChoices(for: comparison?.first.id)
    }
}

nonisolated struct SecondSpeedOptions: DynamicOptionsProvider {
    @IntentParameterDependency<CompareSpeedIntent>(\.$second) var comparison

    func results() async throws -> [SpeedStatsEntity] {
        await IntentData.speedChoices(for: comparison?.second.id)
    }
}

// MARK: - The Pokémon to beat

/// The investment of the Pokémon to beat, in Find Counters. Siri asks for
/// it each time and offers these.
nonisolated struct TargetStatsEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Stats"
    static let defaultQuery = TargetStatsQuery()

    /// "none", "physical", "special", or "set:" and the saved set's encoded
    /// identifier.
    let id: String
    let title: String
    let subtitle: String
    /// Other ways to say it, for answering Siri's question: "max def".
    var synonyms: [String] = []

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(subtitle)", image: nil,
                              synonyms: synonyms.map { "\($0)" })
    }

    static let noInvestment = TargetStatsEntity(
        id: "none", title: "No investment",
        subtitle: "No EVs or stat points, a neutral nature, level 50",
        synonyms: ["Uninvested", "No EVs", "No stat points"])
    static let physicallyBulky = TargetStatsEntity(
        id: "physical", title: "Full HP and Defense",
        subtitle: "Full HP and Defense stat points, a neutral nature, level 50",
        synonyms: ["Max Defense", "Max Def", "Max HP and Defense", "Physically bulky", "Physical bulk"])
    static let speciallyBulky = TargetStatsEntity(
        id: "special", title: "Full HP and Sp. Def",
        subtitle: "Full HP and Special Defense stat points, a neutral nature, level 50",
        synonyms: ["Max Special Defense", "Max Sp. Def", "Max SpD", "Max HP and Special Defense",
                   "Specially bulky", "Special bulk"])

    static let fixed = [noInvestment, physicallyBulky, speciallyBulky]

    var choice: TargetStats? {
        switch id {
        case "none": return .noInvestment
        case "physical": return .physicallyBulky
        case "special": return .speciallyBulky
        default: return StoredID.set(from: id).map { .savedSet($0) }
        }
    }
}

nonisolated struct TargetStatsQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [TargetStatsEntity] {
        await IntentData.targetStatsEntities(ids: identifiers)
    }

    /// "max def" is full HP and Defense; a saved set by its name.
    func entities(matching string: String) async throws -> [TargetStatsEntity] {
        await IntentData.targetStatsEntities(matching: string)
    }
}

nonisolated struct TargetStatsOptions: DynamicOptionsProvider {
    @IntentParameterDependency<FindCountersIntent>(\.$pokemon) var counters

    func results() async throws -> [TargetStatsEntity] {
        await IntentData.targetStatsChoices(for: counters?.pokemon.id)
    }
}

// MARK: - Regulations

/// A Pokémon Champions regulation, for Check Legality. Every
/// `ChampionsRegulation` needs a case here too; `AppIntentsTests` checks.
nonisolated enum RegulationChoice: String, AppEnum {
    case mA = "m-a"
    case mB = "m-b"
    case mC = "m-c"

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Regulation"
    static let caseDisplayRepresentations: [RegulationChoice: DisplayRepresentation] = [
        .mA: "Regulation M-A",
        .mB: "Regulation M-B",
        .mC: "Regulation M-C",
    ]
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

    /// No investment, full investment, full investment and a boosting
    /// nature, then the Pokémon's saved sets, newest first.
    static func statsChoices(for pokemonID: Int?, in store: ModelContext? = nil) throws -> [StatsEntity] {
        let context = store ?? storeContext
        let sets = pokemonID.map { sets(for: $0, in: context) } ?? []
        return StatsEntity.fixed + sets.compactMap(statsEntity)
    }

    static func statsEntities(ids: [String]) throws -> [StatsEntity] {
        ids.compactMap { id in
            if let fixed = StatsEntity.fixed.first(where: { $0.id == id }) { return fixed }
            guard let identifier = StoredID.set(from: id), let spread = savedSpread(identifier) else { return nil }
            return statsEntity(spread)
        }
    }

    /// The investment `text` says, if it says one, then the saved sets its
    /// words name. A set may be another Pokémon's; the calc then says it
    /// couldn't use it.
    static func statsEntities(matching text: String, in store: ModelContext? = nil) -> [StatsEntity] {
        let fixed: StatsEntity? = switch IntentNames.investment(said: text) {
        case .uninvested: .noInvestment
        case .full: .fullInvestment
        case .fullWithNature: .fullInvestmentBoostingNature
        case nil: nil
        }
        return [fixed].compactMap { $0 } + setsNamed(text, in: store).compactMap(statsEntity)
    }

    /// Saved sets whose names match `text`, best first.
    private static func setsNamed(_ text: String, in store: ModelContext?) -> [SavedSpread] {
        let context = store ?? storeContext
        let all = (try? context.fetch(FetchDescriptor<SavedSpread>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)]))) ?? []
        let candidates = all.enumerated().map {
            IntentNames.Candidate(id: $0.offset, keys: [IntentNames.key($0.element.name)], length: $0.element.name.count)
        }
        return IntentNames.matches(text, in: candidates).map { all[$0] }
    }

    static func savedSpread(_ identifier: PersistentIdentifier, in store: ModelContext? = nil) -> SavedSpread? {
        let context = store ?? storeContext
        return try? context.fetch(FetchDescriptor<SavedSpread>(
            predicate: #Predicate { $0.persistentModelID == identifier })).first
    }

    // Speed

    static func speedStatsEntity(_ spread: SavedSpread) -> SpeedStatsEntity? {
        guard let id = StatsEntity.setID(spread.persistentModelID) else { return nil }
        var parts = ["Saved set"]
        if let nature = allNatures.first(where: { $0.id == spread.natureID }) { parts.append(nature.name) }
        parts.append(spread.championsMode ? "\(spread.evSpeed) Speed stat points" : "\(spread.evSpeed) Speed EVs")
        if spread.itemRawValue == HeldItem.choiceScarf.rawValue { parts.append("Choice Scarf") }
        return SpeedStatsEntity(id: id, title: spread.name, subtitle: parts.joined(separator: " · "))
    }

    /// No investment, full investment, full investment and a Speed nature,
    /// then the Pokémon's saved sets, newest first.
    static func speedChoices(for pokemonID: Int?, in store: ModelContext? = nil) -> [SpeedStatsEntity] {
        let context = store ?? storeContext
        let sets = pokemonID.map { sets(for: $0, in: context) } ?? []
        return SpeedStatsEntity.fixed + sets.compactMap(speedStatsEntity)
    }

    /// As `statsEntities(matching:)`, for Speed.
    static func speedStatsEntities(matching text: String, in store: ModelContext? = nil) -> [SpeedStatsEntity] {
        let fixed: SpeedStatsEntity? = switch IntentNames.investment(said: text) {
        case .uninvested: .noInvestment
        case .full: .fullInvestment
        case .fullWithNature: .fullInvestmentSpeedNature
        case nil: nil
        }
        return [fixed].compactMap { $0 } + setsNamed(text, in: store).compactMap(speedStatsEntity)
    }

    static func speedStatsEntities(ids: [String]) -> [SpeedStatsEntity] {
        ids.compactMap { id in
            if let fixed = SpeedStatsEntity.fixed.first(where: { $0.id == id }) { return fixed }
            guard let identifier = StoredID.set(from: id), let spread = savedSpread(identifier) else { return nil }
            return speedStatsEntity(spread)
        }
    }

    // The Pokémon to beat

    static func targetStatsEntity(_ spread: SavedSpread) -> TargetStatsEntity? {
        guard let id = StatsEntity.setID(spread.persistentModelID) else { return nil }
        var parts = ["Saved set"]
        if let ability = spread.abilityName { parts.append(formatAbilityName(ability)) }
        if let nature = allNatures.first(where: { $0.id == spread.natureID }) { parts.append(nature.name) }
        return TargetStatsEntity(id: id, title: spread.name, subtitle: parts.joined(separator: " · "))
    }

    /// No investment, full HP and Defense, full HP and Special Defense,
    /// then the Pokémon's saved sets, newest first.
    static func targetStatsChoices(for pokemonID: Int?, in store: ModelContext? = nil) -> [TargetStatsEntity] {
        let context = store ?? storeContext
        let sets = pokemonID.map { sets(for: $0, in: context) } ?? []
        return TargetStatsEntity.fixed + sets.compactMap(targetStatsEntity)
    }

    /// The bulk `text` says ("max def", "max SpD", "uninvested"), then the
    /// saved sets its words name.
    static func targetStatsEntities(matching text: String, in store: ModelContext? = nil) -> [TargetStatsEntity] {
        let said = IntentNames.key(text)
        let fixed: TargetStatsEntity?
        if IntentNames.investment(said: text) == .uninvested {
            fixed = .noInvestment
        } else if ["spd", "specialdef", "spdef", "specialbulk", "speciallybulk"].contains(where: said.contains) {
            fixed = .speciallyBulky
        } else if ["def", "physicalbulk", "physicallybulk"].contains(where: said.contains) {
            fixed = .physicallyBulky
        } else {
            fixed = nil
        }
        return [fixed].compactMap { $0 } + setsNamed(text, in: store).compactMap(targetStatsEntity)
    }

    static func targetStatsEntities(ids: [String]) -> [TargetStatsEntity] {
        ids.compactMap { id in
            if let fixed = TargetStatsEntity.fixed.first(where: { $0.id == id }) { return fixed }
            guard let identifier = StoredID.set(from: id), let spread = savedSpread(identifier) else { return nil }
            return targetStatsEntity(spread)
        }
    }
}
