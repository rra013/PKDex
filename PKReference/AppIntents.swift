//
//  AppIntents.swift
//  PKReference
//
//  The actions Siri, Spotlight and Shortcuts can run: look up a Pokémon,
//  calculate damage, search tournament teams, compare speeds and check
//  legality. Each answers in place, with a spoken or shown answer and a
//  snippet whose "Open in PK Reference" button opens the page through an
//  Open intent and `AppNavigator`. The answers' wording is in
//  `IntentAnswers.swift`, the snippets in `IntentSnippets.swift`, and the
//  entities in `IntentEntities.swift`; saved sets and teams have their own
//  actions in `SavedIntents.swift`. AppIntents-PLAN.md has the plan.
//

import AppIntents
import SwiftData
import SwiftUI

// MARK: - Look Up Pokémon

struct LookUpPokemonIntent: AppIntent {
    static let title: LocalizedStringResource = "Look Up Pokémon"
    static let description = IntentDescription(
        "Says a Pokémon's types, what it's weak to and resists by type, and its base stat total.")

    @Parameter(title: "Pokémon", requestValueDialog: "Which Pokémon?")
    var pokemon: PokemonEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Look up \(\.$pokemon)")
    }

    init() {}

    init(pokemon: PokemonEntity) {
        self.pokemon = pokemon
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetIntent {
        let answer = try IntentData.lookup(pokemon.id)
        return .result(dialog: "\(answer.spoken)", snippetIntent: PokemonSnippetIntent(pokemon: pokemon))
    }
}

struct PokemonSnippetIntent: SnippetIntent {
    static let title: LocalizedStringResource = "Pokémon Summary"
    static let isDiscoverable = false

    @Parameter(title: "Pokémon")
    var pokemon: PokemonEntity

    init() {}

    init(pokemon: PokemonEntity) {
        self.pokemon = pokemon
    }

    @MainActor
    func perform() async throws -> some IntentResult & ShowsSnippetView {
        .result(view: PokemonSnippetView(answer: try IntentData.lookup(pokemon.id), pokemon: pokemon))
    }
}

struct OpenPokemonIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open Pokémon"
    static let description = IntentDescription("Opens a Pokémon's page in PK Reference.")

    @Parameter(title: "Pokémon")
    var target: PokemonEntity

    init() {}

    init(target: PokemonEntity) {
        self.target = target
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        AppNavigator.shared.request = .pokemon(speciesID: target.speciesID)
        return .result()
    }
}

// MARK: - Calculate Damage

struct CalculateDamageIntent: AppIntent {
    static let title: LocalizedStringResource = "Calculate Damage"
    static let description = IntentDescription(
        """
        Answers how much damage one Pokémon's move does to another, such as how much Incineroar's Darkest \
        Lariat does to a Farigiraf with maxed Defense: the damage as a share of the defender's HP, and how \
        many hits it takes to knock it out, from PK Reference's damage calc.
        """,
        searchKeywords: ["damage", "damage calc", "calc", "how much damage", "KO", "OHKO", "2HKO",
                         "one-hit KO", "percent", "rolls", "EVs"])

    @Parameter(title: "Attacker", requestValueDialog: "Which Pokémon is attacking?")
    var attacker: PokemonEntity

    @Parameter(title: "Move", requestValueDialog: "Which move?")
    var move: MoveEntity

    @Parameter(title: "Defender", requestValueDialog: "Which Pokémon is it attacking?")
    var defender: PokemonEntity

    @Parameter(title: "Attacker's Stats", requestValueDialog: "Which stats for the attacker?",
               optionsProvider: AttackerStatsOptions())
    var attackerStats: StatsEntity

    @Parameter(title: "Defender's Stats", requestValueDialog: "Which stats for the defender?",
               optionsProvider: DefenderStatsOptions())
    var defenderStats: StatsEntity

    static var parameterSummary: some ParameterSummary {
        Summary("\(\.$attacker)'s \(\.$move) against \(\.$defender)") {
            \.$attackerStats
            \.$defenderStats
        }
    }

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetIntent {
        let answer = try IntentData.damage(try request)
        return .result(dialog: "\(answer.spoken)", snippetIntent: DamageSnippetIntent(copying: self))
    }

    var request: CalcRequest {
        get throws {
            guard let attackerChoice = attackerStats.choice, let defenderChoice = defenderStats.choice else {
                throw IntentError.notFound("that saved set")
            }
            return CalcRequest(attackerID: attacker.id, attackerStats: attackerChoice,
                               defenderID: defender.id, defenderStats: defenderChoice, moveID: move.id)
        }
    }
}

struct DamageSnippetIntent: SnippetIntent {
    static let title: LocalizedStringResource = "Damage Summary"
    static let isDiscoverable = false

    @Parameter(title: "Attacker") var attacker: PokemonEntity
    @Parameter(title: "Move") var move: MoveEntity
    @Parameter(title: "Defender") var defender: PokemonEntity
    @Parameter(title: "Attacker's Stats") var attackerStats: StatsEntity
    @Parameter(title: "Defender's Stats") var defenderStats: StatsEntity

    init() {}

    init(copying calc: CalculateDamageIntent) {
        attacker = calc.attacker
        move = calc.move
        defender = calc.defender
        attackerStats = calc.attackerStats
        defenderStats = calc.defenderStats
    }

    @MainActor
    func perform() async throws -> some IntentResult & ShowsSnippetView {
        let open = OpenCalcIntent(attacker: attacker, move: move, defender: defender,
                                  attackerStats: attackerStats, defenderStats: defenderStats)
        return .result(view: DamageSnippetView(answer: try IntentData.damage(try open.request), open: open))
    }
}

struct OpenCalcIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Damage Calc"
    static let description = IntentDescription("Opens PK Reference's damage calc with both Pokémon loaded.")
    static let supportedModes: IntentModes = .foreground
    static let isDiscoverable = false

    @Parameter(title: "Attacker") var attacker: PokemonEntity
    @Parameter(title: "Move") var move: MoveEntity
    @Parameter(title: "Defender") var defender: PokemonEntity
    @Parameter(title: "Attacker's Stats") var attackerStats: StatsEntity
    @Parameter(title: "Defender's Stats") var defenderStats: StatsEntity

    init() {}

    init(attacker: PokemonEntity, move: MoveEntity, defender: PokemonEntity,
         attackerStats: StatsEntity, defenderStats: StatsEntity) {
        self.attacker = attacker
        self.move = move
        self.defender = defender
        self.attackerStats = attackerStats
        self.defenderStats = defenderStats
    }

    var request: CalcRequest {
        get throws {
            guard let attackerChoice = attackerStats.choice, let defenderChoice = defenderStats.choice else {
                throw IntentError.notFound("that saved set")
            }
            return CalcRequest(attackerID: attacker.id, attackerStats: attackerChoice,
                               defenderID: defender.id, defenderStats: defenderChoice, moveID: move.id)
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        AppNavigator.shared.request = .calc(try request)
        return .result()
    }
}

// MARK: - Search Teams

struct SearchTeamsIntent: AppIntent {
    static let title: LocalizedStringResource = "Search Teams"
    static let description = IntentDescription(
        "Finds the popular tournament team compositions that match a description, such as \"Trick Room with Mega Gardevoir, no Incineroar\".")

    @Parameter(title: "Search", requestValueDialog: "What kind of team?")
    var query: String

    static var parameterSummary: some ParameterSummary {
        Summary("Search teams for \(\.$query)")
    }

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetIntent {
        let answer = try await IntentData.teamSearch(query)
        return .result(dialog: "\(answer.spoken)", snippetIntent: TeamSearchSnippetIntent(query: query))
    }
}

struct TeamSearchSnippetIntent: SnippetIntent {
    static let title: LocalizedStringResource = "Team Search Summary"
    static let isDiscoverable = false

    @Parameter(title: "Search")
    var query: String

    init() {}

    init(query: String) {
        self.query = query
    }

    @MainActor
    func perform() async throws -> some IntentResult & ShowsSnippetView {
        .result(view: TeamSearchSnippetView(answer: try await IntentData.teamSearch(query)))
    }
}

struct OpenTeamSearchIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Team Search"
    static let description = IntentDescription("Opens PK Reference's Team Search with a search.")
    static let supportedModes: IntentModes = .foreground
    static let isDiscoverable = false

    @Parameter(title: "Search")
    var query: String

    init() {}

    init(query: String) {
        self.query = query
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        AppNavigator.shared.request = .teamSearch(query: query)
        return .result()
    }
}

// MARK: - Compare Speed

struct CompareSpeedIntent: AppIntent {
    static let title: LocalizedStringResource = "Compare Speed"
    static let description = IntentDescription(
        "Says which of two Pokémon is faster, with each one's Speed.")

    @Parameter(title: "Pokémon", requestValueDialog: "Which Pokémon?")
    var first: PokemonEntity

    @Parameter(title: "Compared With", requestValueDialog: "Compared with which Pokémon?")
    var second: PokemonEntity

    @Parameter(title: "First Pokémon's Speed", requestValueDialog: "Which Speed for the first Pokémon?",
               optionsProvider: FirstSpeedOptions())
    var firstStats: SpeedStatsEntity

    @Parameter(title: "Second Pokémon's Speed", requestValueDialog: "Which Speed for the second Pokémon?",
               optionsProvider: SecondSpeedOptions())
    var secondStats: SpeedStatsEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Is \(\.$first) faster than \(\.$second)") {
            \.$firstStats
            \.$secondStats
        }
    }

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetIntent {
        let answer = try IntentData.speed(try request)
        return .result(dialog: "\(answer.spoken)", snippetIntent: SpeedSnippetIntent(copying: self))
    }

    var request: SpeedRequest {
        get throws {
            try SpeedRequest(first: first, firstStats: firstStats, second: second, secondStats: secondStats)
        }
    }
}

extension SpeedRequest {
    init(first: PokemonEntity, firstStats: SpeedStatsEntity,
         second: PokemonEntity, secondStats: SpeedStatsEntity) throws {
        guard let firstChoice = firstStats.choice, let secondChoice = secondStats.choice else {
            throw IntentError.notFound("that saved set")
        }
        self.init(firstID: first.id, firstStats: firstChoice, secondID: second.id, secondStats: secondChoice)
    }
}

struct SpeedSnippetIntent: SnippetIntent {
    static let title: LocalizedStringResource = "Speed Comparison"
    static let isDiscoverable = false

    @Parameter(title: "Pokémon") var first: PokemonEntity
    @Parameter(title: "Compared With") var second: PokemonEntity
    @Parameter(title: "First Pokémon's Speed") var firstStats: SpeedStatsEntity
    @Parameter(title: "Second Pokémon's Speed") var secondStats: SpeedStatsEntity

    init() {}

    init(copying comparison: CompareSpeedIntent) {
        first = comparison.first
        second = comparison.second
        firstStats = comparison.firstStats
        secondStats = comparison.secondStats
    }

    @MainActor
    func perform() async throws -> some IntentResult & ShowsSnippetView {
        let open = OpenSpeedTiersIntent(first: first, second: second, firstStats: firstStats, secondStats: secondStats)
        return .result(view: SpeedSnippetView(answer: try IntentData.speed(try open.request), open: open))
    }
}

struct OpenSpeedTiersIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Speed Tiers"
    static let description = IntentDescription(
        "Opens PK Reference's Speed Tiers with the first Pokémon, and the second's investment as the benchmark.")
    static let supportedModes: IntentModes = .foreground
    static let isDiscoverable = false

    @Parameter(title: "Pokémon") var first: PokemonEntity
    @Parameter(title: "Compared With") var second: PokemonEntity
    @Parameter(title: "First Pokémon's Speed") var firstStats: SpeedStatsEntity
    @Parameter(title: "Second Pokémon's Speed") var secondStats: SpeedStatsEntity

    init() {}

    init(first: PokemonEntity, second: PokemonEntity, firstStats: SpeedStatsEntity, secondStats: SpeedStatsEntity) {
        self.first = first
        self.second = second
        self.firstStats = firstStats
        self.secondStats = secondStats
    }

    var request: SpeedRequest {
        get throws {
            try SpeedRequest(first: first, firstStats: firstStats, second: second, secondStats: secondStats)
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        AppNavigator.shared.request = .speed(try request)
        return .result()
    }
}

// MARK: - Check Legality

struct CheckLegalityIntent: AppIntent {
    static let title: LocalizedStringResource = "Check Legality"
    static let description = IntentDescription(
        "Says whether a Pokémon, or one of its forms or Megas, is allowed in a Pokémon Champions regulation, and why not when it isn't.")

    @Parameter(title: "Pokémon", requestValueDialog: "Which Pokémon?")
    var pokemon: PokemonEntity

    @Parameter(title: "Regulation",
               description: "Leave it empty for the regulation chosen in PK Reference's settings. The answer always names the regulation.")
    var regulation: RegulationChoice?

    static var parameterSummary: some ParameterSummary {
        Summary("Is \(\.$pokemon) legal in \(\.$regulation)")
    }

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetIntent {
        let answer = try IntentData.legality(pokemon.id, regulation: regulation)
        return .result(dialog: "\(answer.spoken)",
                       snippetIntent: LegalitySnippetIntent(pokemon: pokemon, regulation: regulation))
    }
}

struct LegalitySnippetIntent: SnippetIntent {
    static let title: LocalizedStringResource = "Legality"
    static let isDiscoverable = false

    @Parameter(title: "Pokémon") var pokemon: PokemonEntity
    @Parameter(title: "Regulation") var regulation: RegulationChoice?

    init() {}

    init(pokemon: PokemonEntity, regulation: RegulationChoice?) {
        self.pokemon = pokemon
        self.regulation = regulation
    }

    @MainActor
    func perform() async throws -> some IntentResult & ShowsSnippetView {
        .result(view: LegalitySnippetView(answer: try IntentData.legality(pokemon.id, regulation: regulation), pokemon: pokemon))
    }
}

// MARK: - Search in the app

/// The system's in-app search, which Siri and Spotlight use for "search PK
/// Reference for …" and for requests they route to the app's search. It
/// opens the app on the result: the Pokémon, move or ability the words
/// name, or the Mon Index filtered to them.
@AppIntent(schema: .system.search)
struct SearchPKReferenceIntent: ShowInAppSearchResultsIntent {
    static let searchScopes: [StringSearchScope] = [.general]

    var criteria: StringSearchCriteria

    @MainActor
    func perform() async throws -> some IntentResult {
        AppNavigator.shared.request = IntentData.searchRequest(for: criteria.term)
        return .result()
    }
}

// MARK: - Siri phrases

struct PKReferenceShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        // Every phrase names the app, as Siri requires; the ones starting
        // with it are the least likely to be answered from the web instead.
        AppShortcut(intent: LookUpPokemonIntent(), phrases: [
            "\(.applicationName), look up \(\.$pokemon)",
            "\(.applicationName), what is \(\.$pokemon) weak to",
            "Look up \(\.$pokemon) in \(.applicationName)",
            "What is \(\.$pokemon) weak to in \(.applicationName)",
            "\(.applicationName), look up a Pokémon",
            "Look up a Pokémon in \(.applicationName)",
        ], shortTitle: "Look Up Pokémon", systemImageName: "magnifyingglass")
        // A phrase can name only one Pokémon, so Siri asks for the move and
        // the other one.
        AppShortcut(intent: CalculateDamageIntent(), phrases: [
            "\(.applicationName), calculate damage",
            "\(.applicationName), how much damage does \(\.$attacker) do",
            "\(.applicationName), how much will \(\.$attacker) do",
            "\(.applicationName), how much damage does \(\.$defender) take",
            "Calculate damage in \(.applicationName)",
            "Run a damage calc in \(.applicationName)",
            "How much damage does \(\.$attacker) do in \(.applicationName)",
        ], shortTitle: "Calculate Damage", systemImageName: "bolt.fill")
        AppShortcut(intent: SearchTeamsIntent(), phrases: [
            "\(.applicationName), search teams",
            "Search teams in \(.applicationName)",
            "Find teams in \(.applicationName)",
        ], shortTitle: "Search Teams", systemImageName: "sparkle.magnifyingglass")
        // A phrase can name only one Pokémon, so Siri asks for the second.
        AppShortcut(intent: CompareSpeedIntent(), phrases: [
            "\(.applicationName), how fast is \(\.$first)",
            "\(.applicationName), compare speeds",
            "How fast is \(\.$first) in \(.applicationName)",
            "Compare speeds in \(.applicationName)",
        ], shortTitle: "Compare Speed", systemImageName: "hare")
        AppShortcut(intent: CheckLegalityIntent(), phrases: [
            "\(.applicationName), is \(\.$pokemon) legal",
            "\(.applicationName), check legality",
            "Check if \(\.$pokemon) is legal in \(.applicationName)",
            "Check legality in \(.applicationName)",
        ], shortTitle: "Check Legality", systemImageName: "checkmark.seal")
        AppShortcut(intent: ShowSetIntent(), phrases: [
            "\(.applicationName), show my set \(\.$savedSet)",
            "\(.applicationName), show a saved set",
            "Show my set \(\.$savedSet) in \(.applicationName)",
        ], shortTitle: "Show Saved Set", systemImageName: "square.and.pencil")
        AppShortcut(intent: LoadSetInCalcIntent(), phrases: [
            "\(.applicationName), load \(\.$savedSet) into the calc",
            "\(.applicationName), load a set into the calc",
            "Load \(\.$savedSet) into the calc in \(.applicationName)",
        ], shortTitle: "Load Set into Calc", systemImageName: "bolt.fill")
        AppShortcut(intent: SearchPKReferenceIntent(), phrases: [
            "Search in \(.applicationName)",
            "Search \(.applicationName)",
            "\(.applicationName), search the Pokédex",
        ], shortTitle: "Search", systemImageName: "magnifyingglass")
        AppShortcut(intent: ShowTeamIntent(), phrases: [
            "\(.applicationName), show my team \(\.$team)",
            "\(.applicationName), show a saved team",
            "Show my team \(\.$team) in \(.applicationName)",
        ], shortTitle: "Show Saved Team", systemImageName: "person.3")
    }
}

// MARK: - Answers from the store

extension IntentData {
    static func lookup(_ id: Int, in store: ModelContext? = nil) throws -> PokemonLookupAnswer {
        let context = store ?? storeContext
        let stats = try pokemon(id, in: context)
        return PokemonLookupAnswer(
            name: IntentNames.spoken(name: stats.name, formName: stats.formName),
            types: [stats.type1] + [stats.type2].compactMap { $0 },
            baseStats: [stats.baseHP, stats.baseAtk, stats.baseDef, stats.baseSpAtk, stats.baseSpDef, stats.baseSpeed])
    }

    /// The calc's answer, from the same view model the calc screen uses,
    /// with its default field: no weather, terrain or other effects. A side
    /// without a saved set follows the Default Generation setting, as the
    /// calc does, unless `championsMode` says otherwise.
    static func damage(_ request: CalcRequest, championsMode: Bool? = nil,
                       in store: ModelContext? = nil) throws -> DamageAnswer {
        let context = store ?? storeContext
        let vm = DamageCalcVM()
        guard vm.load(request, championsMode: championsMode ?? championsByDefault, context: context),
              let attacker = vm.side1.pokemon, let defender = vm.side2.pokemon,
              let result = vm.side1Results.first else {
            throw IntentError.notFound("those Pokémon, that move, or that saved set")
        }
        return DamageAnswer(
            attacker: IntentNames.spoken(name: attacker.name, formName: attacker.formName),
            defender: IntentNames.spoken(name: defender.name, formName: defender.formName),
            move: result.move.name,
            minPercent: result.minPercent, maxPercent: result.maxPercent,
            minDamage: Int(result.damageMin), maxDamage: Int(result.damageMax),
            attackerSetup: setup(vm.side1, request.attackerStats),
            defenderSetup: setup(vm.side2, request.defenderStats),
            championsRules: vm.side1.championsMode)
    }

    /// "Sand Veil, no investment", "Intimidate, full investment, Adamant
    /// nature", or "Intimidate, your set Screenshot Test".
    private static func setup(_ side: CalcSide, _ choice: StatChoice) -> String {
        let ability = side.selectedAbility.map(formatAbilityName) ?? "no ability"
        switch choice {
        case .noInvestment: return "\(ability), no investment"
        case .fullInvestment: return "\(ability), full investment"
        case .fullInvestmentBoostingNature: return "\(ability), full investment, \(side.nature.name) nature"
        case .savedSet: return "\(ability), your set \(side.loadedSpreadName ?? "")"
        }
    }

    /// Where a search goes: the page of the Pokémon it names (a form or
    /// Mega opens its species), else the Move or Ability Index on the move
    /// or ability it names, else the Mon Index filtered to it. Names match
    /// as Siri says them: case, accents, spaces and punctuation don't
    /// matter.
    static func searchRequest(for text: String, in store: ModelContext? = nil) -> AppNavigator.Request {
        let context = store ?? storeContext
        let term = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let wanted = IntentNames.key(term)
        guard !wanted.isEmpty else { return .indexSearch(.monIndex, "") }
        let pokemon = (try? context.fetch(FetchDescriptor<PKMNStats>())) ?? []
        if let named = pokemon.first(where: { IntentNames.keys(name: $0.name, formName: $0.formName).contains(wanted) }) {
            return .pokemon(speciesID: named.speciesID)
        }
        let moves = (try? context.fetch(FetchDescriptor<MoveData>())) ?? []
        if let move = moves.first(where: { IntentNames.key($0.name) == wanted }) {
            return .indexSearch(.moveIndex, move.name)
        }
        let abilities = Set(pokemon.flatMap(\.allAbilities).map(formatAbilityName))
        if let ability = abilities.first(where: { IntentNames.key($0) == wanted }) {
            return .indexSearch(.abilityIndex, ability)
        }
        return .indexSearch(.monIndex, term)
    }

    /// Whether a Pokémon without a saved set gets Champions rules: the
    /// Default Generation setting, as in the calc and Speed Tiers.
    static var championsByDefault: Bool {
        let defaultGeneration = UserDefaults.standard.string(forKey: AppSettings.defaultGeneration.name)
            ?? AppSettings.defaultGeneration.defaultValue
        return defaultGeneration == PokedexFilter.champions.rawValue
    }

    /// Which of two Pokémon is faster, each loaded as the calc loads a side.
    /// A Pokémon without a saved set follows the Default Generation setting
    /// unless `championsMode` says otherwise.
    static func speed(_ request: SpeedRequest, championsMode: Bool? = nil,
                      in store: ModelContext? = nil) throws -> SpeedAnswer {
        let context = store ?? storeContext
        let allPokemon = try allPokemon(in: context)
        let allMoves = (try? context.fetch(FetchDescriptor<MoveData>())) ?? []
        let mode = championsMode ?? championsByDefault
        let first = CalcSide(), second = CalcSide()
        guard first.load(pokemonID: request.firstID, speed: request.firstStats, championsMode: mode,
                         allPokemon: allPokemon, allMoves: allMoves, context: context),
              second.load(pokemonID: request.secondID, speed: request.secondStats, championsMode: mode,
                          allPokemon: allPokemon, allMoves: allMoves, context: context)
        else {
            throw IntentError.notFound("those Pokémon, or that saved set")
        }
        return SpeedAnswer(first: speedSide(first, request.firstStats),
                           second: speedSide(second, request.secondStats))
    }

    private static func speedSide(_ side: CalcSide, _ choice: SpeedChoice) -> SpeedAnswer.Side {
        let name = side.activeMegaForm?.displayName
            ?? side.pokemon.map { IntentNames.spoken(name: $0.name, formName: $0.formName) } ?? ""
        let setup: String
        switch choice {
        case .noInvestment: setup = "no investment"
        case .fullInvestment: setup = "full investment"
        case .fullInvestmentSpeedNature: setup = "full investment and a Speed nature"
        case .savedSet:
            var parts = ["your set \(side.loadedSpreadName ?? "")"]
            if side.holdsChoiceScarf { parts.append("with Choice Scarf") }
            setup = parts.joined(separator: ", ")
        }
        return SpeedAnswer.Side(name: name, speed: side.speedWithItem, setup: setup,
                                championsRules: side.championsMode)
    }

    /// Whether a Pokémon is in `choice`'s regulation, or the one chosen in
    /// Settings, from the files the validator reads.
    static func legality(_ id: Int, regulation choice: RegulationChoice?, in store: ModelContext? = nil,
                         now: Date = .now) throws -> LegalityAnswer {
        let context = store ?? storeContext
        let regulation = choice.flatMap { ChampionsRegulation(rawValue: $0.rawValue) } ?? .current
        let row = try pokemon(id, in: context)
        let speciesID = row.speciesID
        let baseRow = try allPokemon(in: context).first { $0.speciesID == speciesID && !$0.isForm }
        let dexName = try? context.fetch(FetchDescriptor<PKMN>(
            predicate: #Predicate { $0.nationalPokedexNumber == speciesID })).first?.name

        // The regulation's name for the species, whichever way the Pokédex
        // spells it: "Kommo-O" is its "Kommo-o", "Lycanroc-Midday" its
        // "Lycanroc". Champions' Floette is Eternal Floette, a form in the
        // Pokédex.
        let whitelist = regulation.speciesWhitelist()
        let listed: (String) -> String? = { name in
            whitelist.first { IntentNames.key($0) == IntentNames.key(name) }
        }
        let championsName = ChampionsFormat.canonicalChampionsSpecies(row.name)
        let isChampionsForm = championsName != row.name && listed(championsName) != nil
        let listedSpecies = [championsName, row.name, baseRow?.name, dexName].compactMap { $0 }
            .lazy.compactMap(listed).first

        let species = listedSpecies.flatMap { ChampionsLearnsetStore.store(for: regulation).data(for: $0) }
        let name = IntentNames.spoken(name: row.name, formName: row.formName)
        let verdict = PokemonLegality.verdict(
            formName: isChampionsForm ? nil : row.formName, spokenName: name, listedSpecies: listedSpecies,
            speciesName: baseRow.map { IntentNames.spoken(name: $0.name, formName: nil) } ?? name,
            rules: regulation.rules(),
            listing: species.map { .init(megas: $0.megas.map(\.name), forms: $0.alternateForms.map(\.name)) })
        return LegalityAnswer(
            name: name, regulation: regulation.displayName, verdict: verdict,
            schedule: LegalityAnswer.schedule(regulation: regulation.displayName, from: regulation.validFrom,
                                              until: regulation.validUntil, now: now))
    }

    /// The last search, so a snippet shown right after its answer doesn't
    /// load the tournament data again.
    private static var lastTeamSearch: TeamSearchAnswer?

    static func teamSearch(_ query: String) async throws -> TeamSearchAnswer {
        if let last = lastTeamSearch, last.query == query { return last }
        let model = TeamSearchModel()
        await model.load()
        if case .failed = model.status { throw IntentError.noTournamentData }
        model.setText(query)
        let results = model.results
        let answer = TeamSearchAnswer(
            query: query, compositions: results.count,
            teams: results.reduce(0) { $0 + $1.teams.count },
            top: results.prefix(3).map { .init(species: $0.species, teams: $0.teams.count) })
        lastTeamSearch = answer
        return answer
    }
}
