//
//  EVSolverTests.swift
//  PKDexTests
//
//  The solver's answers are checked by property, not by hardcoded EV values:
//  the goal holds at the solution, and nothing cheaper meets it. Minimality
//  is checked by an independent brute force over the whole grid, so a pruning
//  bug in the solver can't hide behind a test that shares its logic.
//
//  Legacy-engine cases use made-up species (championsMode off). Champions
//  cases use real species and moves from the bundled Champions data, since
//  that's the only path with per-roll damage and the Psyshock / Body Press /
//  Foul Play special cases the stat probe has to discover.
//

import Testing
import Foundation
@testable import PKDex

@Suite("EV Solver")
struct EVSolverTests {

    // MARK: - Fixtures

    private static let serious = allNatures.first { $0.id == "serious" }!

    private static func species(_ name: String, _ t1: String, _ t2: String? = nil,
                                _ s: (Int, Int, Int, Int, Int, Int)) -> SpeciesSnapshot {
        SpeciesSnapshot(name: name, type1: t1, type2: t2,
                        baseHP: s.0, baseAtk: s.1, baseDef: s.2,
                        baseSpAtk: s.3, baseSpDef: s.4, baseSpeed: s.5)
    }

    private static func side(_ species: SpeciesSnapshot, champions: Bool = false,
                             level: Int? = nil) -> CalcSnapshot {
        CalcSnapshot(species: species, megaForm: nil, nature: serious,
                     level: level ?? (champions ? 50 : 100), selectedAbility: nil,
                     heldItem: .none, moves: [], championsMode: champions)
    }

    private static func move(_ name: String, _ type: String, _ cls: String,
                             _ power: Int?, contact: Bool = false) -> MoveSnapshot {
        MoveSnapshot(id: 1, name: name, type: type, damageClass: cls,
                     power: power, makesContact: contact)
    }

    // Legacy-engine cast.
    private static let bruiser = species("Bruiser", "Normal", nil, (80, 120, 80, 120, 80, 100))
    private static let wall = species("Wall", "Water", nil, (90, 70, 90, 70, 90, 60))
    private static let slam = move("Test Slam", "Normal", "physical", 110, contact: true)
    /// Big enough that the uninvested Wall is KO'd but a full HP + Def spread
    /// survives, so the survive solves have a non-trivial answer.
    private static let quake = move("Test Quake", "Normal", "physical", 200)
    private static let beam = move("Test Beam", "Normal", "special", 200)
    /// Doesn't KO the Sturdy target at 0 Atk, does at 252.
    private static let hammer = move("Test Hammer", "Normal", "physical", 150, contact: true)
    private static let sturdy = species("Sturdy", "Normal", nil, (80, 50, 60, 50, 60, 50))

    private static let field = FieldSnapshot()

    private static func evaluate(_ m: MoveSnapshot, _ a: CalcSnapshot,
                                 _ d: CalcSnapshot) -> CalcOutcome {
        CalcEngine.evaluate(move: m, attacker: a, defender: d, field: field)
    }

    // MARK: - Survive

    @Test("Survive: the solution survives and no cheaper spread does")
    func surviveIsMinimal() throws {
        let atk = Self.side(Self.bruiser).settingEV(.atk, to: 252)
        let def = Self.side(Self.wall)
        let solution = try EVSolver.minimumToSurvive(
            move: Self.quake, attacker: atk, defender: def, field: Self.field).get()

        #expect(solution.cost > 0, "premise: the uninvested Wall must not survive")
        #expect(Set(solution.evs.keys) == [.hp, .def], "physical hit varies HP + Def")
        #expect(try #require(solution.outcome).isGuaranteedSurvival)
        #expect(!solution.usedRolls)

        // Independent brute force: every spread strictly cheaper must fail.
        for hp in def.evDomain {
            for d in def.evDomain where hp + d < solution.cost {
                let probe = def.settingHPEV(to: hp).settingEV(.def, to: d)
                #expect(!Self.evaluate(Self.quake, atk, probe).isGuaranteedSurvival,
                        "cheaper spread \(hp) HP / \(d) Def also survives")
            }
        }
    }

    @Test("Survive: finds an HP-heavy spread when HP is the cheaper bulk")
    func surviveFindsHPHeavySpread() throws {
        // Low HP, high Def: each HP EV buys more bulk than a Def EV, so the
        // cheapest spread has HP in it. The Wall above happens to be cheapest
        // at 0 HP, the first row scanned, so it couldn't tell a minimal solve
        // from one that just returned the first survivable spread.
        let shell = Self.species("Shell", "Water", nil, (50, 50, 150, 50, 90, 50))
        let atk = Self.side(Self.bruiser).settingEV(.atk, to: 252)
        let def = Self.side(shell)
        let solution = try EVSolver.minimumToSurvive(
            move: Self.quake, attacker: atk, defender: def, field: Self.field).get()

        #expect(try #require(solution.evs[.hp]) > 0,
                "premise: the cheapest spread for a low-HP / high-Def mon needs HP")
        #expect(try #require(solution.outcome).isGuaranteedSurvival)
        for hp in def.evDomain {
            for d in def.evDomain where hp + d < solution.cost {
                let probe = def.settingHPEV(to: hp).settingEV(.def, to: d)
                #expect(!Self.evaluate(Self.quake, atk, probe).isGuaranteedSurvival,
                        "cheaper spread \(hp) HP / \(d) Def also survives")
            }
        }
    }

    @Test("Survive: a special hit varies SpD, not Def")
    func surviveSpecialUsesSpDef() throws {
        let atk = Self.side(Self.bruiser).settingEV(.spAtk, to: 252)
        let solution = try EVSolver.minimumToSurvive(
            move: Self.beam, attacker: atk, defender: Self.side(Self.wall),
            field: Self.field).get()
        #expect(solution.cost > 0, "premise: the uninvested Wall must not survive")
        #expect(Set(solution.evs.keys) == [.hp, .spDef])
    }

    @Test("Survive: existing investment elsewhere shrinks the budget")
    func surviveRespectsBudget() {
        let atk = Self.side(Self.bruiser).settingEV(.atk, to: 252)
        // 252 Atk + 252 Spe leaves 6 EVs, which rounds to nothing useful.
        let def = Self.side(Self.wall).settingEV(.atk, to: 252).settingEV(.speed, to: 252)
        let result = EVSolver.minimumToSurvive(
            move: Self.quake, attacker: atk, defender: def, field: Self.field)

        // Unreachable is the expected answer only if the unbudgeted solve
        // needs more than 4 EVs, so pin that premise first.
        let free = try? EVSolver.minimumToSurvive(
            move: Self.quake, attacker: atk, defender: Self.side(Self.wall),
            field: Self.field).get()
        if let free, free.cost <= 4 {
            Issue.record("premise broken: the free solve only needs \(free.cost) EVs")
            return
        }

        guard case .failure(.unreachable(let best)) = result else {
            Issue.record("expected unreachable, got \(result)")
            return
        }
        #expect(best != nil, "unreachable reports the max-investment outcome")
    }

    @Test("Survive: existing investment in the solved stats is freed up")
    func surviveReplacesSolvedStats() throws {
        let atk = Self.side(Self.bruiser).settingEV(.atk, to: 252)
        let fresh = Self.side(Self.wall)
        let preloaded = fresh.settingHPEV(to: 252).settingEV(.def, to: 252)
        let a = try EVSolver.minimumToSurvive(move: Self.quake, attacker: atk,
                                              defender: fresh, field: Self.field).get()
        let b = try EVSolver.minimumToSurvive(move: Self.quake, attacker: atk,
                                              defender: preloaded, field: Self.field).get()
        #expect(a.cost > 0, "premise: the solve needs investment")
        #expect(a.evs == b.evs)
    }

    // MARK: - KO

    @Test("KO: the solution KOs and one step less doesn't")
    func koIsMinimal() throws {
        let atk = Self.side(Self.bruiser)
        let def = Self.side(Self.sturdy)
        let solution = try EVSolver.minimumToKO(
            move: Self.hammer, attacker: atk, defender: def, field: Self.field).get()

        #expect(solution.cost > 0, "premise: 0 Atk must not already KO")
        #expect(Set(solution.evs.keys) == [.atk])
        #expect(try #require(solution.outcome).isGuaranteedOHKO)

        let spent = solution.evs[.atk]!
        if let below = atk.evDomain.last(where: { $0 < spent }) {
            let weaker = atk.settingEV(.atk, to: below)
            #expect(!Self.evaluate(Self.hammer, weaker, def).isGuaranteedOHKO)
        }
    }

    @Test("KO: out of reach reports the max-investment outcome")
    func koUnreachable() {
        let result = EVSolver.minimumToKO(
            move: Self.slam, attacker: Self.side(Self.bruiser),
            defender: Self.side(Self.wall).settingHPEV(to: 252).settingEV(.def, to: 252),
            field: Self.field)
        guard case .failure(.unreachable(let best?)) = result else {
            Issue.record("expected unreachable with an outcome, got \(result)")
            return
        }
        #expect(!best.isGuaranteedOHKO)
    }

    @Test("A status move can't be solved against")
    func statusMove() {
        let growl = Self.move("Growl", "Normal", "status", nil)
        let result = EVSolver.minimumToKO(
            move: growl, attacker: Self.side(Self.bruiser),
            defender: Self.side(Self.wall), field: Self.field)
        #expect(result == .failure(.notApplicable("status move")))
    }

    @Test("A move with no EV-dependent damage reports noRelevantStat")
    func noRelevantStat() {
        let nothing = Self.move("Zero", "Normal", "physical", nil)
        let result = EVSolver.minimumToKO(
            move: nothing, attacker: Self.side(Self.bruiser),
            defender: Self.side(Self.wall), field: Self.field)
        #expect(result == .failure(.noRelevantStat))
    }

    @Test(".chance falls back to guaranteed without rolls")
    func chanceFallsBackOnLegacy() throws {
        let atk = Self.side(Self.bruiser).settingEV(.atk, to: 252)
        let def = Self.side(Self.wall)
        let guaranteed = try EVSolver.minimumToSurvive(
            move: Self.quake, attacker: atk, defender: def, field: Self.field).get()
        let chance = try EVSolver.minimumToSurvive(
            move: Self.quake, attacker: atk, defender: def, field: Self.field,
            certainty: .chance(atLeast: 0.5)).get()
        #expect(guaranteed.cost > 0, "premise: the solve needs investment")
        #expect(chance.evs == guaranteed.evs)
        #expect(!chance.usedRolls)
    }

    // MARK: - Speed

    @Test("Speed: outspeeds by the smallest step, and ties only when allowed")
    func speed() throws {
        let side = Self.side(Self.bruiser)
        let target = side.settingEV(.speed, to: 100).speed

        let outspeed = try EVSolver.minimumToOutspeed(side, targetSpeed: target).get()
        #expect(outspeed.snapshot.speed > target)
        let spent = outspeed.evs[.speed]!
        if let below = side.evDomain.last(where: { $0 < spent }) {
            #expect(side.settingEV(.speed, to: below).speed <= target)
        }

        let tie = try EVSolver.minimumToOutspeed(side, targetSpeed: target,
                                                 allowTie: true).get()
        #expect(tie.snapshot.speed >= target)
        #expect(tie.evs[.speed]! <= spent)
    }

    @Test("Speed: a multiplier (Scarf) lowers the requirement")
    func speedMultiplier() throws {
        let side = Self.side(Self.bruiser)
        let target = side.settingEV(.speed, to: 252).speed
        let scarf = try EVSolver.minimumToOutspeed(side, targetSpeed: target,
                                                   multiplier: 1.5).get()
        #expect(scarf.evs[.speed]! < 252)
    }

    // MARK: - Champions path

    private static let garchomp = species("Garchomp", "Dragon", "Ground", (108, 130, 95, 80, 85, 102))
    private static let snorlax = species("Snorlax", "Normal", nil, (160, 110, 65, 65, 110, 30))

    @Test("Champions: roll-level chance needs no more EVs than guaranteed")
    func championsChance() throws {
        let atk = Self.side(Self.garchomp, champions: true).settingEV(.atk, to: 32)
        let def = Self.side(Self.garchomp, champions: true)
        // Outrage is super effective on Garchomp: an OHKO uninvested, survivable
        // with full bulk, so both solves land somewhere in between.
        let outrage = Self.move("Outrage", "Dragon", "physical", 120, contact: true)

        // Premise: this matchup really is on the Champions path.
        #expect(CalcEngine.evaluateChampions(move: outrage, attacker: atk, defender: def,
                                             field: Self.field)?.rolls != nil)

        let guaranteed = try EVSolver.minimumToSurvive(
            move: outrage, attacker: atk, defender: def, field: Self.field).get()
        let likely = try EVSolver.minimumToSurvive(
            move: outrage, attacker: atk, defender: def, field: Self.field,
            certainty: .chance(atLeast: 0.5)).get()
        #expect(guaranteed.cost > 0, "premise: uninvested Garchomp must not survive")
        #expect(likely.usedRolls)
        #expect(likely.cost <= guaranteed.cost)
    }

    @Test("Champions: Psyshock is survived with Def, not SpD")
    func championsPsyshock() throws {
        let atk = Self.side(Self.garchomp, champions: true).settingEV(.spAtk, to: 32)
        let def = Self.side(Self.snorlax, champions: true)
        let psyshock = Self.move("Psyshock", "Psychic", "special", 80)
        let result = EVSolver.minimumToSurvive(move: psyshock, attacker: atk,
                                               defender: def, field: Self.field)
        let solution = try result.get()
        #expect(solution.evs[.def] != nil)
        #expect(solution.evs[.spDef] == nil)
    }

    @Test("Champions: Body Press is powered by the user's Def")
    func championsBodyPress() {
        let atk = Self.side(Self.snorlax, champions: true)
        let def = Self.side(Self.species("Kingambit", "Dark", "Steel", (100, 135, 120, 60, 85, 50)),
                            champions: true)
        let press = Self.move("Body Press", "Fighting", "physical", 80, contact: true)
        switch EVSolver.minimumToKO(move: press, attacker: atk, defender: def,
                                    field: Self.field) {
        case .success(let s):
            #expect(s.evs.keys.contains(.def))
        case .failure(.unreachable(let best)):
            // Not a KO at any investment is fine; the stat choice is what's
            // under test, and it's visible in the maxed-out damage.
            #expect(best != nil)
            #expect(EVSolver.mostRelevant(of: [.atk, .spAtk, .def], on: atk) {
                CalcEngine.evaluate(move: press, attacker: $0, defender: def,
                                    field: Self.field).damageMax
            } == .def)
        case .failure(let other):
            Issue.record("unexpected \(other)")
        }
    }

    @Test("Champions: Foul Play has no attacker stat to invest in")
    func championsFoulPlay() {
        let atk = Self.side(Self.snorlax, champions: true)
        let def = Self.side(Self.garchomp, champions: true)
        let foul = Self.move("Foul Play", "Dark", "physical", 95, contact: true)
        #expect(EVSolver.minimumToKO(move: foul, attacker: atk, defender: def,
                                     field: Self.field) == .failure(.noRelevantStat))
    }
}
