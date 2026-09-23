//
//  CalcSnapshotTests.swift
//  PKDexTests
//
//  Guards the one real risk in the Phase 2.1 extraction: `CalcSnapshot`
//  reimplements `CalcSide`'s stat and "effective state" accessors, so the two
//  can silently drift apart. Every test here asserts they agree rather than
//  asserting a hardcoded number — that way the check stays valid if the stat
//  formula itself is ever corrected.
//
//  The damage *numbers* are not covered here on purpose. They're already
//  covered far better by the existing suites (the nine `BattleTier` files,
//  `DamageCalcMegaEvolutionTests`, `AbilityTests`, `BattleItemsTests`,
//  `TypeChartTests`), all of which run through `computeSingleResult` and now
//  therefore through `CalcEngine.evaluateLegacy`. Those are the real parity
//  gate for this refactor.
//

import Testing
import Foundation
@testable import PKDex

@MainActor
@Suite("Calc Snapshot — Parity with CalcSide")
struct CalcSnapshotTests {

    // MARK: - Fixtures

    private static func charizard() -> PKMNStats {
        PKMNStats(
            id: 6, speciesID: 6, name: "Charizard", formName: nil,
            type1: "Fire", type2: "Flying",
            baseHP: 78, baseAtk: 84, baseDef: 78,
            baseSpAtk: 109, baseSpDef: 85, baseSpeed: 100,
            ability1: "blaze", hiddenAbility: "solar-power"
        )
    }

    private static func dragonAscent() -> MoveData {
        MoveData(id: 620, name: "Dragon Ascent", type: "Flying",
                 damageClass: "physical", power: 120, accuracy: 100,
                 pp: 5, priority: 0, makesContact: true, generationId: 6)
    }

    /// A side with every knob turned off centre, so a mismatch in any one of
    /// EV / IV / nature / stage handling shows up.
    private static func loadedSide() -> CalcSide {
        let side = CalcSide()
        side.pokemon = charizard()
        side.level = 50
        side.nature = allNatures.first { $0.id == "modest" }!
        side.selectedAbility = "blaze"
        side.heldItem = .lifeOrb
        side.evHP = 252; side.evAtk = 0; side.evDef = 4
        side.evSpAtk = 252; side.evSpDef = 0; side.evSpeed = 0
        side.ivHP = 31; side.ivAtk = 0; side.ivDef = 31
        side.ivSpAtk = 31; side.ivSpDef = 31; side.ivSpeed = 31
        side.atkStage = -1; side.defStage = 2
        side.spAtkStage = 1; side.spDefStage = 0; side.speedStage = -2
        return side
    }

    /// Asserts every stat accessor agrees between a side and its snapshot.
    private static func expectStatsMatch(_ side: CalcSide,
                                         _ snap: CalcSnapshot,
                                         _ label: Comment) {
        #expect(snap.hp == side.hp, label)
        #expect(snap.atk == side.atk, label)
        #expect(snap.def == side.def, label)
        #expect(snap.spAtk == side.spAtk, label)
        #expect(snap.spDef == side.spDef, label)
        #expect(snap.speed == side.speed, label)
    }

    // MARK: - Stat parity

    @Test("Stats match across EVs, IVs, nature and stat stages")
    func statsMatchLoadedSide() throws {
        let side = Self.loadedSide()
        let snap = try #require(side.snapshot())
        Self.expectStatsMatch(side, snap, "mainline, loaded")
    }

    @Test("Stats match in Champions mode")
    func statsMatchChampionsMode() throws {
        // Champions stores EVs on the 0-32 scale and pins IVs at 31, so this
        // exercises the `formulaEV` / `formulaIV` translation specifically.
        let side = Self.loadedSide()
        side.championsMode = true
        side.evHP = 32; side.evAtk = 0; side.evDef = 2
        side.evSpAtk = 32; side.evSpDef = 0; side.evSpeed = 0
        // Deliberately non-31 IVs: Champions must ignore them entirely.
        side.ivSpAtk = 7; side.ivHP = 3
        let snap = try #require(side.snapshot())
        Self.expectStatsMatch(side, snap, "champions")
    }

    @Test("Stats match at every nature", arguments: allNatures.map(\.id))
    func statsMatchPerNature(natureID: String) throws {
        let side = Self.loadedSide()
        side.nature = allNatures.first { $0.id == natureID }!
        let snap = try #require(side.snapshot())
        Self.expectStatsMatch(side, snap, "nature: \(natureID)")
    }

    @Test("Stats match across the stat-stage range", arguments: -6...6)
    func statsMatchPerStage(stage: Int) throws {
        let side = Self.loadedSide()
        side.atkStage = stage; side.defStage = stage
        side.spAtkStage = stage; side.spDefStage = stage; side.speedStage = stage
        let snap = try #require(side.snapshot())
        Self.expectStatsMatch(side, snap, "stage: \(stage)")
    }

    @Test("Stats match with a Mega active")
    func statsMatchWithMega() throws {
        let side = Self.loadedSide()
        side.heldItem = .charizarditeX
        side.megaActive = true
        // Guard the premise: if the Mega didn't resolve, the test would be
        // comparing two un-Mega'd sides and pass for the wrong reason.
        #expect(side.activeMegaForm != nil)

        let snap = try #require(side.snapshot())
        #expect(snap.megaForm != nil)
        Self.expectStatsMatch(side, snap, "mega charizard x")
        #expect(snap.effectiveTypes == side.effectiveTypes)
        #expect(snap.effectiveAbility == side.effectiveAbility)
        #expect(snap.effectiveDisplayName == side.effectiveDisplayName)
        // Stone-based Megas consume the stone, so the calc sees no item.
        #expect(snap.effectiveHeldItem == side.effectiveHeldItem)
        #expect(snap.effectiveHeldItem == .none)
    }

    @Test("Mega Rayquaza keeps its item and resolves off Dragon Ascent")
    func megaRayquazaKeepsItem() throws {
        let side = CalcSide()
        side.pokemon = PKMNStats(
            id: 384, speciesID: 384, name: "Rayquaza", formName: nil,
            type1: "Dragon", type2: "Flying",
            baseHP: 105, baseAtk: 150, baseDef: 90,
            baseSpAtk: 150, baseSpDef: 90, baseSpeed: 95,
            ability1: "air-lock"
        )
        side.heldItem = .lifeOrb
        side.moves[0] = Self.dragonAscent()
        side.megaActive = true
        #expect(side.activeMegaForm != nil)

        let snap = try #require(side.snapshot())
        // Rayquaza's trigger is the move, not a stone, so Life Orb survives.
        #expect(snap.effectiveHeldItem == .lifeOrb)
        #expect(snap.effectiveHeldItem == side.effectiveHeldItem)
        Self.expectStatsMatch(side, snap, "mega rayquaza")
    }

    // MARK: - Effective state parity

    @Test("Types and ability match without a Mega")
    func effectiveStateMatches() throws {
        let side = Self.loadedSide()
        let snap = try #require(side.snapshot())
        #expect(snap.effectiveTypes == side.effectiveTypes)
        #expect(snap.types == side.types)
        #expect(snap.effectiveAbility == side.effectiveAbility)
        #expect(snap.effectiveHeldItem == side.effectiveHeldItem)
        #expect(snap.effectiveDisplayName == side.effectiveDisplayName)
        #expect(snap.effectiveBaseAtk == side.effectiveBaseAtk)
        #expect(snap.effectiveBaseSpAtk == side.effectiveBaseSpAtk)
        #expect(snap.effectiveBaseSpeed == side.effectiveBaseSpeed)
    }

    @Test("EV caps and totals match")
    func evBudgetMatches() throws {
        let side = Self.loadedSide()
        let snap = try #require(side.snapshot())
        #expect(snap.evPerStatMax == side.evPerStatMax)
        #expect(snap.evTotalMax == side.evTotalMax)
        #expect(snap.totalEVs == side.totalEVs)

        side.championsMode = true
        let champSnap = try #require(side.snapshot())
        #expect(champSnap.evPerStatMax == side.evPerStatMax)
        #expect(champSnap.evTotalMax == side.evTotalMax)
    }

    // MARK: - Snapshot plumbing

    @Test("A side with no species yields no snapshot")
    func emptySideYieldsNil() {
        #expect(CalcSide().snapshot() == nil)
    }

    @Test("Only filled move slots are carried over")
    func movesAreCompacted() throws {
        let side = Self.loadedSide()
        side.moves[0] = Self.dragonAscent()
        side.moves[2] = MoveData(id: 53, name: "Flamethrower", type: "Fire",
                                 damageClass: "special", power: 90)
        let snap = try #require(side.snapshot())
        #expect(snap.moves.count == 2)
        // Explicit closure, not a key path: `#expect`'s expansion can't infer
        // the key-path root (same issue as in ShowdownPasteImportTests).
        let names = snap.moves.map { $0.name }
        #expect(names == ["Dragon Ascent", "Flamethrower"])
    }

    // MARK: - Solver support

    @Test("The EV domain covers only values that move a stat")
    func evDomain() throws {
        let side = Self.loadedSide()
        let mainline = try #require(side.snapshot()).evDomain
        // 0...252 in steps of 4 — the formula divides EVs by 4, so nothing
        // between those points changes the result.
        #expect(mainline.count == 64)
        #expect(mainline.first == 0)
        #expect(mainline.last == 252)
        #expect(mainline.allSatisfy { $0 % 4 == 0 })

        side.championsMode = true
        let champions = try #require(side.snapshot()).evDomain
        #expect(champions.count == 33)
        #expect(champions.last == 32)
    }

    @Test("settingEV changes one stat and leaves the rest alone")
    func settingEV() throws {
        let snap = try #require(Self.loadedSide().snapshot())
        let bumped = snap.settingEV(.spDef, to: 100)
        #expect(bumped.evSpDef == 100)
        #expect(bumped.spDef > snap.spDef)
        // Everything else is untouched.
        #expect(bumped.evHP == snap.evHP)
        #expect(bumped.evSpAtk == snap.evSpAtk)
        #expect(bumped.atk == snap.atk)
        #expect(bumped.hp == snap.hp)
    }

    @Test("settingHPEV moves HP only")
    func settingHPEV() throws {
        let snap = try #require(Self.loadedSide().snapshot())
        let bumped = snap.settingHPEV(to: 0)
        #expect(bumped.evHP == 0)
        #expect(bumped.hp < snap.hp)
        #expect(bumped.spAtk == snap.spAtk)
    }
}

// MARK: - Outcome

@Suite("Calc Outcome — Derived Values")
struct CalcOutcomeTests {

    private static func outcome(min: Double, max: Double, hp: Int,
                                rolls: [Int]? = nil) -> CalcOutcome {
        CalcOutcome(damageMin: min, damageMax: max, defenderHP: hp,
                    effectiveness: 1, isSTAB: false, rolls: rolls)
    }

    @Test("Percentages are damage over max HP, capped at 999")
    func percentages() {
        let o = Self.outcome(min: 50, max: 100, hp: 200)
        #expect(o.minPercent == 25)
        #expect(o.maxPercent == 50)
        // A huge overkill is clamped rather than reported as thousands.
        #expect(Self.outcome(min: 5000, max: 9000, hp: 100).maxPercent == 999)
    }

    @Test("Zero max HP doesn't divide by zero")
    func zeroHP() {
        let o = Self.outcome(min: 10, max: 20, hp: 0)
        #expect(o.minPercent == 0)
        #expect(o.maxPercent == 0)
        #expect(o.isGuaranteedOHKO == false)
        #expect(o.isGuaranteedSurvival == false)
        #expect(o.hitsToKOText == "--")
    }

    @Test("Guaranteed-KO and guaranteed-survival predicates")
    func predicates() {
        // Lowest roll already KOs.
        let certain = Self.outcome(min: 200, max: 240, hp: 200)
        #expect(certain.isGuaranteedOHKO)
        #expect(certain.isGuaranteedSurvival == false)

        // Highest roll still doesn't.
        let survives = Self.outcome(min: 100, max: 199, hp: 200)
        #expect(survives.isGuaranteedOHKO == false)
        #expect(survives.isGuaranteedSurvival)

        // Straddling the line is neither.
        let roll = Self.outcome(min: 190, max: 210, hp: 200)
        #expect(roll.isGuaranteedOHKO == false)
        #expect(roll.isGuaranteedSurvival == false)
    }

    @Test("Hit-count label collapses when min and max agree")
    func hitsToKOText() {
        // 50% max, 50% min -> exactly 2HKO both ways.
        #expect(Self.outcome(min: 100, max: 100, hp: 200).hitsToKOText == "2HKO")
        // 50% max, 25% min -> 2 to 4 hits.
        #expect(Self.outcome(min: 50, max: 100, hp: 200).hitsToKOText == "2-4HKO")
        // No damage at all.
        #expect(Self.outcome(min: 0, max: 0, hp: 200).hitsToKOText == "--")
    }

    @Test("OHKO chance needs rolls and is nil without them")
    func ohkoChance() {
        #expect(Self.outcome(min: 100, max: 300, hp: 200).ohkoChance == nil)

        let withRolls = Self.outcome(min: 100, max: 300, hp: 200,
                                     rolls: [100, 150, 200, 300])
        // Two of the four rolls reach 200.
        #expect(withRolls.ohkoChance == 0.5)
    }
}
