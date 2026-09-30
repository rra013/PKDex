//
//  ProblemSolverView.swift
//  PKReference
//
//  The Problem Solver tab: the set to beat, edited like a side of the calc,
//  and the Pokémon, moves and investments that knock it out in one hit,
//  guaranteed, under Champions doubles rules (`ProblemSolver`). Each answer
//  opens in the damage calc exactly as solved, or saves as a set.
//  ProblemSolver-PLAN.md has the plan.
//

import SwiftUI
import SwiftData

// MARK: - Solving

/// Runs the solver for the screen: off the main thread, with the
/// candidates built once per regulation. A new solve cancels the last.
@MainActor @Observable
final class ProblemSolverModel {
    enum Status: Equatable {
        /// No Pokémon to beat yet.
        case waiting
        case solving
        case solved
    }

    private(set) var status: Status = .waiting
    private(set) var counters: [ProblemSolver.Counter] = []
    private(set) var candidateCount = 0
    private var candidates: [ChampionsRegulation: [ProblemSolver.Candidate]] = [:]

    func solve(_ problem: ProblemSolver.Problem?, regulation: ChampionsRegulation, context: ModelContext) async {
        guard let problem else {
            status = .waiting
            counters = []
            return
        }
        status = .solving
        let list = candidates[regulation] ?? ProblemSolver.candidates(for: regulation, in: context)
        candidates[regulation] = list
        candidateCount = list.count
        let found = await Self.run(problem, list)
        guard !Task.isCancelled else { return }
        counters = found
        status = .solved
    }

    @concurrent
    nonisolated private static func run(_ problem: ProblemSolver.Problem,
                                        _ candidates: [ProblemSolver.Candidate]) async -> [ProblemSolver.Counter] {
        ProblemSolver.solve(problem, candidates: candidates, isCancelled: { Task.isCancelled })
    }
}

// MARK: - Screen

struct ProblemSolverView: View {
    @Query(sort: \PKMNStats.name) private var allPokemon: [PKMNStats]
    @Query(sort: \MoveData.name) private var allMoves: [MoveData]
    @AppStorage(ChampionsRegulation.userDefaultsKey) private var regulationRaw = ChampionsRegulation.latest.rawValue
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var hSize

    @State private var problem = ProblemSolverView.newProblem()
    @State private var model = ProblemSolverModel()
    @State private var intimidate = true
    @State private var weather: WeatherCondition = .none
    @State private var terrain: TerrainCondition = .none
    @State private var helpingHand = false
    @State private var tailwind = false
    @State private var trickRoom = false
    /// Wide layouts show the chosen answer above the list.
    @State private var selected: ProblemSolver.Counter?

    private var regulation: ChampionsRegulation { ChampionsRegulation(rawValue: regulationRaw) ?? .current }

    /// A Pokémon to beat starts on Champions rules, like the rest of the
    /// screen.
    static func newProblem() -> CalcSide {
        let side = CalcSide()
        side.setChampionsMode(true)
        return side
    }

    /// The set to beat on the field chosen; nil without a Pokémon.
    private var rules: ProblemSolver.Problem? {
        problem.snapshot().map {
            ProblemSolver.Problem(defender: $0, intimidate: intimidate, weather: weather, terrain: terrain,
                                  helpingHand: helpingHand, tailwind: tailwind, trickRoom: trickRoom)
        }
    }

    private struct SolveKey: Equatable {
        let problem: CalcSnapshot?
        let intimidate, helpingHand, tailwind, trickRoom: Bool
        let weather: WeatherCondition
        let terrain: TerrainCondition
        let regulation: ChampionsRegulation
    }

    private var solveKey: SolveKey {
        SolveKey(problem: problem.snapshot(), intimidate: intimidate, helpingHand: helpingHand,
                 tailwind: tailwind, trickRoom: trickRoom, weather: weather, terrain: terrain,
                 regulation: regulation)
    }

    var body: some View {
        TabNavigationStack {
            ScrollView {
                Group {
                    if allPokemon.isEmpty {
                        SectionCard(title: "Problem Solver", icon: "scope") {
                            Text("Downloading Pokémon and move data. This only happens once.")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    } else if hSize == .regular {
                        HStack(alignment: .top, spacing: 16) {
                            CardStack {
                                problemCard
                                rulesCard
                            }
                            .frame(maxWidth: .infinity, alignment: .top)
                            CardStack {
                                if let selected {
                                    CounterDetailCard(counter: selected, problem: problem, rules: rules)
                                }
                                resultsCard(wide: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .top)
                        }
                    } else {
                        CardStack {
                            problemCard
                            rulesCard
                            resultsCard(wide: false)
                        }
                    }
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Problem Solver")
            .cardPage()
            .navigationDestination(for: ProblemSolver.Counter.self) { counter in
                ScrollView {
                    CardStack { CounterDetailCard(counter: counter, problem: problem, rules: rules) }
                        .padding()
                }
                .navigationTitle(counter.name)
                .cardPage()
            }
            .task(id: solveKey) {
                // Let a burst of edits settle before searching.
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { return }
                await model.solve(rules, regulation: regulation, context: modelContext)
            }
            .onChange(of: model.counters) {
                if let selected, !model.counters.contains(selected) { self.selected = nil }
                #if DEBUG && os(macOS)
                // `-debugOpenFirst YES`: show the first answer, for snapshots.
                if selected == nil, UserDefaults.standard.bool(forKey: "debugOpenFirst") {
                    selected = model.counters.first
                }
                #endif
            }
            .onChange(of: problem.championsMode) {
                // The solver works on Champions rules only.
                if !problem.championsMode { problem.setChampionsMode(true) }
            }
            .onChange(of: AppNavigator.shared.request, initial: true) { openRequestedProblem() }
        }
    }

    /// Loads the set an App Intent or launch argument asked to beat.
    private func openRequestedProblem() {
        guard case .problemSolver(let setup) = AppNavigator.shared.request else { return }
        AppNavigator.shared.request = nil
        let side = Self.newProblem()
        if setup.apply(to: side, allPokemon: allPokemon, allMoves: allMoves) {
            problem = side
            selected = nil
        }
    }

    private var problemCard: some View {
        SideCard(title: "Problem", role: .side2, side: problem, allPokemon: allPokemon, allMoves: allMoves,
                 icon: "target")
    }

    private var rulesCard: some View {
        SectionCard(title: "Rules", icon: "list.bullet.clipboard") {
            Text("\(regulation.displayName), doubles: spread moves do 0.75×. Only guaranteed one-hit KOs count, from the lowest damage roll.")
                .font(.subheadline).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if problem.selectedAbility == "intimidate" {
                Toggle("Its Intimidate lowers the counters' Attack", isOn: $intimidate)
                    .font(.subheadline)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Weather").font(.subheadline).foregroundStyle(.secondary)
                Picker("Weather", selection: $weather) {
                    ForEach(WeatherCondition.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Terrain").font(.subheadline).foregroundStyle(.secondary)
                Picker("Terrain", selection: $terrain) {
                    ForEach(TerrainCondition.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                if rules?.blocksPriority == true {
                    Text("Psychic Terrain stops priority moves hitting \(problem.effectiveDisplayName).")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Toggle("Helping Hand from a partner", isOn: $helpingHand).font(.subheadline)
            Toggle("Tailwind on your side", isOn: $tailwind).font(.subheadline)
            Toggle("Trick Room", isOn: $trickRoom).font(.subheadline)
        }
    }

    private func resultsCard(wide: Bool) -> some View {
        CountersCard(model: model, problemName: problem.effectiveDisplayName,
                     regulation: regulation, trickRoom: trickRoom, wide: wide, selected: $selected)
    }
}

// MARK: - Results

private struct CountersCard: View {
    let model: ProblemSolverModel
    let problemName: String
    let regulation: ChampionsRegulation
    let trickRoom: Bool
    let wide: Bool
    @Binding var selected: ProblemSolver.Counter?

    @State private var filter = ""
    @State private var showingAll: Set<ProblemSolver.Group> = []
    /// Pokémon whose other answers are showing.
    @State private var expanded: Set<String> = []

    private static let firstShown = 25

    private var filtered: [ProblemSolver.Counter] {
        let wanted = IntentNames.key(filter)
        guard !wanted.isEmpty else { return model.counters }
        return model.counters.filter {
            IntentNames.key($0.name).contains(wanted) || IntentNames.key($0.move.name).contains(wanted)
        }
    }

    var body: some View {
        SectionCard(title: "Counters", icon: "scope") {
            switch model.status {
            case .waiting:
                Text("Choose the Pokémon to beat.")
                    .font(.subheadline).foregroundStyle(.secondary)
            case .solving:
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Checking \(model.candidateCount.formatted()) Pokémon, abilities and moves…")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            case .solved:
                if model.counters.isEmpty {
                    Text("Nothing in \(regulation.displayName) knocks out \(problemName) in one hit, guaranteed.")
                        .font(.subheadline).foregroundStyle(.secondary)
                } else {
                    results
                }
            }
        }
    }

    @ViewBuilder
    private var results: some View {
        let pokemon = Set(model.counters.map(\.name)).count
        Text("\(pokemon.formatted()) Pokémon can knock out \(problemName) in one hit, \(model.counters.count.formatted()) ways.")
            .font(.subheadline).foregroundStyle(.secondary)
        TextField("Filter by Pokémon or move", text: $filter)
            .textFieldStyle(.roundedBorder)
        let counters = filtered
        ForEach(ProblemSolver.Group.allCases, id: \.self) { group in
            let members = ProblemSolver.byPokemon(counters.filter { $0.group == group })
            if !members.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Divider()
                    HStack(alignment: .firstTextBaseline) {
                        Text(group.title(trickRoom: trickRoom)).font(.headline)
                        Spacer()
                        Text("\(members.count) Pokémon").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    Text(group.explanation(problemName, trickRoom: trickRoom))
                        .font(.caption).foregroundStyle(.secondary)
                    let shown = showingAll.contains(group) ? members : Array(members.prefix(Self.firstShown))
                    ForEach(shown, id: \.first!.id) { answers in
                        pokemonRows(answers)
                    }
                    if shown.count < members.count {
                        Button("Show all \(members.count)") { showingAll.insert(group) }
                            .font(.subheadline)
                    }
                }
            }
        }
    }

    /// A Pokémon's best answer, then its others when opened.
    @ViewBuilder
    private func pokemonRows(_ answers: [ProblemSolver.Counter]) -> some View {
        let best = answers[0]
        row(best)
        if answers.count > 1 {
            let open = expanded.contains(best.name)
            if open {
                ForEach(answers.dropFirst()) { row($0).padding(.leading, 12) }
            }
            Button {
                if open { expanded.remove(best.name) } else { expanded.insert(best.name) }
            } label: {
                Text(open ? "Fewer" : "\(answers.count - 1) more: \(answers.dropFirst().map(\.move.name).joined(separator: ", "))")
                    .font(.caption)
                    .lineLimit(1)
            }
            .buttonStyle(.borderless)
            .padding(.leading, 12)
        }
    }

    @ViewBuilder
    private func row(_ counter: ProblemSolver.Counter) -> some View {
        if wide {
            Button { selected = counter } label: {
                CounterRow(counter: counter)
                    .padding(6)
                    .background(selected?.id == counter.id ? Color.accentColor.opacity(0.15) : .clear,
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink(value: counter) { CounterRow(counter: counter) }
                .buttonStyle(.plain)
        }
    }
}

private struct CounterRow: View {
    let counter: ProblemSolver.Counter

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                // The badges wrap under a long name rather than splitting it.
                FlowLayout(spacing: 4) {
                    Text(counter.name).font(.subheadline.bold()).fixedSize()
                    ForEach(counter.attacker.effectiveTypes, id: \.self) { TypeBadge(type: $0) }
                }
                Text("\(counter.move.name) · \(counter.itemName)")
                    .font(.caption)
                Text(counter.pointsLabel)
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                if !counter.notes.isEmpty {
                    Text(counter.notes.joined(separator: " · "))
                        .font(.caption2).foregroundStyle(.orange)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                Text(counter.percentLabel)
                    .font(.caption.monospacedDigit())
                if counter.group != .priority {
                    Text("Spe \(counter.speed)")
                        .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Detail

private struct CounterDetailCard: View {
    let counter: ProblemSolver.Counter
    let problem: CalcSide
    /// The field it was solved on.
    let rules: ProblemSolver.Problem?

    @Environment(\.modelContext) private var modelContext
    @State private var naming = false
    @State private var setName = ""
    @State private var saved = false

    var body: some View {
        SectionCard(title: counter.name, icon: "scope", types: counter.attacker.effectiveTypes) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(counter.move.name).font(.headline)
                    TypeBadge(type: counter.move.type)
                    DamageClassBadge(damageClass: counter.move.damageClass)
                }
                detail("Item", counter.itemName)
                detail(counter.abilities.count > 1 ? "Abilities" : "Ability",
                       counter.abilities.map(formatAbilityName).joined(separator: " or "))
                detail("Nature", counter.attacker.nature.name)
                detail("Stat points", counter.pointsLabel)
                if counter.attacker.atkStage != 0 || counter.attacker.spAtkStage != 0 {
                    detail("After Intimidate", counter.stagesLabel)
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 4) {
                Text("\(Int(counter.outcome.damageMin))–\(Int(counter.outcome.damageMax)) damage (\(counter.percentLabel)) of \(counter.outcome.defenderHP) HP: a guaranteed one-hit KO.")
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                Text(counter.speedLabel(against: ProblemSolver.speed(problemSnapshot, fieldSnapshot),
                                        problemName: problem.effectiveDisplayName,
                                        trickRoom: rules?.trickRoom ?? false))
                    .font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(counter.notes, id: \.self) { note in
                    Label(note, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                }
            }
            Divider()
            HStack {
                Button {
                    guard let defender = SideSetup(problem) else { return }
                    AppNavigator.shared.request = .calcSides(CalcSides(
                        attacker: SideSetup(counter.attacker, pokemonID: counter.pokemonID),
                        defender: defender, doubles: true,
                        weather: fieldSnapshot.weather, terrain: fieldSnapshot.terrain))
                } label: {
                    Label("Open in Damage Calc", systemImage: "bolt.fill").frame(maxWidth: .infinity)
                }
                Button {
                    setName = "\(counter.name) vs \(problem.effectiveDisplayName)"
                    naming = true
                } label: {
                    Label(saved ? "Saved" : "Save as Set", systemImage: saved ? "checkmark" : "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .disabled(saved)
            }
            .buttonStyle(.bordered)
        }
        .alert("Save as Set", isPresented: $naming) {
            TextField("Name", text: $setName)
            Button("Save") { save() }
            Button("Cancel", role: .cancel) {}
        }
        .onChange(of: counter.id) { saved = false }
    }

    private var problemSnapshot: CalcSnapshot {
        problem.snapshot() ?? counter.attacker
    }

    private var fieldSnapshot: FieldSnapshot {
        rules?.field ?? ProblemSolver.Problem(defender: problemSnapshot).field
    }

    private func detail(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(.caption).foregroundStyle(.secondary)
                .frame(width: 96, alignment: .leading)
            Text(value).font(.subheadline)
        }
    }

    private func save() {
        let name = setName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        modelContext.insert(counter.savedSpread(named: name))
        saved = true
    }
}

// MARK: - Wording

extension ProblemSolver.Group {
    func title(trickRoom: Bool) -> String {
        switch self {
        case .outspeeds: trickRoom ? "Moves first in Trick Room, and OHKOs" : "Outspeeds and OHKOs"
        case .priority: "OHKOs with priority"
        case .slower: trickRoom ? "OHKOs but moves later" : "OHKOs but slower"
        }
    }

    func explanation(_ problemName: String, trickRoom: Bool) -> String {
        switch self {
        case .outspeeds where trickRoom:
            "Slower than \(problemName), so under Trick Room it knocks it out before it moves."
        case .outspeeds: "Faster than \(problemName), so it knocks it out before it moves."
        case .priority: "A priority move goes first, whatever the Speeds."
        case .slower where trickRoom: "Too fast for Trick Room: it needs a switch-in to land the hit."
        case .slower: "Needs Trick Room, Tailwind or a switch-in to land the hit."
        }
    }
}

extension ProblemSolver.Counter {
    /// The item held: the move's booster, Choice Scarf, or a Mega's stone.
    var itemName: String {
        attacker.heldItem == .none ? "No item" : attacker.heldItem.rawValue
    }

    /// "28 SpA / 20 Spe", or "No investment needed".
    var pointsLabel: String {
        var parts: [String] = []
        if let attackStat, attackPoints > 0 { parts.append("\(attackPoints) \(attackStat.short)") }
        if let speedPoints, speedPoints > 0 { parts.append("\(speedPoints) Spe") }
        return parts.isEmpty ? "No investment needed" : parts.joined(separator: " / ")
    }

    /// "112.4% – 132.7%".
    var percentLabel: String {
        let hp = Double(max(outcome.defenderHP, 1))
        return "\(DamageAnswer.percent(outcome.damageMin / hp * 100)) – \(DamageAnswer.percent(outcome.damageMax / hp * 100))"
    }

    /// "Atk -1" or "Atk +1, SpA +2".
    var stagesLabel: String {
        [("Atk", attacker.atkStage), ("SpA", attacker.spAtkStage), ("Spe", attacker.speedStage)]
            .filter { $0.1 != 0 }
            .map { "\($0.0) \($0.1 > 0 ? "+" : "")\($0.1)" }
            .joined(separator: ", ")
    }

    func speedLabel(against target: Int, problemName: String, trickRoom: Bool = false) -> String {
        switch group {
        case .outspeeds where trickRoom:
            "Speed \(speed), slower than \(problemName)'s \(target), so it moves first in Trick Room."
        case .outspeeds: "Speed \(speed), faster than \(problemName)'s \(target)."
        case .priority: "\(move.name) has priority, so Speed doesn't matter."
        case .slower where marks.contains(.movesLast): "\(move.name) moves last, whatever the Speeds."
        case .slower where trickRoom:
            "Speed \(speed), not slower than \(problemName)'s \(target), so it moves later in Trick Room."
        case .slower: "Speed \(speed), slower than \(problemName)'s \(target)."
        }
    }

    /// Accuracy under 100% and each mark, as the results say them.
    var notes: [String] {
        var notes: [String] = []
        if let accuracy, accuracy < 100 { notes.append("\(accuracy)% accurate") }
        let order: [(ProblemSolver.Mark, String)] = [
            (.mustRecharge, "Must recharge"), (.faintsUser, "Faints the user"), (.chargesFirst, "Charges first"),
            (.firstTurnOnly, "First turn only"), (.failsIfHit, "Fails if hit first"), (.movesLast, "Moves last"),
            (.speedTie, "Can only tie on Speed"),
        ]
        notes += order.filter { marks.contains($0.0) }.map(\.1)
        return notes
    }

    /// This answer as a saved set: its Pokémon, ability, item, nature,
    /// points and move, on Champions rules.
    func savedSpread(named name: String) -> SavedSpread {
        SavedSpread(
            name: name, pokemonID: pokemonID, pokemonName: attacker.species.name,
            abilityName: attacker.selectedAbility,
            itemRawValue: attacker.heldItem == .none ? nil : attacker.heldItem.rawValue,
            championsMode: attacker.championsMode, natureID: attacker.nature.id, level: attacker.level,
            evHP: attacker.evHP, evAtk: attacker.evAtk, evDef: attacker.evDef,
            evSpAtk: attacker.evSpAtk, evSpDef: attacker.evSpDef, evSpeed: attacker.evSpeed,
            moveID1: move.id)
    }
}

extension EVSolver.Stat {
    var short: String {
        switch self {
        case .hp: "HP"
        case .atk: "Atk"
        case .def: "Def"
        case .spAtk: "SpA"
        case .spDef: "SpD"
        case .speed: "Spe"
        }
    }
}
