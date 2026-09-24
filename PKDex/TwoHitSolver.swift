//
//  TwoHitSolver.swift
//  PKDex
//
//  EV goals over two hits: "survive two hits" and "guaranteed 2HKO".
//
//  A naive "add the two hits" is wrong whenever something happens between
//  them: Sitrus Berry heals, Multiscale only works at full HP, Stamina and
//  Weak Armor change Defense, Leftovers heals at end of turn, Eruption loses
//  power as HP drops. Rather than re-derive all of that, each candidate spread
//  is played out in the battle simulator: the attacker uses the move on two
//  consecutive turns, the defender does nothing, and the sim applies every
//  between-hit effect it models.
//
//  "Guaranteed" follows the usual damage-calc reading. Rolls are pinned (max
//  for surviving, min for KOing), crits only if the calc's Crit toggle is on,
//  accuracy always hits, and luck-based effects (secondary effects, Focus
//  Band…) don't happen. When the defender holds an HP berry, a *bigger* first
//  hit can be better for it (it triggers the berry), so the first hit is
//  scanned across its whole range and the goal must hold at every point.
//
//  With the calc's doubles toggle on and a spread move, the run is a doubles
//  battle with a very bulky placeholder partner beside the defender, so both
//  hits take the 0.75x spread reduction.
//
//  The simulator's damage path goes through `DamageCalcVM`, so this runs on the
//  main actor. The solve yields between simulations to keep the UI responsive.
//

import Foundation

@MainActor
enum TwoHitSolver {

    enum Goal { case survive, ko }

    struct Answer {
        var result: Result<EVSolver.Solution, EVSolver.Failure>
        /// Worst-case HP left after both hits (survive), or best-case HP left
        /// for the defender at maximum investment when a KO is unreachable.
        var defenderHPLeftPercent: Int?
    }

    /// First reason the sim can't faithfully play this matchup, or nil.
    static func unsupportedReason(vm: DamageCalcVM, attacker: CalcSide,
                                  defender: CalcSide, move: MoveData) -> String? {
        if move.damageClass == "status" { return "status move" }
        if vm.glaiveRush || vm.zMoveBypass || vm.miscMultiplier != 1 {
            return "Glaive Rush, Z-move bypass and the misc multiplier aren't modelled over two hits"
        }
        if attacker.isHelpingHand { return "Helping Hand isn't modelled over two hits" }
        if defender.isFriendGuard || defender.isProtected {
            return "Friend Guard and Protect aren't modelled over two hits"
        }
        for side in [attacker, defender] where !side.championsMode {
            if [side.ivHP, side.ivAtk, side.ivDef, side.ivSpAtk, side.ivSpDef, side.ivSpeed]
                .contains(where: { $0 != 31 }) {
                return "the battle simulator assumes 31 IVs"
            }
        }
        if [.slp, .frz].contains(attacker.status) {
            return "the attacker is asleep or frozen"
        }
        return nil
    }

    // MARK: - Solving

    static func solve(_ goal: Goal, vm: DamageCalcVM, attacker: CalcSide,
                      defender: CalcSide, move: MoveData) async -> Answer {
        if let reason = unsupportedReason(vm: vm, attacker: attacker,
                                          defender: defender, move: move) {
            return Answer(result: .failure(.notApplicable(reason)))
        }
        guard let atkSnap = attacker.snapshot(), let defSnap = defender.snapshot() else {
            return Answer(result: .failure(.notApplicable("no Pokemon selected")))
        }
        let moveSnap = move.snapshot()
        let field = vm.fieldSnapshot()
        let scanFirstHit = [.sitrusBerry, .oranBerry].contains(defender.effectiveHeldItem)

        switch goal {
        case .survive:
            // Which defensive stat matters is the same question as for one
            // hit, so ask the calc engine rather than the sim.
            let defensive = EVSolver.mostRelevant(of: [.def, .spDef], on: defSnap) {
                CalcEngine.evaluate(move: moveSnap, attacker: atkSnap, defender: $0,
                                    field: field).damageMax
            }
            let stats: [EVSolver.Stat] = [.hp] + [defensive].compactMap { $0 }
            let budget = EVSolver.remainingBudget(defSnap, excluding: stats)
            let domain = defSnap.evDomain

            var best: (evs: [EVSolver.Stat: Int], cost: Int, hpLeft: Int)?
            for hp in domain where hp <= budget {
                for d in (defensive == nil ? [0] : domain) where hp + d <= budget {
                    if let best, hp + d > best.cost { break }
                    var evs: [EVSolver.Stat: Int] = [.hp: hp]
                    if let defensive { evs[defensive] = d }
                    guard let left = await worstCaseHPLeft(
                        vm: vm, attacker: attacker, defender: defender, move: move,
                        defenderEVs: evs, scanFirstHit: scanFirstHit) else { continue }
                    let cost = hp + d
                    if best == nil || cost < best!.cost || (cost == best!.cost && left > best!.hpLeft) {
                        best = (evs, cost, left)
                    }
                    break
                }
            }
            guard let best else { return Answer(result: .failure(.unreachable(best: nil))) }
            let solution = EVSolver.Solution(evs: best.evs,
                                             snapshot: EVSolver.applying(best.evs, to: defSnap),
                                             outcome: nil, usedRolls: false)
            return Answer(result: .success(solution), defenderHPLeftPercent: best.hpLeft)

        case .ko:
            guard let offensive = EVSolver.mostRelevant(of: [.atk, .spAtk, .def], on: atkSnap,
                                                        measure: {
                CalcEngine.evaluate(move: moveSnap, attacker: $0, defender: defSnap,
                                    field: field).damageMax
            }) else { return Answer(result: .failure(.noRelevantStat)) }
            let budget = EVSolver.remainingBudget(atkSnap, excluding: [offensive])

            var lastLeft: Int?
            for value in atkSnap.evDomain where value <= budget {
                let evs = [offensive: value]
                let left = await bestCaseHPLeft(vm: vm, attacker: attacker, defender: defender,
                                                move: move, attackerEVs: evs,
                                                scanFirstHit: scanFirstHit)
                if left == 0 {
                    let solution = EVSolver.Solution(evs: evs,
                                                     snapshot: EVSolver.applying(evs, to: atkSnap),
                                                     outcome: nil, usedRolls: false)
                    return Answer(result: .success(solution))
                }
                lastLeft = left
            }
            return Answer(result: .failure(.unreachable(best: nil)), defenderHPLeftPercent: lastLeft)
        }
    }

    /// Worst-case HP% left after two hits, or nil if any roll KOs. Max rolls;
    /// with an HP berry, the first hit is scanned across its range.
    private static func worstCaseHPLeft(vm: DamageCalcVM, attacker: CalcSide, defender: CalcSide,
                                        move: MoveData, defenderEVs: [EVSolver.Stat: Int],
                                        scanFirstHit: Bool) async -> Int? {
        var worst = Int.max
        for first in firstHitRolls(scan: scanFirstHit, preferred: .max) {
            await Task.yield()
            let run = simulate(vm: vm, attacker: attacker, defender: defender, move: move,
                               defenderEVs: defenderEVs, rolls: (first, .max))
            if run.defenderFainted { return nil }
            worst = min(worst, run.defenderHPLeftPercent)
        }
        return worst
    }

    /// Best-case HP% left for the defender after two hits (0 = KO'd on every
    /// roll). Min rolls; first hit scanned when the defender has an HP berry.
    private static func bestCaseHPLeft(vm: DamageCalcVM, attacker: CalcSide, defender: CalcSide,
                                       move: MoveData, attackerEVs: [EVSolver.Stat: Int],
                                       scanFirstHit: Bool) async -> Int {
        var best = 0
        for first in firstHitRolls(scan: scanFirstHit, preferred: .min) {
            await Task.yield()
            let run = simulate(vm: vm, attacker: attacker, defender: defender, move: move,
                               attackerEVs: attackerEVs, rolls: (first, .min))
            if !run.defenderFainted { best = max(best, max(1, run.defenderHPLeftPercent)) }
        }
        return best
    }

    /// The preferred extreme first (it usually decides), then 17 evenly spaced
    /// points across the range when scanning, roughly the game's 16 rolls.
    private static func firstHitRolls(scan: Bool,
                                      preferred: BattleEngine.RollOverride.Roll) -> [BattleEngine.RollOverride.Roll] {
        guard scan else { return [preferred] }
        return [preferred] + (0...16).map { .fraction(Double($0) / 16) }
    }

    // MARK: - Simulation

    struct Run {
        var defenderFainted: Bool
        var defenderHPLeftPercent: Int
        var defenderHPLost: Int = 0
        /// The placeholder partner fainted, so a later spread hit wasn't spread.
        var partnerFainted: Bool
    }

    /// Plays the attacker using `move` on two consecutive turns against a
    /// passive defender. EV overrides are applied on top of each side's set.
    static func simulate(vm: DamageCalcVM, attacker: CalcSide, defender: CalcSide,
                         move: MoveData,
                         attackerEVs: [EVSolver.Stat: Int] = [:],
                         defenderEVs: [EVSolver.Stat: Int] = [:],
                         rolls: (BattleEngine.RollOverride.Roll, BattleEngine.RollOverride.Roll),
                         hits: Int = 2)
    -> Run {
        guard let atkMon = attacker.pokemon, let defMon = defender.pokemon else {
            return Run(defenderFainted: false, defenderHPLeftPercent: 100, partnerFainted: false)
        }
        let spread = vm.multi && SpreadMoves.isSpread(move.name)
        let format: BattleFormat = spread ? .doubles : .singles

        var atkSlots = [slot(from: attacker, pokemon: atkMon, evs: attackerEVs, moves: [move])]
        var defSlots = [slot(from: defender, pokemon: defMon, evs: defenderEVs, moves: [])]
        var allPokemon = [atkMon, defMon]
        if spread {
            // Placeholders so the spread move has two targets on both turns:
            // enormous bulk, no ability or item.
            let filler = PKMNStats(id: -9001, speciesID: -9001, name: "Solver Partner",
                                   type1: "Normal", type2: nil,
                                   baseHP: 255, baseAtk: 1, baseDef: 255,
                                   baseSpAtk: 1, baseSpDef: 255, baseSpeed: 1,
                                   ability1: nil)
            allPokemon.append(filler)
            let fillerSlot = TeamSlotInfo(spreadName: "solver-partner", pokemonID: filler.id,
                                          pokemonName: filler.name, type1: "Normal",
                                          abilityName: nil, itemRawValue: nil,
                                          championsMode: false, natureID: "hardy", level: 100,
                                          moveSlots: [])
            atkSlots.append(fillerSlot)
            defSlots.append(fillerSlot)
        }

        let s1 = BattleSide(label: "Attacker", slots: atkSlots, format: format,
                            allPokemon: allPokemon, allMoves: [move])
        let s2 = BattleSide(label: "Defender", slots: defSlots, format: format,
                            allPokemon: allPokemon, allMoves: [move])
        let engine = BattleEngine(format: format, side1: s1, side2: s2,
                                  allPokemon: allPokemon, allMoves: [move])
        guard let a = engine.side1.active(at: 0), let d = engine.side2.active(at: 0) else {
            return Run(defenderFainted: false, defenderHPLeftPercent: 100, partnerFainted: false)
        }

        configure(a, from: attacker, burnToggle: vm.burn)
        configure(d, from: defender, burnToggle: false)
        engine.weather = vm.weather
        engine.terrain = vm.terrain
        if vm.gravity { engine.gravityTurns = 5 }
        if vm.wonderRoom { engine.wonderRoomTurns = 5 }
        if vm.magicRoom { engine.magicRoomTurns = 5 }
        if defender.isReflect { engine.side2.reflectTurns = 5 }
        if defender.isLightScreen { engine.side2.lightScreenTurns = 5 }
        if defender.isAuroraVeil { engine.side2.auroraVeilTurns = 5 }
        if attacker.activeMegaForm != nil { engine.pendingMega[0][0] = true }
        if defender.activeMegaForm != nil { engine.pendingMega[1][0] = true }

        let startHP = d.currentHP
        for roll in [rolls.0, rolls.1].prefix(hits) {
            guard !d.fainted, !a.fainted else { break }
            engine.rollOverride = .init(crit: vm.crit, roll: roll, suppressChanceEvents: true)
            engine.setAction(side: 0, slot: 0, action: spread
                             ? .spreadMove(moveIndex: 0)
                             : .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
            engine.executeTurn()
        }

        let partnerFainted = spread && (engine.side2.participants.last?.fainted ?? false)
        let percent = d.maxHP > 0 ? Int((Double(d.currentHP) / Double(d.maxHP) * 100).rounded(.down)) : 0
        return Run(defenderFainted: d.fainted, defenderHPLeftPercent: percent,
                   defenderHPLost: startHP - d.currentHP, partnerFainted: partnerFainted)
    }

    private static func slot(from side: CalcSide, pokemon: PKMNStats,
                             evs: [EVSolver.Stat: Int], moves: [MoveData]) -> TeamSlotInfo {
        func ev(_ stat: EVSolver.Stat) -> Int { evs[stat] ?? side.ev(stat) }
        let types = [pokemon.type1] + [pokemon.type2].compactMap { $0 }
        return TeamSlotInfo(
            spreadName: "solver-\(pokemon.id)", pokemonID: pokemon.id,
            pokemonName: pokemon.name, type1: pokemon.type1, type2: pokemon.type2,
            abilityName: side.selectedAbility,
            itemRawValue: side.heldItem == .none ? nil : side.heldItem.rawValue,
            championsMode: side.championsMode, natureID: side.nature.id, level: side.level,
            evHP: ev(.hp), evAtk: ev(.atk), evDef: ev(.def),
            evSpAtk: ev(.spAtk), evSpDef: ev(.spDef), evSpeed: ev(.speed),
            moveSlots: moves.map {
                TeamMoveInfo(moveID: $0.id, moveName: $0.name, moveType: $0.type,
                             damageClass: $0.damageClass, power: $0.power,
                             isSTAB: $0.damageClass != "status" && types.contains($0.type))
            })
    }

    private static func configure(_ p: BattleParticipant, from side: CalcSide, burnToggle: Bool) {
        p.atkStage = side.atkStage
        p.defStage = side.defStage
        p.spAtkStage = side.spAtkStage
        p.spDefStage = side.spDefStage
        p.speedStage = side.speedStage
        p.status = battleStatus(side.status)
        if burnToggle && p.status == .none { p.status = .burn }
        let pct = max(1, min(100, side.currentHPPercent))
        if pct < 100 { p.currentHP = max(1, p.maxHP * pct / 100) }
    }

    private static func battleStatus(_ status: ShowdownStatus) -> BattleStatus {
        switch status {
        case .brn: return .burn
        case .par: return .paralysis
        case .psn: return .poison
        case .tox: return .toxic
        case .slp: return .sleep
        case .frz: return .freeze
        default:   return .none
        }
    }
}
