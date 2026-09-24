//
//  TwoHitSolverTests.swift
//  PKDexTests
//
//  The two-hit solver plays candidate spreads out in the battle simulator.
//  These tests check that the sim agrees with the calc on a single hit (the
//  answers mean nothing otherwise), that answers are minimal against an
//  independent brute force over the same simulation, and that between-hit
//  effects and doubles spread actually change the answer.
//

import Testing
import Foundation
@testable import PKDex

@MainActor
@Suite("EV Solver — Two Hits")
struct TwoHitSolverTests {

    // MARK: - Fixtures

    private static func mon(_ name: String, id: Int, type1: String, type2: String? = nil,
                            _ s: (Int, Int, Int, Int, Int, Int)) -> PKMNStats {
        PKMNStats(id: id, speciesID: id, name: name, type1: type1, type2: type2,
                  baseHP: s.0, baseAtk: s.1, baseDef: s.2, baseSpAtk: s.3,
                  baseSpDef: s.4, baseSpeed: s.5, ability1: "rough-skin")
    }

    private static func move(_ name: String, type: String, _ cls: String, _ power: Int) -> MoveData {
        MoveData(id: 900 + power, name: name, type: type, damageClass: cls, power: power,
                 accuracy: 100, pp: 16, priority: 0, minHits: nil, maxHits: nil,
                 drain: 0, healing: 0, critRate: 0, makesContact: cls == "physical")
    }

    private static let garchomp = mon("Garchomp", id: 445, type1: "Dragon", type2: "Ground",
                                      (108, 130, 95, 80, 85, 102))
    private static let claw = move("Dragon Claw", type: "Dragon", "physical", 80)
    private static let voice = move("Hyper Voice", type: "Normal", "special", 90)
    /// Super effective on Garchomp, about half its HP per hit uninvested: two
    /// hits KO at 0 EVs, a bulky spread survives, and Sitrus (at 50%) matters.
    private static let midHit = move("Test Strike", type: "Dragon", "physical", 50)

    /// A Champions-mode calc: Garchomp (P1, 32 Atk / 32 SpA) vs Garchomp (P2).
    /// The move defaults to Dragon Claw. The default is nil, not `claw`,
    /// because default arguments are evaluated off the main actor.
    private static func calc(attackerMove: MoveData? = nil) -> DamageCalcVM {
        let vm = DamageCalcVM()
        for side in [vm.side1, vm.side2] {
            side.pokemon = garchomp
            side.championsMode = true
            side.level = 50
            side.nature = allNatures.first { $0.id == "serious" }!
            side.selectedAbility = "rough-skin"
        }
        vm.side1.evAtk = 32
        vm.side1.evSpAtk = 32
        vm.side1.moves = [attackerMove ?? claw, nil, nil, nil]
        return vm
    }

    private static func run(_ vm: DamageCalcVM, _ move: MoveData,
                            defenderEVs: [EVSolver.Stat: Int] = [:],
                            rolls: (BattleEngine.RollOverride.Roll, BattleEngine.RollOverride.Roll) = (.max, .max),
                            hits: Int = 2) -> TwoHitSolver.Run {
        TwoHitSolver.simulate(vm: vm, attacker: vm.side1, defender: vm.side2, move: move,
                              defenderEVs: defenderEVs, rolls: rolls, hits: hits)
    }

    // MARK: - Parity with the calc

    @Test("A single simulated hit matches the calc engine", arguments: [0, 16, 32])
    func singleHitParity(hpPoints: Int) throws {
        let vm = Self.calc()
        let def = try #require(vm.side2.snapshot()).settingHPEV(to: hpPoints)
        let calc = CalcEngine.evaluate(move: Self.claw.snapshot(),
                                       attacker: try #require(vm.side1.snapshot()),
                                       defender: def, field: vm.fieldSnapshot())
        for (roll, expected) in [(BattleEngine.RollOverride.Roll.max, calc.damageMax),
                                 (.min, calc.damageMin)] {
            let sim = Self.run(vm, Self.claw, defenderEVs: [.hp: hpPoints], rolls: (roll, roll), hits: 1)
            #expect(Double(sim.defenderHPLost) == expected, "\(roll): sim \(sim.defenderHPLost) vs calc \(expected)")
        }
    }

    // MARK: - Survive two hits

    @Test("Survive two hits: the answer survives and nothing cheaper does")
    func surviveIsMinimal() async throws {
        let vm = Self.calc()
        let weak = Self.midHit
        vm.side1.moves = [weak, nil, nil, nil]
        let answer = await TwoHitSolver.solve(.survive, vm: vm, attacker: vm.side1,
                                              defender: vm.side2, move: weak)
        let solution = try answer.result.get()
        #expect(solution.cost > 0, "premise: the uninvested defender must not survive two hits")
        #expect(!Self.run(vm, weak, defenderEVs: solution.evs).defenderFainted)

        let defensive = try #require(solution.evs.keys.first { $0 != .hp })
        let domain = try #require(vm.side2.snapshot()).evDomain
        for hp in domain {
            for d in domain where hp + d < solution.cost {
                let run = Self.run(vm, weak, defenderEVs: [.hp: hp, defensive: d])
                #expect(run.defenderFainted, "cheaper \(hp) HP / \(d) survives two hits")
            }
        }
    }

    @Test("Two hits need more bulk than one")
    func twoHitsCostMoreThanOne() async throws {
        let vm = Self.calc()
        let weak = Self.midHit
        vm.side1.moves = [weak, nil, nil, nil]
        let one = try EVSolver.minimumToSurvive(
            move: weak.snapshot(), attacker: try #require(vm.side1.snapshot()),
            defender: try #require(vm.side2.snapshot()), field: vm.fieldSnapshot()).get()
        let two = try await TwoHitSolver.solve(.survive, vm: vm, attacker: vm.side1,
                                               defender: vm.side2, move: weak).result.get()
        #expect(two.cost > one.cost)
    }

    @Test("Sitrus Berry between hits lowers the requirement")
    func sitrusHelps() async throws {
        let weak = Self.midHit
        let plain = Self.calc(); plain.side1.moves = [weak, nil, nil, nil]
        let berry = Self.calc(); berry.side1.moves = [weak, nil, nil, nil]
        berry.side2.heldItem = .sitrusBerry
        let without = await TwoHitSolver.solve(.survive, vm: plain, attacker: plain.side1,
                                               defender: plain.side2, move: weak)
        let with = await TwoHitSolver.solve(.survive, vm: berry, attacker: berry.side1,
                                            defender: berry.side2, move: weak)
        let solution = try with.result.get()
        let withoutCost = (try? without.result.get())?.cost ?? Int.max
        #expect(solution.cost < withoutCost)

        // A smaller first hit may not reach the berry's 50% trigger, so the
        // answer has to hold at every first-hit roll, not just the max.
        for step in 0...16 {
            let run = Self.run(berry, weak, defenderEVs: solution.evs,
                               rolls: (.fraction(Double(step) / 16), .max))
            #expect(!run.defenderFainted, "faints when the first hit is roll \(step)/16")
        }
    }

    // MARK: - 2HKO

    @Test("2HKO: the answer KOs on the lowest rolls and one step less doesn't")
    func twoHKOIsMinimal() async throws {
        let vm = Self.calc()
        vm.side1.evAtk = 0
        // Full bulk, so the 2HKO needs Attack investment.
        vm.side2.evHP = 32
        vm.side2.evDef = 32
        let answer = await TwoHitSolver.solve(.ko, vm: vm, attacker: vm.side1,
                                              defender: vm.side2, move: Self.claw)
        let solution = try answer.result.get()
        let spent = try #require(solution.evs[.atk])
        #expect(spent > 0, "premise: 0 Atk must not already 2HKO on the lowest rolls")
        let domain = try #require(vm.side1.snapshot()).evDomain
        vm.side1.evAtk = spent
        #expect(Self.run(vm, Self.claw, rolls: (.min, .min)).defenderFainted)
        if let below = domain.last(where: { $0 < spent }) {
            vm.side1.evAtk = below
            #expect(!Self.run(vm, Self.claw, rolls: (.min, .min)).defenderFainted)
        }
    }

    // MARK: - Doubles spread

    @Test("Spread in doubles: both hits are reduced and the partner stays up")
    func doublesSpread() throws {
        let vm = Self.calc(attackerMove: Self.voice)
        let singles = Self.run(vm, Self.voice, hits: 1)
        vm.multi = true
        let doubles = Self.run(vm, Self.voice, hits: 2)
        let oneDoubleHit = Self.run(vm, Self.voice, hits: 1)
        #expect(oneDoubleHit.defenderHPLost < singles.defenderHPLost)
        #expect(abs(Double(oneDoubleHit.defenderHPLost) - Double(singles.defenderHPLost) * 0.75) <= 2)
        #expect(!doubles.partnerFainted)
    }

    // MARK: - Refusals

    @Test("Refuses matchups the simulator can't reproduce")
    func refusals() {
        let vm = Self.calc()
        vm.side1.isHelpingHand = true
        #expect(TwoHitSolver.unsupportedReason(vm: vm, attacker: vm.side1,
                                               defender: vm.side2, move: Self.claw) != nil)
        let mainline = Self.calc()
        mainline.side2.championsMode = false
        mainline.side2.ivDef = 0
        #expect(TwoHitSolver.unsupportedReason(vm: mainline, attacker: mainline.side1,
                                               defender: mainline.side2, move: Self.claw) != nil)
    }
}
