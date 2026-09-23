//
//  EVSolverSheet.swift
//  PKDex
//
//  Phase 2.3: the EV solver's UI. Opened from a move row on the damage calc,
//  it answers three questions about that matchup and can write the answer
//  back to the calc:
//
//    * the cheapest HP + defensive spread for the defender to survive it,
//    * the cheapest offensive investment for the attacker to OHKO with it,
//    * the Speed each side needs to outspeed the other.
//
//  The solves run off the main actor on `Sendable` snapshots taken when the
//  sheet opens (see `CalcSnapshot.swift`), so a 64 x 64 defensive sweep
//  never blocks the UI. Everything the detached task touches is
//  `nonisolated`, per the convention in CalcCore-HANDOFF.md.
//

import SwiftUI

/// Which move to solve around, and in which direction. Identifiable so the
/// calc can drive the sheet with `.sheet(item:)`.
struct EVSolveRequest: Identifiable {
    let id = UUID()
    let move: MoveData
    /// True when side 1 is the attacker (the "Pokemon 1 → Pokemon 2" list).
    let attackerIsSide1: Bool
}

struct EVSolverSheet: View {
    let vm: DamageCalcVM
    let request: EVSolveRequest

    @Environment(\.dismiss) private var dismiss
    @State private var certainty: CertaintyChoice = .guaranteed
    @State private var results: SolveResults?

    private var attacker: CalcSide { request.attackerIsSide1 ? vm.side1 : vm.side2 }
    private var defender: CalcSide { request.attackerIsSide1 ? vm.side2 : vm.side1 }
    /// Side names, tagged P1 / P2 in a mirror match so "Garchomp over
    /// Garchomp" says which one.
    private var attackerName: String { displayName(attacker, isSide1: request.attackerIsSide1) }
    private var defenderName: String { displayName(defender, isSide1: !request.attackerIsSide1) }

    private func displayName(_ side: CalcSide, isSide1: Bool) -> String {
        let name = side.pokemon?.name ?? (isSide1 ? "Pokemon 1" : "Pokemon 2")
        let mirror = vm.side1.pokemon?.name == vm.side2.pokemon?.name
        return mirror ? "\(name) (\(isSide1 ? "P1" : "P2"))" : name
    }

    /// Roll-level goals only mean something on the Champions path, the only
    /// engine that reports individual rolls.
    private var rollsPossible: Bool { attacker.championsMode && defender.championsMode }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 6) {
                        Text(request.move.name).font(.headline)
                        TypeBadge(type: request.move.type)
                        DamageClassBadge(damageClass: request.move.damageClass)
                    }
                    Text("\(attackerName) → \(defenderName)")
                        .font(.subheadline).foregroundStyle(.secondary)
                    if rollsPossible {
                        Picker("Goal", selection: $certainty) {
                            ForEach(CertaintyChoice.allCases) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }
                } footer: {
                    Text("Each answer is the fewest EVs that works, using only EVs not already spent in other stats. Other stats keep their current values.")
                }

                if let results {
                    damageSection(
                        title: "\(defenderName) survives",
                        icon: "shield.lefthalf.filled",
                        result: results.survive, side: defender, goalIsKO: false)
                    damageSection(
                        title: "\(attackerName) OHKOs",
                        icon: "bolt.fill",
                        result: results.ko, side: attacker, goalIsKO: true)
                    Section {
                        speedRow(name: attackerName, over: defenderName,
                                 targetSpeed: results.defenderSpeedStat,
                                 result: results.attackerOutspeeds, side: attacker)
                        speedRow(name: defenderName, over: attackerName,
                                 targetSpeed: results.attackerSpeedStat,
                                 result: results.defenderOutspeeds, side: defender)
                    } header: {
                        Label("Outspeed", systemImage: "hare.fill")
                    } footer: {
                        Text("Compares current Speed with stat stages. Items, Tailwind and paralysis aren't applied. Ties don't count.")
                    }
                } else {
                    Section {
                        HStack {
                            Spacer()
                            ProgressView("Solving…")
                            Spacer()
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
            .navigationTitle("Solve EVs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task(id: certainty) { await solve() }
        }
    }

    // MARK: - Solving

    private func solve() async {
        results = nil
        guard let atk = attacker.snapshot(), let def = defender.snapshot() else { return }
        let move = request.move.snapshot()
        let field = vm.fieldSnapshot()
        let goal = certainty.solverValue
        let solved = await Task.detached(priority: .userInitiated) {
            SolveResults.compute(move: move, attacker: atk, defender: def,
                                 field: field, certainty: goal)
        }.value
        guard !Task.isCancelled else { return }
        results = solved
    }

    // MARK: - Damage goals

    @ViewBuilder
    private func damageSection(title: String, icon: String,
                               result: Result<EVSolver.Solution, EVSolver.Failure>,
                               side: CalcSide, goalIsKO: Bool) -> some View {
        Section {
            switch result {
            case .success(let solution):
                spreadRows(solution, side: side)
                if let outcome = solution.outcome {
                    outcomeRow(outcome, usedRolls: solution.usedRolls, goalIsKO: goalIsKO)
                }
                if certainty != .guaranteed && !solution.usedRolls {
                    Text("This matchup has no roll data, so this is the every-roll answer.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                applyButton(solution, side: side)
            case .failure(let failure):
                failureRow(failure, goalIsKO: goalIsKO)
            }
        } header: {
            Label(title, systemImage: icon)
        }
    }

    /// One row per solved stat: current value → solution, so it's clear when
    /// applying would *lower* an existing investment. With nothing needed,
    /// only the stats that would drop to 0 are listed.
    @ViewBuilder
    private func spreadRows(_ solution: EVSolver.Solution, side: CalcSide) -> some View {
        if solution.cost == 0 {
            Text("No investment needed")
                .foregroundStyle(.green)
        }
        let shown = EVSolver.Stat.allCases.filter { stat in
            guard let new = solution.evs[stat] else { return false }
            return solution.cost > 0 || side.ev(stat) != new
        }
        ForEach(shown, id: \.self) { stat in
            let now = side.ev(stat)
            let new = solution.evs[stat]!
            LabeledContent(stat.shortLabel) {
                HStack(spacing: 4) {
                    if now != new {
                        Text("\(now)").foregroundStyle(.secondary)
                        Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.secondary)
                    }
                    Text(new == 1 ? "1 EV" : "\(new) EVs").bold()
                }
                .monospacedDigit()
            }
        }
    }

    private func outcomeRow(_ outcome: CalcOutcome, usedRolls: Bool, goalIsKO: Bool) -> some View {
        var detail = String(format: "%.1f%% – %.1f%%", outcome.minPercent, outcome.maxPercent)
        if usedRolls, let ko = outcome.ohkoChance {
            let rolls = outcome.rolls?.count ?? 16
            let hits = Int((ko * Double(rolls)).rounded())
            detail += goalIsKO
                ? " · KOs on \(hits)/\(rolls) rolls"
                : " · survives \(rolls - hits)/\(rolls) rolls"
        }
        return LabeledContent("Result") {
            Text(detail).monospacedDigit()
        }
    }

    private func applyButton(_ solution: EVSolver.Solution, side: CalcSide) -> some View {
        let changes = solution.evs.contains { side.ev($0.key) != $0.value }
        return Button {
            for (stat, value) in solution.evs { side.setEV(stat, to: value) }
            dismiss()
        } label: {
            Label(changes ? "Apply to calc" : "Already applied",
                  systemImage: changes ? "checkmark.circle" : "checkmark.circle.fill")
        }
        .disabled(!changes)
    }

    @ViewBuilder
    private func failureRow(_ failure: EVSolver.Failure, goalIsKO: Bool) -> some View {
        switch failure {
        case .unreachable(let best):
            VStack(alignment: .leading, spacing: 4) {
                Text(goalIsKO ? "Can't OHKO within the EV budget" : "Can't survive within the EV budget")
                    .foregroundStyle(.orange)
                if let best {
                    Text(maxedSummary(best, goalIsKO: goalIsKO))
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
            }
        case .noRelevantStat:
            Text("This move's damage doesn't depend on the attacker's EVs.")
                .foregroundStyle(.secondary)
        case .notApplicable(let reason):
            Text("Not solvable: \(reason).")
                .foregroundStyle(.secondary)
        }
    }

    /// "At maximum investment: 86.3% – 102.7% · KOs on 2/16 rolls". The roll
    /// count is what makes a near miss legible, when the engine has one.
    private func maxedSummary(_ best: CalcOutcome, goalIsKO: Bool) -> String {
        var text = String(format: "At maximum investment: %.1f%% – %.1f%%",
                          best.minPercent, best.maxPercent)
        if let ko = best.ohkoChance, let rolls = best.rolls?.count {
            let hits = Int((ko * Double(rolls)).rounded())
            text += goalIsKO ? " · KOs on \(hits)/\(rolls) rolls"
                             : " · survives \(rolls - hits)/\(rolls) rolls"
        }
        return text
    }

    // MARK: - Speed

    @ViewBuilder
    private func speedRow(name: String, over other: String, targetSpeed: Int,
                          result: Result<EVSolver.Solution, EVSolver.Failure>,
                          side: CalcSide) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(name) over \(other) (\(targetSpeed))")
                .font(.subheadline)
            switch result {
            case .success(let solution):
                let now = side.evSpeed
                let new = solution.evs[.speed] ?? 0
                HStack(spacing: 4) {
                    if now != new {
                        Text("\(now)").foregroundStyle(.secondary)
                        Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.secondary)
                    }
                    Text(new == 1 ? "1 EV" : "\(new) EVs").bold()
                    Text("(Speed \(solution.snapshot.speed))").foregroundStyle(.secondary)
                    Spacer()
                    if now != new {
                        Button("Apply") {
                            side.setEV(.speed, to: new)
                            dismiss()
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .monospacedDigit()
            case .failure:
                Text("Can't outspeed within the EV budget")
                    .foregroundStyle(.orange)
            }
        }
    }
}

// MARK: - Solve inputs & results

private enum CertaintyChoice: String, CaseIterable, Identifiable {
    case guaranteed, likely
    var id: String { rawValue }
    var label: String {
        switch self {
        case .guaranteed: return "Every roll"
        case .likely:     return "Most rolls (≥ 50%)"
        }
    }
    var solverValue: EVSolver.Certainty {
        switch self {
        case .guaranteed: return .guaranteed
        case .likely:     return .chance(atLeast: 0.5)
        }
    }
}

/// Everything the sheet shows, computed together in one detached task.
private nonisolated struct SolveResults: Sendable {
    var survive: Result<EVSolver.Solution, EVSolver.Failure>
    var ko: Result<EVSolver.Solution, EVSolver.Failure>
    /// Each side's Speed solve against the other's current Speed stat.
    var attackerOutspeeds: Result<EVSolver.Solution, EVSolver.Failure>
    var defenderOutspeeds: Result<EVSolver.Solution, EVSolver.Failure>
    var attackerSpeedStat: Int
    var defenderSpeedStat: Int

    static func compute(move: MoveSnapshot, attacker: CalcSnapshot,
                        defender: CalcSnapshot, field: FieldSnapshot,
                        certainty: EVSolver.Certainty) -> SolveResults {
        SolveResults(
            survive: EVSolver.minimumToSurvive(move: move, attacker: attacker,
                                               defender: defender, field: field,
                                               certainty: certainty),
            ko: EVSolver.minimumToKO(move: move, attacker: attacker,
                                     defender: defender, field: field,
                                     certainty: certainty),
            attackerOutspeeds: EVSolver.minimumToOutspeed(attacker, targetSpeed: defender.speed),
            defenderOutspeeds: EVSolver.minimumToOutspeed(defender, targetSpeed: attacker.speed),
            attackerSpeedStat: attacker.speed,
            defenderSpeedStat: defender.speed
        )
    }
}

// MARK: - CalcSide bridging

extension EVSolver.Stat {
    var shortLabel: String {
        switch self {
        case .hp:    return "HP"
        case .atk:   return "Atk"
        case .def:   return "Def"
        case .spAtk: return "SpA"
        case .spDef: return "SpD"
        case .speed: return "Spe"
        }
    }
}

extension CalcSide {
    func ev(_ stat: EVSolver.Stat) -> Int {
        switch stat {
        case .hp:    return evHP
        case .atk:   return evAtk
        case .def:   return evDef
        case .spAtk: return evSpAtk
        case .spDef: return evSpDef
        case .speed: return evSpeed
        }
    }

    func setEV(_ stat: EVSolver.Stat, to value: Int) {
        switch stat {
        case .hp:    evHP = value
        case .atk:   evAtk = value
        case .def:   evDef = value
        case .spAtk: evSpAtk = value
        case .spDef: evSpDef = value
        case .speed: evSpeed = value
        }
    }
}
