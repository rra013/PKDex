//
//  SpeedTierTests.swift
//  PKDexTests
//

import Testing
@testable import PKDex

@Suite("Speed Tier Calculations")
struct SpeedTierTests {

    // MARK: - computeBenchmarkSpeed

    // Garchomp: base speed 102, Lv50
    // Max+ (252 EV, 31 IV, +Spe nature):
    //   raw = ((2*102 + 31 + 252/4) * 50/100 + 5) * 1.1
    //       = ((204 + 31 + 63) * 50/100 + 5) * 1.1
    //       = (298 * 50/100 + 5) * 1.1
    //       = (149 + 5) * 1.1 = 154 * 1.1 = 169.4 -> 169
    @Test func garchompMaxBoosted() {
        let speed = computeBenchmarkSpeed(
            baseSpeed: 102, level: 50,
            benchmark: .maxBoosted, championsMode: false,
            itemMod: .none, abilityMod: .none
        )
        #expect(speed == 169)
    }

    // Max neutral (252 EV, 31 IV, 1.0 nature):
    //   raw = (298 * 50/100 + 5) * 1.0 = 154
    @Test func garchompMaxNeutral() {
        let speed = computeBenchmarkSpeed(
            baseSpeed: 102, level: 50,
            benchmark: .maxNeutral, championsMode: false,
            itemMod: .none, abilityMod: .none
        )
        #expect(speed == 154)
    }

    // Uninvested+ (0 EV, 31 IV, +Spe):
    //   raw = ((204 + 31 + 0) * 50/100 + 5) * 1.1
    //       = (235 * 50/100 + 5) * 1.1
    //       = (117 + 5) * 1.1 = 122 * 1.1 = 134.2 -> 134
    @Test func garchompUninvestedBoosted() {
        let speed = computeBenchmarkSpeed(
            baseSpeed: 102, level: 50,
            benchmark: .uninvBoosted, championsMode: false,
            itemMod: .none, abilityMod: .none
        )
        #expect(speed == 134)
    }

    // Uninvested neutral (0 EV, 31 IV, 1.0):
    //   raw = (235 * 50/100 + 5) * 1.0 = 122
    @Test func garchompUninvestedNeutral() {
        let speed = computeBenchmarkSpeed(
            baseSpeed: 102, level: 50,
            benchmark: .uninvNeutral, championsMode: false,
            itemMod: .none, abilityMod: .none
        )
        #expect(speed == 122)
    }

    // Min (0 EV, 0 IV, -Spe):
    //   raw = ((204 + 0 + 0) * 50/100 + 5) * 0.9
    //       = (102 + 5) * 0.9 = 107 * 0.9 = 96.3 -> 96
    @Test func garchompMinHindered() {
        let speed = computeBenchmarkSpeed(
            baseSpeed: 102, level: 50,
            benchmark: .minHindered, championsMode: false,
            itemMod: .none, abilityMod: .none
        )
        #expect(speed == 96)
    }

    // MARK: - Item Modifiers

    // Max+ Garchomp with Choice Scarf: 169 * 1.5 = 253.5 -> 253
    @Test func choiceScarfMultiplier() {
        let speed = computeBenchmarkSpeed(
            baseSpeed: 102, level: 50,
            benchmark: .maxBoosted, championsMode: false,
            itemMod: .choiceScarf, abilityMod: .none
        )
        #expect(speed == 253)
    }

    // Max+ Garchomp with Iron Ball: 169 * 0.5 = 84.5 -> 84
    @Test func ironBallMultiplier() {
        let speed = computeBenchmarkSpeed(
            baseSpeed: 102, level: 50,
            benchmark: .maxBoosted, championsMode: false,
            itemMod: .ironBall, abilityMod: .none
        )
        #expect(speed == 84)
    }

    // MARK: - Ability / Status Modifiers

    // Max neutral Garchomp with Swift Swim: 154 * 2.0 = 308
    @Test func swiftSwimDoubles() {
        let speed = computeBenchmarkSpeed(
            baseSpeed: 102, level: 50,
            benchmark: .maxNeutral, championsMode: false,
            itemMod: .none, abilityMod: .swiftSwim
        )
        #expect(speed == 308)
    }

    // Max neutral Garchomp with Quick Feet: 154 * 1.5 = 231
    @Test func quickFeetBoost() {
        let speed = computeBenchmarkSpeed(
            baseSpeed: 102, level: 50,
            benchmark: .maxNeutral, championsMode: false,
            itemMod: .none, abilityMod: .quickFeet
        )
        #expect(speed == 231)
    }

    // Max neutral Garchomp paralyzed: 154 * 0.25 = 38.5 -> 38
    @Test func paralysisQuartersSpeed() {
        let speed = computeBenchmarkSpeed(
            baseSpeed: 102, level: 50,
            benchmark: .maxNeutral, championsMode: false,
            itemMod: .none, abilityMod: .paralysis
        )
        #expect(speed == 38)
    }

    // MARK: - Combined Modifiers

    // Scarf + Swift Swim: 154 * 1.5 * 2.0 = 462
    @Test func scarfPlusSwiftSwim() {
        let speed = computeBenchmarkSpeed(
            baseSpeed: 102, level: 50,
            benchmark: .maxNeutral, championsMode: false,
            itemMod: .choiceScarf, abilityMod: .swiftSwim
        )
        #expect(speed == 462)
    }

    // MARK: - Champions Mode

    // Champions max+: EV 32 -> championsEVToMain(32) = 252, same as regular max+
    @Test func championsModeMaxBoosted() {
        let speed = computeBenchmarkSpeed(
            baseSpeed: 102, level: 50,
            benchmark: .maxBoosted, championsMode: true,
            itemMod: .none, abilityMod: .none
        )
        #expect(speed == 169)
    }

    // Champions uninvested: EV 0, same as regular uninvested
    @Test func championsModeUninvested() {
        let speed = computeBenchmarkSpeed(
            baseSpeed: 102, level: 50,
            benchmark: .uninvNeutral, championsMode: true,
            itemMod: .none, abilityMod: .none
        )
        #expect(speed == 122)
    }

    // MARK: - Level 100

    // Garchomp Max+ at Lv100:
    //   raw = ((204 + 31 + 63) * 100/100 + 5) * 1.1
    //       = (298 + 5) * 1.1 = 303 * 1.1 = 333.3 -> 333
    @Test func level100MaxBoosted() {
        let speed = computeBenchmarkSpeed(
            baseSpeed: 102, level: 100,
            benchmark: .maxBoosted, championsMode: false,
            itemMod: .none, abilityMod: .none
        )
        #expect(speed == 333)
    }

    // MARK: - Edge Cases

    // Shuckle (base 5): Max+
    //   raw = ((10 + 31 + 63) * 50/100 + 5) * 1.1
    //       = (104 * 50/100 + 5) * 1.1
    //       = (52 + 5) * 1.1 = 57 * 1.1 = 62.7 -> 62
    @Test func shuckleMinBaseSpeed() {
        let speed = computeBenchmarkSpeed(
            baseSpeed: 5, level: 50,
            benchmark: .maxBoosted, championsMode: false,
            itemMod: .none, abilityMod: .none
        )
        #expect(speed == 62)
    }

    // Regieleki (base 200): Max+
    //   raw = ((400 + 31 + 63) * 50/100 + 5) * 1.1
    //       = (494 * 50/100 + 5) * 1.1
    //       = (247 + 5) * 1.1 = 252 * 1.1 = 277.2 -> 277
    @Test func regielekiHighBaseSpeed() {
        let speed = computeBenchmarkSpeed(
            baseSpeed: 200, level: 50,
            benchmark: .maxBoosted, championsMode: false,
            itemMod: .none, abilityMod: .none
        )
        #expect(speed == 277)
    }
}
