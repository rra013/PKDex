//
//  TypeChartTests.swift
//  PKDexTests
//

import Testing
import Foundation
@testable import PKDex

@Suite("Type Chart")
struct TypeChartTests {

    // MARK: - Regression

    /// Originally reported bug: Ice moves were dealing 1.0x to Fire-type defenders
    /// because the Ice row of `typeEffectivenessChart` was missing `"Fire": 0.5`.
    @Test func iceMovesAreResistedByFireDefenders() {
        let eff = computeTypeEffectiveness(moveType: "Ice", defenderTypes: ["Fire"])
        #expect(eff == 0.5)
    }

    @Test func iceMovesQuadrupleResistedByFireSteel() {
        // Heatran is Fire/Steel. Ice → Fire = 0.5, Ice → Steel = 0.5, product = 0.25.
        let eff = computeTypeEffectiveness(moveType: "Ice", defenderTypes: ["Fire", "Steel"])
        #expect(eff == 0.25)
    }

    // MARK: - Smoke tests

    @Test func waterDoubleVsFire() {
        #expect(computeTypeEffectiveness(moveType: "Water", defenderTypes: ["Fire"]) == 2.0)
    }

    @Test func electricImmuneToGround() {
        #expect(computeTypeEffectiveness(moveType: "Electric", defenderTypes: ["Ground"]) == 0)
    }

    @Test func dragonImmuneToFairy() {
        #expect(computeTypeEffectiveness(moveType: "Dragon", defenderTypes: ["Fairy"]) == 0)
    }

    @Test func ghostImmuneToNormal() {
        #expect(computeTypeEffectiveness(moveType: "Normal", defenderTypes: ["Ghost"]) == 0)
    }

    @Test func groundImmuneToFlying() {
        #expect(computeTypeEffectiveness(moveType: "Ground", defenderTypes: ["Flying"]) == 0)
    }

    @Test func iceQuadrupleVsDragonFlying() {
        // Salamence / Dragonite: Ice → Dragon = 2, Ice → Flying = 2, product = 4.
        let eff = computeTypeEffectiveness(moveType: "Ice", defenderTypes: ["Dragon", "Flying"])
        #expect(eff == 4.0)
    }

    @Test func fightingQuadrupleVsIceRock() {
        // Aurorus / Regice etc.: Fighting → Ice = 2, Fighting → Rock = 2.
        let eff = computeTypeEffectiveness(moveType: "Fighting", defenderTypes: ["Ice", "Rock"])
        #expect(eff == 4.0)
    }

    @Test func neutralWhenUnlistedDefenderType() {
        // Sanity: any (move, defender) pair not in the chart row should be neutral.
        let eff = computeTypeEffectiveness(moveType: "Normal", defenderTypes: ["Water"])
        #expect(eff == 1.0)
    }

    // MARK: - Defensive matchups for Fire-type

    /// Fire-type defenders resist: Fire, Grass, Ice, Bug, Steel, Fairy. Asserting the
    /// whole set guards against any one of them silently going missing.
    @Test func fireDefenderResists() {
        let resistedMoveTypes = ["Fire", "Grass", "Ice", "Bug", "Steel", "Fairy"]
        for moveType in resistedMoveTypes {
            let eff = computeTypeEffectiveness(moveType: moveType, defenderTypes: ["Fire"])
            #expect(eff == 0.5, "\(moveType) → Fire should be 0.5x, got \(eff)")
        }
    }

    /// Fire-type defenders are weak to: Water, Ground, Rock.
    @Test func fireDefenderWeaknesses() {
        for moveType in ["Water", "Ground", "Rock"] {
            let eff = computeTypeEffectiveness(moveType: moveType, defenderTypes: ["Fire"])
            #expect(eff == 2.0, "\(moveType) → Fire should be 2x, got \(eff)")
        }
    }
}
