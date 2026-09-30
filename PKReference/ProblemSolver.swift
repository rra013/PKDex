//
//  ProblemSolver.swift
//  PKReference
//
//  Finds the Pokémon, move and investment combinations that knock out a
//  chosen set in one hit, guaranteed, under Champions doubles rules, and
//  says which of them move first. ProblemSolver-PLAN.md has the plan and
//  the owner's decisions.
//
//  Every answer comes from the calc itself (`CalcEngine.evaluate`, through
//  `EVSolver` for the scaling down), never from an estimate, so the solver
//  and the calc screen can't disagree. The search is exhaustive: at about
//  40 µs a calc the whole roster takes a second or two (measured 2026-09-30).
//
//  `nonisolated`, like `CalcEngine` and `EVSolver`: the candidates are
//  built on the main actor as `Sendable` snapshots, and the search runs
//  anywhere.
//

import Foundation
import SwiftData

nonisolated enum ProblemSolver {

    // MARK: - Inputs

    /// The set to beat, and the field it's beaten on.
    struct Problem: Sendable {
        var defender: CalcSnapshot
        /// Champions doubles: `multi` is on, so spread moves take 0.75×.
        var field: FieldSnapshot
        /// Whether the defender's Intimidate lowers the counters' Attack.
        var intimidate = true

        init(defender: CalcSnapshot, intimidate: Bool = true) {
            self.defender = defender
            var field = FieldSnapshot()
            field.multi = true
            self.field = field
            self.intimidate = intimidate
        }
    }

    /// One Pokémon, ability and move to try: its species, form or Mega at
    /// level 50 on Champions rules, with no investment and no item (a Mega
    /// holds its stone). The solver chooses the rest.
    struct Candidate: Sendable {
        var attacker: CalcSnapshot
        var move: MoveSnapshot
        /// Percent, or nil for a move that can't miss.
        var accuracy: Int?
        var priority: Int
        var marks: Set<Mark>
    }

    // MARK: - Results

    /// How a counter gets its hit in, best first.
    enum Group: Int, Comparable, CaseIterable, Sendable {
        /// Faster than the problem set, so it knocks it out first.
        case outspeeds
        /// A priority move, so Speed doesn't matter.
        case priority
        /// Slower: it needs Trick Room, Tailwind or a switch-in.
        case slower

        static func < (a: Group, b: Group) -> Bool { a.rawValue < b.rawValue }
    }

    /// Something to know about a counter.
    enum Mark: Hashable, Sendable {
        case mustRecharge
        case faintsUser
        case chargesFirst
        case firstTurnOnly
        case failsIfHit
        /// Negative priority: it moves after everything else, whatever the
        /// Speeds (Focus Punch).
        case movesLast
        /// It can only tie the problem set's Speed, not beat it.
        case speedTie
    }

    struct Counter: Identifiable, Equatable, Sendable {
        /// As solved: nature, stat points, item, and any stages from the
        /// problem set's Intimidate.
        var attacker: CalcSnapshot
        /// Every ability that gives this result.
        var abilities: [String]
        var move: MoveSnapshot
        var outcome: CalcOutcome
        /// The stat the damage depends on, or nil when none does (Foul Play).
        var attackStat: EVSolver.Stat?
        var attackPoints: Int
        /// Points in Speed to outspeed, or nil for a priority move or a
        /// counter that can't.
        var speedPoints: Int?
        /// Final Speed as solved.
        var speed: Int
        var group: Group
        var accuracy: Int?
        var marks: Set<Mark>

        var totalPoints: Int { attackPoints + (speedPoints ?? 0) }

        /// The Pokémon as named in the results: its Mega, or its species.
        var name: String { attacker.megaForm?.displayName ?? attacker.species.name }

        var id: String {
            "\(name)|\(move.id)|\(attacker.heldItem.rawValue)|\(attacker.nature.id)|\(group)"
        }
    }

    // MARK: - Solving

    /// Every counter among `candidates`, best first: by group, then fewest
    /// points, then accuracy, then fewest marks. Stops early, returning what
    /// it has, when `isCancelled` says so.
    static func solve(_ problem: Problem, candidates: [Candidate],
                      isCancelled: () -> Bool = { false }) -> [Counter] {
        let targetSpeed = speed(problem.defender, problem.field)
        var byKey: [String: Counter] = [:]
        var order: [String] = []
        // Abilities that give the same damage share one scaling down; see
        // `scaledKey`.
        var scaled: [String: [Counter]] = [:]

        for candidate in candidates {
            if isCancelled() { break }
            guard !candidate.move.isStatus, (candidate.move.power ?? 0) > 0 else { continue }

            let attacker = prepared(candidate, problem)
            let stat = offensiveStat(for: candidate.move)
            let strongest = attacker.settingNature(attackingNature(for: stat))
                .settingEV(stat.natureKey!, to: attacker.evPerStatMax)
            let best = CalcEngine.evaluate(move: candidate.move, attacker: strongest,
                                           defender: problem.defender, field: problem.field)
            guard best.isGuaranteedOHKO else { continue }

            let key = scaledKey(candidate, attacker, best)
            let counters = scaled[key] ?? scaleDown(candidate, attacker, stat, problem, targetSpeed)
            scaled[key] = counters

            let ability = candidate.attacker.megaForm?.ability ?? candidate.attacker.selectedAbility
            for var counter in counters {
                if let existing = byKey[counter.id] {
                    counter = existing
                    if let ability, !counter.abilities.contains(ability) { counter.abilities.append(ability) }
                } else {
                    counter.abilities = ability.map { [$0] } ?? []
                    order.append(counter.id)
                }
                byKey[counter.id] = counter
            }
        }

        return order.compactMap { byKey[$0] }.sorted { a, b in
            (a.group, a.totalPoints, -(a.accuracy ?? 101), a.marks.count, a.name, a.move.name)
                < (b.group, b.totalPoints, -(b.accuracy ?? 101), b.marks.count, b.name, b.move.name)
        }
    }

    /// The candidate as it enters the battle: the move's type booster (a
    /// Mega keeps its stone), and the problem set's Intimidate.
    static func prepared(_ candidate: Candidate, _ problem: Problem) -> CalcSnapshot {
        var attacker = candidate.attacker
        attacker.moves = [candidate.move]
        if attacker.megaForm == nil {
            attacker.heldItem = booster(for: candidate.move.type) ?? .none
        }
        if problem.intimidate, problem.defender.effectiveAbility == "intimidate" {
            // Intimidate lands on switch-in, before a Mega Evolves, so the
            // ability that answers it is the one chosen, not the Mega's.
            let stages = intimidated(ability: attacker.selectedAbility)
            attacker.atkStage += stages.atk
            attacker.spAtkStage += stages.spAtk
            attacker.speedStage += stages.speed
        }
        return attacker
    }

    /// Two abilities with the same damage at full investment scale down the
    /// same way, so they share the work.
    private static func scaledKey(_ candidate: Candidate, _ attacker: CalcSnapshot,
                                  _ best: CalcOutcome) -> String {
        [candidate.attacker.species.name, candidate.attacker.megaForm?.displayName ?? "",
         "\(candidate.move.id)", "\(best.damageMin)", "\(best.damageMax)",
         "\(attacker.atkStage)", "\(attacker.spAtkStage)", "\(attacker.speedStage)"].joined(separator: "|")
    }

    /// The fewest points that guarantee the KO, and the Speed to go with
    /// them, with each nature; then, for a counter left slower, the same
    /// holding Choice Scarf instead of its booster.
    private static func scaleDown(_ candidate: Candidate, _ attacker: CalcSnapshot, _ stat: EVSolver.Stat,
                                  _ problem: Problem, _ targetSpeed: Int) -> [Counter] {
        guard let best = bestOption(candidate, attacker, stat, problem, targetSpeed) else { return [] }
        var counters = [best]
        if best.group == .slower, attacker.megaForm == nil, candidate.priority == 0 {
            var scarfed = attacker
            scarfed.heldItem = .choiceScarf
            if let withScarf = bestOption(candidate, scarfed, stat, problem, targetSpeed),
               withScarf.group == .outspeeds {
                counters.append(withScarf)
            }
        }
        return counters
    }

    /// Of an attacking nature and a Speed nature, the one that gets the
    /// better group, then the fewer points. nil when neither KOs.
    private static func bestOption(_ candidate: Candidate, _ attacker: CalcSnapshot, _ stat: EVSolver.Stat,
                                   _ problem: Problem, _ targetSpeed: Int) -> Counter? {
        // Speed decides nothing for a priority move, first or last.
        let natures = candidate.priority != 0
            ? [attackingNature(for: stat)]
            : [attackingNature(for: stat), speedNature(for: stat)]
        return natures.compactMap { nature in
            option(candidate, attacker.settingNature(nature), problem, targetSpeed)
        }.min { ($0.group, $0.totalPoints) < ($1.group, $1.totalPoints) }
    }

    private static func option(_ candidate: Candidate, _ attacker: CalcSnapshot,
                               _ problem: Problem, _ targetSpeed: Int) -> Counter? {
        let solved: CalcSnapshot
        let outcome: CalcOutcome
        let attackStat: EVSolver.Stat?
        let attackPoints: Int
        switch EVSolver.minimumToKO(move: candidate.move, attacker: attacker,
                                    defender: problem.defender, field: problem.field) {
        case .success(let solution):
            guard let result = solution.outcome else { return nil }
            solved = solution.snapshot
            outcome = result
            attackStat = solution.evs.keys.first
            attackPoints = solution.cost
        case .failure(.noRelevantStat):
            // Damage that doesn't depend on the attacker's stats (Foul Play).
            let result = CalcEngine.evaluate(move: candidate.move, attacker: attacker,
                                             defender: problem.defender, field: problem.field)
            guard result.isGuaranteedOHKO else { return nil }
            (solved, outcome, attackStat, attackPoints) = (attacker, result, nil, 0)
        case .failure:
            return nil
        }

        var marks = candidate.marks
        let speedOf = { (side: CalcSnapshot) in speed(side, problem.field) }
        let group: Group
        var speedPoints: Int?
        var final = solved
        if candidate.priority > 0 {
            group = .priority
        } else if candidate.priority < 0 {
            group = .slower
            marks.insert(.movesLast)
        } else if case .success(let fast) = EVSolver.minimumToOutspeed(solved, targetSpeed: targetSpeed,
                                                                      speedOf: speedOf) {
            group = .outspeeds
            speedPoints = fast.cost
            final = fast.snapshot
        } else {
            group = .slower
            if case .success = EVSolver.minimumToOutspeed(solved, targetSpeed: targetSpeed, allowTie: true,
                                                         speedOf: speedOf) {
                marks.insert(.speedTie)
            }
        }
        return Counter(attacker: final, abilities: [], move: candidate.move, outcome: outcome,
                       attackStat: attackStat, attackPoints: attackPoints, speedPoints: speedPoints,
                       speed: speedOf(final), group: group, accuracy: candidate.accuracy, marks: marks)
    }

    // MARK: - Rules

    /// Final Speed as the calc works it out: items (Choice Scarf), Megas and
    /// stages, through the Champions port.
    static func speed(_ side: CalcSnapshot, _ field: FieldSnapshot) -> Int {
        CalcEngine.finalSpeed(side, field: field) ?? side.speed
    }

    /// The stat a move's damage comes from on the attacker's side: Defense
    /// for Body Press, else Attack or Special Attack.
    static func offensiveStat(for move: MoveSnapshot) -> EVSolver.Stat {
        if BattleSimSeed.normalize(move.name) == "bodypress" { return .def }
        return move.isPhysical ? .atk : .spAtk
    }

    /// A nature raising `stat` and lowering one the move doesn't use.
    static func attackingNature(for stat: EVSolver.Stat) -> Nature {
        nature(stat == .spAtk ? "modest" : stat == .def ? "bold" : "adamant")
    }

    /// A nature raising Speed and lowering one the move doesn't use.
    static func speedNature(for stat: EVSolver.Stat) -> Nature {
        nature(stat == .atk ? "jolly" : "timid")
    }

    private static func nature(_ id: String) -> Nature {
        allNatures.first { $0.id == id } ?? allNatures[0]
    }

    /// The 1.2× item for a type. Every type has one.
    static func booster(for type: String) -> HeldItem? {
        typeBoostingItemMap.first { $0.value == type }?.key
    }

    /// What the problem set's Intimidate does to a Pokémon with `ability`,
    /// in stages: blocked by Clear Body and the like, turned around by
    /// Defiant, Competitive, Contrary and Guard Dog, doubled by Simple.
    static func intimidated(ability: String?) -> (atk: Int, spAtk: Int, speed: Int) {
        switch ability {
        case "clear-body", "white-smoke", "full-metal-body", "hyper-cutter", "inner-focus",
             "oblivious", "own-tempo", "scrappy", "mirror-armor":
            return (0, 0, 0)
        case "guard-dog", "contrary", "defiant":
            // Defiant takes the drop, then +2.
            return (1, 0, 0)
        case "competitive":
            return (-1, 2, 0)
        case "simple":
            return (-2, 0, 0)
        case "rattled":
            return (-1, 0, 1)
        default:
            return (-1, 0, 0)
        }
    }
}

// MARK: - Snapshot helpers

nonisolated extension CalcSnapshot {
    func settingNature(_ nature: Nature) -> CalcSnapshot {
        var copy = self
        copy.nature = nature
        return copy
    }
}

// MARK: - Building the candidates

extension ProblemSolver {
    /// Every Pokémon, form and Mega `regulation` allows, with each of its
    /// abilities and legal damaging moves, as candidates. Names are matched
    /// between the regulation's files and the Pokédex by `IntentNames.key`,
    /// as Check Legality matches them.
    @MainActor
    static func candidates(for regulation: ChampionsRegulation, in context: ModelContext) -> [Candidate] {
        let allPokemon = (try? context.fetch(FetchDescriptor<PKMNStats>())) ?? []
        let moves = (try? context.fetch(FetchDescriptor<MoveData>())) ?? []
        let dexNames = Dictionary(((try? context.fetch(FetchDescriptor<PKMN>())) ?? [])
            .map { ($0.nationalPokedexNumber, $0.name) }, uniquingKeysWith: { first, _ in first })
        let store = ChampionsLearnsetStore.store(for: regulation)
        let rules = regulation.rules()
        let moveByKey = Dictionary(moves.map { (IntentNames.key($0.name), $0) }, uniquingKeysWith: { first, _ in first })
        func damaging(_ names: [String]) -> [MoveData] {
            names.compactMap { moveByKey[IntentNames.key($0)] }
                .filter { $0.damageClass != "status" && ($0.power ?? 0) > 0 }
        }

        var candidates: [Candidate] = []
        func add(_ side: CalcSide, abilities: [String?], moves: [MoveData]) {
            for ability in abilities {
                side.selectedAbility = ability
                guard let attacker = side.snapshot() else { continue }
                for move in moves {
                    candidates.append(Candidate(attacker: attacker, move: move.snapshot(), accuracy: move.accuracy,
                                                priority: move.priority, marks: marks(for: move.name)))
                }
            }
        }

        for (name, row) in rosterRows(for: regulation, allPokemon: allPokemon, dexNames: dexNames) {
            guard let data = store.data(for: name), let row else { continue }
            let moves = damaging(data.moves)

            let base = CalcSide()
            base.loadUninvested(row, championsMode: true, allPokemon: allPokemon)
            add(base, abilities: abilityIDs(data.abilities, on: row), moves: moves)

            for form in data.alternateForms {
                let keys = PokemonLegality.formKeys(form.name)
                guard let formRow = allPokemon.first(where: { other in
                    other.speciesID == row.speciesID && other.isForm
                        && keys.contains { IntentNames.key(other.formName ?? "").hasPrefix($0) }
                }) else { continue }
                let side = CalcSide()
                side.loadUninvested(formRow, championsMode: true, allPokemon: allPokemon)
                add(side, abilities: abilityIDs(form.abilities, on: formRow), moves: damaging(form.moves ?? data.moves))
            }

            guard rules.megaEvolutionsAllowed else { continue }
            for mega in data.megas {
                guard let form = MegaForms.all.first(where: { IntentNames.key($0.displayName) == IntentNames.key(mega.name) }),
                      let stone = form.stone,
                      rules.allowsMega(form) else { continue }
                let side = CalcSide()
                side.loadUninvested(row, championsMode: true, allPokemon: allPokemon)
                side.heldItem = stone
                side.megaActive = true
                // A Mega has one ability; the one chosen before it Mega
                // Evolves is its species' first.
                add(side, abilities: [row.ability1], moves: moves)
            }
        }
        return candidates
    }

    /// Each species the regulation lists, sorted, with its Pokédex row: by
    /// any name the Pokédex might give it ("Kommo-O" for "Kommo-o",
    /// "Lycanroc-Midday" for "Lycanroc"). nil where there's none.
    @MainActor
    static func rosterRows(for regulation: ChampionsRegulation, allPokemon: [PKMNStats],
                           dexNames: [Int: String]) -> [(name: String, row: PKMNStats?)] {
        var species: [String: PKMNStats] = [:]
        for row in allPokemon where !row.isForm {
            for name in [row.name, ChampionsFormat.canonicalChampionsSpecies(row.name), dexNames[row.speciesID]]
                .compactMap({ $0 }) where species[IntentNames.key(name)] == nil {
                species[IntentNames.key(name)] = row
            }
        }
        return regulation.speciesWhitelist().sorted().map { ($0, species[IntentNames.key($0)]) }
    }

    /// The regulation's abilities for a Pokémon ("Rough Skin") as the calc
    /// names them ("rough-skin").
    @MainActor
    static func abilityIDs(_ names: [String], on row: PKMNStats) -> [String?] {
        let ids = names.map { name in
            row.allAbilities.first { IntentNames.key(formatAbilityName($0)) == IntentNames.key(name) }
                ?? name.lowercased().replacingOccurrences(of: "'", with: "").replacingOccurrences(of: " ", with: "-")
        }
        return ids.isEmpty ? [row.ability1] : ids
    }

    @MainActor
    static func marks(for moveName: String) -> Set<Mark> {
        let key = BattleSimSeed.normalize(moveName)
        var marks: Set<Mark> = []
        if BattleMoveEffects.rechargeMoves.contains(key) { marks.insert(.mustRecharge) }
        if BattleMoveEffects.selfKOMoves.contains(key) { marks.insert(.faintsUser) }
        if BattleMoveEffects.chargeMoves[key] != nil { marks.insert(.chargesFirst) }
        if BattleMoveEffects.firstTurnOnlyMoves.contains(key) { marks.insert(.firstTurnOnly) }
        if BattleMoveEffects.failsIfHitMoves.contains(key) { marks.insert(.failsIfHit) }
        return marks
    }
}
