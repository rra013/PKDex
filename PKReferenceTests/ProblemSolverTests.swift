//
//  ProblemSolverTests.swift
//  PKReferenceTests
//
//  Covers the Problem Solver's search (ProblemSolver-PLAN.md): every answer
//  is a guaranteed OHKO by the calc itself, at the fewest points (one fewer
//  fails), in the right group; a resisted move isn't an answer; a Speed
//  nature or Choice Scarf is used when it's what moves first; the problem
//  set's Intimidate lowers or raises the counters' stats as their abilities
//  say; abilities with the same result are listed together; and moves with
//  drawbacks are marked. The Pokémon are in a store in memory, with their
//  real base stats. A timing test runs the whole regulation against the
//  simulator's downloaded Pokédex when it's there.
//

import Testing
import Foundation
import SwiftData
@testable import PKReference

@MainActor
@Suite("Problem Solver")
struct ProblemSolverTests {

    private struct Store {
        let container: ModelContainer
        let pokemon: [String: PKMNStats]
        let moves: [String: MoveData]
        var all: [PKMNStats] { Array(pokemon.values) }
    }

    private func store() throws -> Store {
        let container = try ModelContainer(
            for: PKMNStats.self, MoveData.self, SavedSpread.self, PKMN.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let rows = [
            PKMNStats(id: 445, speciesID: 445, name: "Garchomp", type1: "Dragon", type2: "Ground",
                      baseHP: 108, baseAtk: 130, baseDef: 95, baseSpAtk: 80, baseSpDef: 85, baseSpeed: 102,
                      ability1: "sand-veil", hiddenAbility: "rough-skin"),
            PKMNStats(id: 485, speciesID: 485, name: "Heatran", type1: "Fire", type2: "Steel",
                      baseHP: 91, baseAtk: 90, baseDef: 106, baseSpAtk: 130, baseSpDef: 106, baseSpeed: 77,
                      ability1: "flash-fire", hiddenAbility: "flame-body"),
            PKMNStats(id: 727, speciesID: 727, name: "Incineroar", type1: "Fire", type2: "Dark",
                      baseHP: 95, baseAtk: 115, baseDef: 90, baseSpAtk: 80, baseSpDef: 90, baseSpeed: 60,
                      ability1: "blaze", hiddenAbility: "intimidate"),
            PKMNStats(id: 983, speciesID: 983, name: "Kingambit", type1: "Dark", type2: "Steel",
                      baseHP: 100, baseAtk: 135, baseDef: 120, baseSpAtk: 60, baseSpDef: 85, baseSpeed: 50,
                      ability1: "defiant", ability2: "supreme-overlord", hiddenAbility: "pressure"),
            PKMNStats(id: 887, speciesID: 887, name: "Dragapult", type1: "Dragon", type2: "Ghost",
                      baseHP: 88, baseAtk: 120, baseDef: 75, baseSpAtk: 100, baseSpDef: 75, baseSpeed: 142,
                      ability1: "clear-body", ability2: "infiltrator", hiddenAbility: "cursed-body"),
            PKMNStats(id: 94, speciesID: 94, name: "Gengar", type1: "Ghost", type2: "Poison",
                      baseHP: 60, baseAtk: 65, baseDef: 60, baseSpAtk: 130, baseSpDef: 75, baseSpeed: 110,
                      ability1: "cursed-body"),
        ]
        let moves = [
            MoveData(id: 89, name: "Earthquake", type: "Ground", damageClass: "physical",
                     power: 100, accuracy: 100, pp: 10, generationId: 1),
            MoveData(id: 337, name: "Dragon Claw", type: "Dragon", damageClass: "physical",
                     power: 80, accuracy: 100, pp: 15, makesContact: true, generationId: 3),
            MoveData(id: 389, name: "Sucker Punch", type: "Dark", damageClass: "physical",
                     power: 70, accuracy: 100, pp: 5, priority: 1, makesContact: true, generationId: 4),
            MoveData(id: 264, name: "Focus Punch", type: "Fighting", damageClass: "physical",
                     power: 150, accuracy: 100, pp: 20, priority: -3, makesContact: true, generationId: 3),
        ]
        rows.forEach { context.insert($0) }
        moves.forEach { context.insert($0) }
        try context.save()
        return Store(container: container,
                     pokemon: Dictionary(uniqueKeysWithValues: rows.map { ($0.name, $0) }),
                     moves: Dictionary(uniqueKeysWithValues: moves.map { ($0.name, $0) }))
    }

    private func side(_ name: String, in store: Store, ability: String? = nil,
                      configure: (CalcSide) -> Void = { _ in }) throws -> CalcSide {
        let side = CalcSide()
        side.loadUninvested(try #require(store.pokemon[name]), championsMode: true, allPokemon: store.all)
        if let ability { side.selectedAbility = ability }
        configure(side)
        return side
    }

    private func candidate(_ name: String, _ move: String, in store: Store,
                           ability: String? = nil) throws -> ProblemSolver.Candidate {
        let move = try #require(store.moves[move])
        return ProblemSolver.Candidate(
            attacker: try #require(try side(name, in: store, ability: ability).snapshot()),
            move: move.snapshot(), accuracy: move.accuracy, priority: move.priority,
            marks: ProblemSolver.marks(for: move.name))
    }

    private func problem(_ name: String, in store: Store, ability: String? = nil, intimidate: Bool = true,
                         configure: (CalcSide) -> Void = { _ in }) throws -> ProblemSolver.Problem {
        ProblemSolver.Problem(
            defender: try #require(try side(name, in: store, ability: ability, configure: configure).snapshot()),
            intimidate: intimidate)
    }

    /// Every answer is a guaranteed OHKO by the calc, at the fewest points:
    /// one fewer attacking point fails, and one fewer Speed point doesn't
    /// outspeed.
    private func expectMinimal(_ counter: ProblemSolver.Counter, _ problem: ProblemSolver.Problem) {
        let damage = { (attacker: CalcSnapshot) in
            CalcEngine.evaluate(move: counter.move, attacker: attacker, defender: problem.defender,
                                field: problem.field)
        }
        #expect(damage(counter.attacker).isGuaranteedOHKO)
        if let stat = counter.attackStat?.natureKey, counter.attackPoints > 0 {
            #expect(!damage(counter.attacker.settingEV(stat, to: counter.attackPoints - 1)).isGuaranteedOHKO)
        }
        let target = ProblemSolver.speed(problem.defender, problem.field)
        if let points = counter.speedPoints {
            #expect(counter.speed > target)
            if points > 0 {
                #expect(ProblemSolver.speed(counter.attacker.settingEV(.speed, to: points - 1), problem.field) <= target)
            }
        }
    }

    // MARK: Finding answers

    /// Full HP and Defense Heatran: Garchomp's Earthquake, a spread move at
    /// 0.75×, still KOs, and Garchomp is faster.
    @Test("A guaranteed OHKO is found at its fewest points, and moves first")
    func findsOHKO() throws {
        let store = try store()
        let problem = try problem("Heatran", in: store) { $0.evHP = 32; $0.evDef = 32 }
        let counters = ProblemSolver.solve(problem, candidates: [
            try candidate("Garchomp", "Earthquake", in: store, ability: "rough-skin"),
        ])
        let counter = try #require(counters.first)
        #expect(counter.group == .outspeeds)
        #expect(counter.attacker.heldItem == .softSand)
        #expect(counter.attackStat == .atk)
        expectMinimal(counter, problem)
    }

    @Test("A resisted move that can't KO isn't an answer")
    func noKO() throws {
        let store = try store()
        let problem = try problem("Heatran", in: store)
        #expect(ProblemSolver.solve(problem, candidates: [
            try candidate("Garchomp", "Dragon Claw", in: store),
        ]).isEmpty)
    }

    @Test("A priority move KOs without needing Speed")
    func priority() throws {
        let store = try store()
        let problem = try problem("Dragapult", in: store)
        let counter = try #require(ProblemSolver.solve(problem, candidates: [
            try candidate("Kingambit", "Sucker Punch", in: store, ability: "supreme-overlord"),
        ]).first)
        #expect(counter.group == .priority && counter.speedPoints == nil)
        #expect(counter.attacker.heldItem == .blackGlasses)
        expectMinimal(counter, problem)
    }

    /// Focus Punch has -3 priority: however fast the user, it goes last.
    @Test("A negative-priority move is slower, and marked")
    func movesLast() throws {
        let store = try store()
        let problem = try problem("Kingambit", in: store)
        let counter = try #require(ProblemSolver.solve(problem, candidates: [
            try candidate("Garchomp", "Focus Punch", in: store),
        ]).first)
        #expect(counter.group == .slower && counter.speedPoints == nil)
        #expect(counter.marks.isSuperset(of: [.movesLast, .failsIfHit]))
        expectMinimal(counter, problem)
    }

    /// Full-Speed Gengar (neutral) is faster than Adamant Garchomp at full
    /// Speed, but not Jolly Garchomp.
    @Test("A Speed nature is used when it's what moves first")
    func speedNature() throws {
        let store = try store()
        let problem = try problem("Gengar", in: store) { $0.evSpeed = 32 }
        let counter = try #require(ProblemSolver.solve(problem, candidates: [
            try candidate("Garchomp", "Earthquake", in: store),
        ]).first)
        #expect(counter.group == .outspeeds)
        #expect(counter.attacker.nature.id == "jolly")
        expectMinimal(counter, problem)
    }

    /// Jolly, full-Speed Dragapult outspeeds any Garchomp without an item,
    /// but not a Jolly one holding Choice Scarf, whose Dragon Claw still KOs
    /// without Dragon Fang.
    @Test("Choice Scarf is tried when nothing else moves first")
    func choiceScarf() throws {
        let store = try store()
        let problem = try problem("Dragapult", in: store) {
            $0.evSpeed = 32
            $0.nature = allNatures.first { $0.id == "jolly" }!
        }
        let counters = ProblemSolver.solve(problem, candidates: [
            try candidate("Garchomp", "Dragon Claw", in: store),
        ])
        let slower = try #require(counters.first { $0.group == .slower })
        #expect(slower.attacker.heldItem == .dragonFang)
        let scarfed = try #require(counters.first { $0.group == .outspeeds })
        #expect(scarfed.attacker.heldItem == .choiceScarf)
        #expect(counters.first?.id == scarfed.id)
        expectMinimal(scarfed, problem)
    }

    // MARK: Intimidate

    @Test("Intimidate's effect on each kind of ability")
    func intimidateTable() {
        #expect(ProblemSolver.intimidated(ability: "rough-skin") == (-1, 0, 0))
        #expect(ProblemSolver.intimidated(ability: "clear-body") == (0, 0, 0))
        #expect(ProblemSolver.intimidated(ability: "defiant") == (1, 0, 0))
        #expect(ProblemSolver.intimidated(ability: "competitive") == (-1, 2, 0))
        #expect(ProblemSolver.intimidated(ability: "simple") == (-2, 0, 0))
        #expect(ProblemSolver.intimidated(ability: "rattled") == (-1, 0, 1))
    }

    /// Uninvested Incineroar with Intimidate: Garchomp's Earthquake KOs it
    /// at full Attack, but not at -1, and turning the switch off gives the
    /// KO back. Clear Body ignores Intimidate; Defiant gains from it.
    @Test("The problem set's Intimidate lowers or raises the counters' Attack")
    func intimidate() throws {
        let store = try store()
        let on = try problem("Incineroar", in: store, ability: "intimidate")
        let off = try problem("Incineroar", in: store, ability: "intimidate", intimidate: false)
        let chomp = try candidate("Garchomp", "Earthquake", in: store, ability: "rough-skin")
        #expect(ProblemSolver.solve(on, candidates: [chomp]).isEmpty)
        let plain = try #require(ProblemSolver.solve(off, candidates: [chomp]).first)
        #expect(plain.attacker.atkStage == 0)
        expectMinimal(plain, off)

        #expect(ProblemSolver.prepared(chomp, on).atkStage == -1)
        #expect(ProblemSolver.prepared(try candidate("Dragapult", "Dragon Claw", in: store, ability: "clear-body"), on)
                    .atkStage == 0)
        #expect(ProblemSolver.prepared(try candidate("Kingambit", "Sucker Punch", in: store, ability: "defiant"), on)
                    .atkStage == 1)
    }

    // MARK: Listing

    @Test("Abilities with the same result are listed together")
    func mergesAbilities() throws {
        let store = try store()
        let problem = try problem("Heatran", in: store)
        let counters = ProblemSolver.solve(problem, candidates: [
            try candidate("Garchomp", "Earthquake", in: store, ability: "sand-veil"),
            try candidate("Garchomp", "Earthquake", in: store, ability: "rough-skin"),
        ])
        #expect(counters.count == 1)
        #expect(Set(try #require(counters.first).abilities) == ["sand-veil", "rough-skin"])
    }

    @Test("Moves with drawbacks are marked")
    func marks() {
        #expect(ProblemSolver.marks(for: "Hyper Beam") == [.mustRecharge])
        #expect(ProblemSolver.marks(for: "Explosion") == [.faintsUser])
        #expect(ProblemSolver.marks(for: "Solar Beam") == [.chargesFirst])
        #expect(ProblemSolver.marks(for: "Fake Out") == [.firstTurnOnly])
        #expect(ProblemSolver.marks(for: "Focus Punch") == [.failsIfHit])
        #expect(ProblemSolver.marks(for: "Earthquake").isEmpty)
    }

    // MARK: The whole regulation

    /// Against the simulator's downloaded Pokédex, when it's there: every
    /// Regulation M-C Pokémon, form and Mega against full HP and Defense
    /// Intimidate Incineroar, within a budget, and every answer checks out.
    @Test("The whole regulation, timed")
    func wholeRegulation() throws {
        let context = AppModelContainer.shared.mainContext
        guard let incineroar = try context.fetch(FetchDescriptor<PKMNStats>(
            predicate: #Predicate { $0.name == "Incineroar" })).first else {
            print("[ProblemSolverTests] No downloaded Pokédex; skipping the timing test.")
            return
        }
        let all = try context.fetch(FetchDescriptor<PKMNStats>())
        let dexNames = Dictionary(try context.fetch(FetchDescriptor<PKMN>()).map { ($0.nationalPokedexNumber, $0.name) },
                                  uniquingKeysWith: { first, _ in first })
        let unmatched = ProblemSolver.rosterRows(for: .mC, allPokemon: all, dexNames: dexNames)
            .filter { $0.row == nil }.map(\.name)
        #expect(unmatched.isEmpty, "Regulation species without a Pokédex match: \(unmatched)")
        let target = CalcSide()
        target.loadUninvested(incineroar, championsMode: true, allPokemon: all)
        target.selectedAbility = "intimidate"
        target.evHP = 32
        target.evDef = 32
        let problem = ProblemSolver.Problem(defender: try #require(target.snapshot()))

        let started = Date()
        let candidates = ProblemSolver.candidates(for: .mC, in: context)
        let built = Date()
        let counters = ProblemSolver.solve(problem, candidates: candidates)
        let finished = Date()
        let species = Set(candidates.map(\.attacker.species.name)).count
        print(String(format: "[ProblemSolverTests] %d candidates from %d species in %.2fs; %d counters in %.2fs",
                     candidates.count, species, built.timeIntervalSince(started),
                     counters.count, finished.timeIntervalSince(built)))
        for group in ProblemSolver.Group.allCases {
            let top = counters.filter { $0.group == group }.prefix(3)
                .map { "\($0.name) \($0.move.name) \($0.attackPoints)+\($0.speedPoints ?? 0)" }
            print("[ProblemSolverTests] \(group): \(counters.filter { $0.group == group }.count), e.g. \(top)")
        }

        #expect(!counters.isEmpty)
        #expect(finished.timeIntervalSince(started) < 30)
        for counter in counters { expectMinimal(counter, problem) }
    }
}
