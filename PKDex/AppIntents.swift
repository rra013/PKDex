//
//  AppIntents.swift
//  PKDex
//
//  The actions Siri, Spotlight and Shortcuts can run: look up a Pokémon,
//  calculate damage, and search tournament teams. Each answers in place,
//  with a spoken or shown answer and a snippet whose "Open in PK Reference"
//  button opens the page through an Open intent and `AppNavigator`. The
//  answers' wording is in `IntentAnswers.swift`; the entities are in
//  `IntentEntities.swift`. AppIntents-PLAN.md has the plan.
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
        "Runs PK Reference's damage calc: how much one Pokémon's move does to another, and how many hits it takes to knock it out.")

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
        AppShortcut(intent: CalculateDamageIntent(), phrases: [
            "\(.applicationName), calculate damage",
            "Calculate damage in \(.applicationName)",
            "Run a damage calc in \(.applicationName)",
        ], shortTitle: "Calculate Damage", systemImageName: "bolt.fill")
        AppShortcut(intent: SearchTeamsIntent(), phrases: [
            "\(.applicationName), search teams",
            "Search teams in \(.applicationName)",
            "Find teams in \(.applicationName)",
        ], shortTitle: "Search Teams", systemImageName: "sparkle.magnifyingglass")
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
        let defaultGeneration = UserDefaults.standard.string(forKey: AppSettings.defaultGeneration.name)
            ?? AppSettings.defaultGeneration.defaultValue
        let vm = DamageCalcVM()
        guard vm.load(request, championsMode: championsMode ?? (defaultGeneration == PokedexFilter.champions.rawValue),
                      context: context),
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

    /// "Sand Veil, no investment", or "Intimidate, your set Screenshot Test".
    private static func setup(_ side: CalcSide, _ choice: StatChoice) -> String {
        let ability = side.selectedAbility.map(formatAbilityName) ?? "no ability"
        switch choice {
        case .noInvestment: return "\(ability), no investment"
        case .fullInvestment: return "\(ability), full investment"
        case .savedSet: return "\(ability), your set \(side.loadedSpreadName ?? "")"
        }
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

// MARK: - Snippets

private struct OpenInAppLabel: View {
    var body: some View {
        Label("Open in PK Reference", systemImage: "arrow.up.forward.app")
            .frame(maxWidth: .infinity)
    }
}

struct PokemonSnippetView: View {
    let answer: PokemonLookupAnswer
    let pokemon: PokemonEntity

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text(answer.name).font(.headline)
                Spacer()
                ForEach(answer.types, id: \.self) { TypeBadge(type: $0) }
            }
            ForEach(answer.matchups, id: \.multiplier) { matchup in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(PokemonLookupAnswer.symbol(matchup.multiplier))
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(width: 64, alignment: .leading)
                    FlowLayout(spacing: 4) {
                        ForEach(matchup.types, id: \.self) { TypeBadge(type: $0) }
                    }
                }
            }
            Text("Base stat total: \(answer.baseStatTotal)")
                .font(.caption).foregroundStyle(.secondary)
            Button(intent: OpenPokemonIntent(target: pokemon)) { OpenInAppLabel() }
                .buttonStyle(.bordered)
        }
        .padding()
    }
}

struct DamageSnippetView: View {
    let answer: DamageAnswer
    let open: OpenCalcIntent

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(answer.attacker) → \(answer.defender)").font(.headline)
            Text(answer.move).font(.subheadline).foregroundStyle(.secondary)
            Text("\(DamageAnswer.percent(answer.minPercent)) – \(DamageAnswer.percent(answer.maxPercent))")
                .font(.title2.monospacedDigit().bold())
            if let knockOut = answer.knockOut {
                Text(knockOut.prefix(1).uppercased() + knockOut.dropFirst())
                    .font(.subheadline)
            }
            Text(answer.details).font(.caption).foregroundStyle(.secondary)
            Button(intent: open) { OpenInAppLabel() }
                .buttonStyle(.bordered)
        }
        .padding()
    }
}

struct TeamSearchSnippetView: View {
    let answer: TeamSearchAnswer

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(answer.compositions) compositions · \(answer.teams) teams").font(.headline)
            ForEach(Array(answer.top.enumerated()), id: \.offset) { _, composition in
                VStack(alignment: .leading, spacing: 2) {
                    Text(composition.species.joined(separator: ", ")).font(.subheadline)
                    Text("\(composition.teams) teams").font(.caption).foregroundStyle(.secondary)
                }
            }
            Button(intent: OpenTeamSearchIntent(query: answer.query)) { OpenInAppLabel() }
                .buttonStyle(.bordered)
        }
        .padding()
    }
}
