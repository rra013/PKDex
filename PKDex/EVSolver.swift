//
//  EVSolver.swift
//  PKDex
//
//  Finds the minimum EV investment that meets a goal: survive a hit, KO a
//  target, or outspeed a speed stat.
//
//  Every solve is an exhaustive scan, not a search. Only multiples of 4 move a
//  mainline stat (64 values) and Champions points are 0–32 (33 values), so the
//  worst case — a combined HP + defence solve — is a 64 x 64 grid, about 4k
//  evaluations. Scanning means no monotonicity assumption: abilities like
//  Multiscale, berries and HP-threshold effects can make damage non-monotone
//  in HP, and a binary search would quietly return a wrong answer.
//
//  All evaluation goes through `CalcEngine.evaluate`, the same door the calc
//  screen uses, so a solve and the on-screen result can't disagree about the
//  engine or the numbers.
//
//  Which stat to vary is *probed*, not hardcoded. The two engines disagree on
//  the edge cases (the Champions port models Psyshock hitting Def, Body Press
//  using the user's Def, Foul Play using the target's Atk, and Wonder Room;
//  the legacy engine models none of them), so the solver asks the engine:
//  each candidate stat is set to 0 and to the cap, and the one that moves the
//  damage most is the one that matters. That way it follows whichever engine
//  answers.
//
//  `nonisolated` for the same reason as `CalcEngine`: the module defaults to
//  MainActor isolation, and the whole point is to run off the main thread.
//

import Foundation

nonisolated enum EVSolver {

    // MARK: - Types

    /// A stat the solver can invest in. `Nature.StatKey` has no HP case (no
    /// nature affects HP), so the solver needs its own.
    enum Stat: String, CaseIterable, Hashable, Sendable {
        case hp, atk, def, spAtk, spDef, speed

        var natureKey: Nature.StatKey? {
            switch self {
            case .hp:    return nil
            case .atk:   return .atk
            case .def:   return .def
            case .spAtk: return .spAtk
            case .spDef: return .spDef
            case .speed: return .speed
            }
        }
    }

    /// How sure a damage goal has to be.
    ///
    /// `.chance` is only meaningful when the engine supplies per-roll damage
    /// (the Champions path). When `CalcOutcome.rolls` is nil it falls back to
    /// `.guaranteed`, which is the conservative reading: the solver may then
    /// ask for more EVs than strictly needed, but it never claims a KO or a
    /// survival that doesn't hold. `Solution.usedRolls` says which one
    /// applied.
    enum Certainty: Equatable, Sendable {
        /// Every damage roll must satisfy the goal.
        case guaranteed
        /// At least this fraction of the 16 rolls must satisfy it (0...1).
        case chance(atLeast: Double)
    }

    struct Solution: Equatable, Sendable {
        /// The EV value chosen for each solved stat, in the side's own units
        /// (0–252 mainline, 0–32 Champions). Stats not solved for are absent
        /// and keep the value they had in the input snapshot.
        var evs: [Stat: Int]
        /// The input snapshot with `evs` applied.
        var snapshot: CalcSnapshot
        /// The evaluation at the solution. nil for speed solves.
        var outcome: CalcOutcome?
        /// True when roll-level data decided a `.chance` goal. False when the
        /// goal was `.guaranteed`, or `.chance` fell back to it for lack of
        /// rolls.
        var usedRolls: Bool

        /// Total EVs spent on the solved stats.
        var cost: Int { evs.values.reduce(0, +) }
    }

    enum Failure: Error, Equatable, Sendable {
        /// The move can't be solved against: a status move, or a side with
        /// nothing to vary.
        case notApplicable(String)
        /// No EV in the attacker's stats changes this move's damage — fixed
        /// damage, or a move like Foul Play that reads the target's stats.
        case noRelevantStat
        /// No spread within the budget meets the goal. `best` is the outcome
        /// at maximum investment, so the UI can say how close it gets.
        case unreachable(best: CalcOutcome?)
    }

    // MARK: - Survive

    /// The cheapest HP + defensive-stat spread that lets `defender` survive
    /// `move` from `attacker`, measured from full HP.
    ///
    /// Only the defensive stat the engine actually reads is varied, alongside
    /// HP. The budget is what's left after the defender's other stats, so
    /// existing investment in Atk / SpA / Speed is respected. Ties on total
    /// cost go to the spread that takes the least worst-case damage.
    static func minimumToSurvive(
        move: MoveSnapshot,
        attacker: CalcSnapshot,
        defender: CalcSnapshot,
        field: FieldSnapshot,
        certainty: Certainty = .guaranteed
    ) -> Result<Solution, Failure> {
        guard !move.isStatus else { return .failure(.notApplicable("status move")) }

        let evaluateWith = { (d: CalcSnapshot) in
            CalcEngine.evaluate(move: move, attacker: attacker, defender: d, field: field)
        }

        // HP always matters; a defensive stat only when the engine reads one.
        let defensive = mostRelevant(of: [.def, .spDef], on: defender) {
            evaluateWith($0).damageMax
        }
        let stats: [Stat] = [.hp] + [defensive].compactMap { $0 }
        let budget = remainingBudget(defender, excluding: stats)
        let domain = defender.evDomain

        var best: (solution: Solution, damage: Double)?

        for hp in domain where hp <= budget {
            for d in (defensive == nil ? [0] : domain) where hp + d <= budget {
                // Going up this column, the first spread that works is the
                // cheapest one with this HP value — later ones only cost more.
                if let best, hp + d > best.solution.cost { break }

                var evs: [Stat: Int] = [.hp: hp]
                if let defensive { evs[defensive] = d }
                let candidate = applying(evs, to: defender)
                let outcome = evaluateWith(candidate)
                guard let used = meets(certainty, outcome, wantKO: false) else { continue }

                let cost = hp + d
                if best == nil
                    || cost < best!.solution.cost
                    || (cost == best!.solution.cost && outcome.maxPercent < best!.damage) {
                    best = (Solution(evs: evs, snapshot: candidate, outcome: outcome,
                                     usedRolls: used),
                            outcome.maxPercent)
                }
                break
            }
        }

        if let best { return .success(best.solution) }
        let maxed = maxInvestment(stats, on: defender, budget: budget)
        return .failure(.unreachable(best: evaluateWith(maxed)))
    }

    // MARK: - KO

    /// The smallest investment in `attacker`'s offensive stat that lets `move`
    /// KO `defender` from full HP.
    ///
    /// The offensive stat is whichever of Atk, SpA or Def the engine reads
    /// (Def covers Body Press on the Champions path). If none of them changes
    /// the damage, the move isn't EV-dependent and the solve reports
    /// `.noRelevantStat`.
    static func minimumToKO(
        move: MoveSnapshot,
        attacker: CalcSnapshot,
        defender: CalcSnapshot,
        field: FieldSnapshot,
        certainty: Certainty = .guaranteed
    ) -> Result<Solution, Failure> {
        guard !move.isStatus else { return .failure(.notApplicable("status move")) }

        let evaluateWith = { (a: CalcSnapshot) in
            CalcEngine.evaluate(move: move, attacker: a, defender: defender, field: field)
        }

        guard let offensive = mostRelevant(of: [.atk, .spAtk, .def], on: attacker,
                                           measure: { evaluateWith($0).damageMax })
        else { return .failure(.noRelevantStat) }

        let budget = remainingBudget(attacker, excluding: [offensive])

        for value in attacker.evDomain where value <= budget {
            let evs = [offensive: value]
            let candidate = applying(evs, to: attacker)
            let outcome = evaluateWith(candidate)
            if let used = meets(certainty, outcome, wantKO: true) {
                return .success(Solution(evs: evs, snapshot: candidate, outcome: outcome,
                                         usedRolls: used))
            }
        }

        let maxed = maxInvestment([offensive], on: attacker, budget: budget)
        return .failure(.unreachable(best: evaluateWith(maxed)))
    }

    // MARK: - Speed

    /// The smallest Speed investment that brings `side` above `targetSpeed`,
    /// or level with it when `allowTie` is set.
    ///
    /// `speedOf` turns a candidate into the Speed that's compared. The default
    /// is the stage-adjusted stat. The calc passes `CalcEngine.finalSpeed`,
    /// which also applies items, Tailwind, weather abilities and paralysis.
    /// Measure `targetSpeed` the same way, or the comparison is lopsided.
    static func minimumToOutspeed(
        _ side: CalcSnapshot,
        targetSpeed: Int,
        allowTie: Bool = false,
        speedOf: (CalcSnapshot) -> Int = { $0.speed }
    ) -> Result<Solution, Failure> {
        let budget = remainingBudget(side, excluding: [.speed])
        for value in side.evDomain where value <= budget {
            let candidate = side.settingEV(.speed, to: value)
            let speed = speedOf(candidate)
            if speed > targetSpeed || (allowTie && speed == targetSpeed) {
                return .success(Solution(evs: [.speed: value], snapshot: candidate,
                                         outcome: nil, usedRolls: false))
            }
        }
        return .failure(.unreachable(best: nil))
    }

    // MARK: - Helpers

    /// Decides a goal from one outcome. Returns nil when the goal isn't met,
    /// otherwise whether roll-level data decided it.
    static func meets(_ certainty: Certainty, _ outcome: CalcOutcome,
                      wantKO: Bool) -> Bool? {
        if case .chance(let threshold) = certainty, let koChance = outcome.ohkoChance {
            let chance = wantKO ? koChance : 1 - koChance
            return chance >= threshold ? true : nil
        }
        let met = wantKO ? outcome.isGuaranteedOHKO : outcome.isGuaranteedSurvival
        return met ? false : nil
    }

    /// Of `candidates`, the stat whose swing from 0 to the per-stat cap moves
    /// `measure` the most. nil when none of them moves it at all.
    ///
    /// The probe runs at the cap regardless of budget. Budget only limits how
    /// far the solve can go, not which stat the engine reads.
    static func mostRelevant(of candidates: [Stat], on side: CalcSnapshot,
                             measure: (CalcSnapshot) -> Double) -> Stat? {
        var best: (stat: Stat, swing: Double)?
        for stat in candidates {
            let low = measure(applying([stat: 0], to: side))
            let high = measure(applying([stat: side.evPerStatMax], to: side))
            let swing = abs(high - low)
            if swing > 0, swing > (best?.swing ?? 0) { best = (stat, swing) }
        }
        return best?.stat
    }

    /// EVs left for `stats` once every other stat keeps what it already has,
    /// capped at the total. Investment in the stats being solved is freed up,
    /// since the solver replaces it.
    static func remainingBudget(_ side: CalcSnapshot, excluding stats: [Stat]) -> Int {
        let solved = stats.reduce(0) { $0 + ev(of: $1, in: side) }
        return max(0, side.evTotalMax - (side.totalEVs - solved))
    }

    static func ev(of stat: Stat, in side: CalcSnapshot) -> Int {
        switch stat {
        case .hp:    return side.evHP
        case .atk:   return side.evAtk
        case .def:   return side.evDef
        case .spAtk: return side.evSpAtk
        case .spDef: return side.evSpDef
        case .speed: return side.evSpeed
        }
    }

    static func applying(_ evs: [Stat: Int], to side: CalcSnapshot) -> CalcSnapshot {
        evs.reduce(side) { snap, entry in
            if let key = entry.key.natureKey { return snap.settingEV(key, to: entry.value) }
            return snap.settingHPEV(to: entry.value)
        }
    }

    /// Spends `budget` on `stats` in order, each up to the per-stat cap —
    /// the "everything in" spread reported when a goal is unreachable.
    /// Rounded down to a value in the side's EV domain.
    static func maxInvestment(_ stats: [Stat], on side: CalcSnapshot,
                              budget: Int) -> CalcSnapshot {
        var left = budget
        var evs: [Stat: Int] = [:]
        for stat in stats {
            let value = side.evDomain.last { $0 <= min(left, side.evPerStatMax) } ?? 0
            evs[stat] = value
            left -= value
        }
        return applying(evs, to: side)
    }
}
