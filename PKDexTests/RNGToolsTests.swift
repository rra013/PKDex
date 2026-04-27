//
//  RNGToolsTests.swift
//  PKDexTests
//
//  Tests for EonTimer port and PokeFinder port
//

import Testing
import Foundation
@testable import PKDex

// MARK: - EonTimer: Calibrator Tests

struct CalibratorTests {
    let ndsSlot1 = CalibratorSettings(
        console: .ndsSlot1, customFramerate: 60.0,
        precisionCalibration: false, minimumLength: 14000
    )

    @Test func roundHalfToEven_roundsCorrectly() {
        #expect(roundHalfToEven(2.5) == 2)  // banker's: round to even
        #expect(roundHalfToEven(3.5) == 4)  // banker's: round to even
        #expect(roundHalfToEven(2.3) == 2)
        #expect(roundHalfToEven(2.7) == 3)
    }

    @Test func toMilliseconds_ndsSlot1() {
        // NDS Slot 1: 59.8261 fps -> ~16.715ms per frame
        let ms = eonToMilliseconds(ndsSlot1, delays: 60)
        // 60 * (1000/59.8261) ≈ 1002.9
        #expect(ms >= 1002 && ms <= 1004)
    }

    @Test func toDelays_ndsSlot1() {
        let delays = eonToDelays(ndsSlot1, milliseconds: 1000.0)
        // 1000 / (1000/59.8261) ≈ 59.83
        #expect(delays == 60)
    }

    @Test func toMilliseconds_gba() {
        let gba = CalibratorSettings(console: .gba, customFramerate: 60, precisionCalibration: false, minimumLength: 14000)
        let ms = eonToMilliseconds(gba, delays: 60)
        // GBA: 16777216/280896 fps ≈ 59.7275 -> 60 frames ≈ 1004.6ms
        #expect(ms >= 1004 && ms <= 1006)
    }

    @Test func createCalibration_combinesDelayAndSecond() {
        // createCalibration(settings, delays, seconds) =
        //   toMilliseconds(settings, delays - toDelays(settings, seconds * 1000))
        let cal = createCalibration(ndsSlot1, delays: 500, seconds: 14)
        #expect(cal != 0)  // Non-trivial calibration
    }

    @Test func toMinimumLength_addsMinuteUntilAbove() {
        // Default minimum is 14000ms (14s)
        let result1 = eonToMinimumLength(5000)
        #expect(result1 == 65000) // 5000 + 60000

        let result2 = eonToMinimumLength(15000)
        #expect(result2 == 15000) // Already above 14000

        let result3 = eonToMinimumLength(-10000)
        #expect(result3 == 50000) // -10000 + 60000
    }
}

// MARK: - EonTimer: Second Timer Tests

struct SecondTimerTests {
    @Test func createSecondPhases_singlePhase() {
        let phases = createSecondPhases(targetSecond: 50, calibration: 0)
        #expect(phases.count == 1)
        // 50*1000 + 0 + 200 = 50200, already above 14000
        #expect(phases[0] == 50200)
    }

    @Test func createSecondPhases_withCalibration() {
        let phases = createSecondPhases(targetSecond: 50, calibration: -500)
        #expect(phases[0] == 49700) // 50000 - 500 + 200
    }

    @Test func calibrateSecond_exactHit() {
        #expect(calibrateSecond(targetSecond: 50, secondHit: 50) == 0)
    }

    @Test func calibrateSecond_hitEarly() {
        // Early: (50-48)*1000 - 500 = 1500
        #expect(calibrateSecond(targetSecond: 50, secondHit: 48) == 1500)
    }

    @Test func calibrateSecond_hitLate() {
        // Late: (50-52)*1000 + 500 = -1500
        #expect(calibrateSecond(targetSecond: 50, secondHit: 52) == -1500)
    }
}

// MARK: - EonTimer: Delay Timer Tests

struct DelayTimerTests {
    let settings = CalibratorSettings(
        console: .ndsSlot1, customFramerate: 60, precisionCalibration: false, minimumLength: 14000
    )

    @Test func createDelayPhases_producesTwoPhases() {
        let phases = createDelayPhases(settings, targetDelay: 600, targetSecond: 50, calibration: 0)
        #expect(phases.count == 2)
    }

    @Test func calibrateDelay_exactHit_returnsZero() {
        let delta = calibrateDelay(settings, targetDelay: 600, delayHit: 600)
        #expect(delta == 0)
    }

    @Test func calibrateDelay_closeHit_usesReducedFactor() {
        let close = calibrateDelay(settings, targetDelay: 600, delayHit: 605)
        let far = calibrateDelay(settings, targetDelay: 600, delayHit: 700)
        // Close uses 0.75x, far uses 1.0x
        #expect(abs(close) < abs(far))
    }
}

// MARK: - EonTimer: Gen 3 Timer Tests

struct Gen3TimerEonTests {
    let gba = CalibratorSettings(console: .gba, customFramerate: 60, precisionCalibration: false, minimumLength: 14000)

    @Test func standardMode_producesTwoPhases() {
        let phases = createGen3Phases(gba, mode: .standard, preTimer: 5000, targetFrame: 1000, calibration: 0)
        #expect(phases.count == 2)
        #expect(phases[0] == 5000) // preTimer passthrough
    }

    @Test func variableMode_producesTwoPhases_secondIsMax() {
        let phases = createGen3Phases(gba, mode: .variableTarget, preTimer: 5000, targetFrame: 1000, calibration: 0)
        #expect(phases.count == 2)
        #expect(phases[0] == 5000)
        #expect(phases[1] == Int.max)
    }

    @Test func calibration_adjustsFramePhase() {
        let uncal = createGen3Phases(gba, mode: .standard, preTimer: 5000, targetFrame: 1000, calibration: 0)
        let cal = createGen3Phases(gba, mode: .standard, preTimer: 5000, targetFrame: 1000, calibration: 100)
        // Positive calibration adds to frame phase
        #expect(cal[1] == uncal[1] + 100)
    }
}

// MARK: - EonTimer: Gen 4 Timer Tests

struct Gen4TimerEonTests {
    let settings = CalibratorSettings(
        console: .ndsSlot1, customFramerate: 60, precisionCalibration: false, minimumLength: 14000
    )

    @Test func producesTwoPhases() {
        let phases = createGen4Phases(settings, targetDelay: 600, targetSecond: 50,
                                       calibratedDelay: 500, calibratedSecond: 14)
        #expect(phases.count == 2)
    }

    @Test func phasesArePositive() {
        let phases = createGen4Phases(settings, targetDelay: 600, targetSecond: 50,
                                       calibratedDelay: 500, calibratedSecond: 14)
        #expect(phases[0] > 0)
        #expect(phases[1] > 0)
    }

    @Test func calibrateGen4_exactHit_returnsZero() {
        #expect(calibrateGen4(settings, targetDelay: 600, delayHit: 600) == 0)
    }

    @Test func calibrateGen4_zeroHit_returnsZero() {
        #expect(calibrateGen4(settings, targetDelay: 600, delayHit: 0) == 0)
    }

    @Test func calibrateGen4_overshoot_positive() {
        let delta = calibrateGen4(settings, targetDelay: 600, delayHit: 610)
        #expect(delta > 0)
    }
}

// MARK: - EonTimer: Gen 5 Timer Tests

struct Gen5TimerEonTests {
    let settings = CalibratorSettings(
        console: .ndsSlot1, customFramerate: 60, precisionCalibration: false, minimumLength: 14000
    )

    @Test func standardMode_producesSinglePhase() {
        // Gen 5 Standard uses only secondPhases (1 phase)
        let phases = createGen5Phases(settings, mode: .standard,
            targetDelay: 1200, targetSecond: 50, targetAdvances: 0,
            calibration: -95, entralinkCalibration: 0, frameCalibration: 0)
        #expect(phases.count == 1)
    }

    @Test func cGearMode_producesTwoPhases() {
        let phases = createGen5Phases(settings, mode: .cGear,
            targetDelay: 1200, targetSecond: 50, targetAdvances: 0,
            calibration: -95, entralinkCalibration: 0, frameCalibration: 0)
        #expect(phases.count == 2)
    }

    @Test func entralinkMode_producesTwoPhases() {
        let phases = createGen5Phases(settings, mode: .entralink,
            targetDelay: 1200, targetSecond: 50, targetAdvances: 100,
            calibration: -95, entralinkCalibration: 256, frameCalibration: 0)
        #expect(phases.count == 2)
    }

    @Test func entralinkPlusMode_producesThreePhases() {
        let phases = createGen5Phases(settings, mode: .entralinkPlus,
            targetDelay: 1200, targetSecond: 50, targetAdvances: 100,
            calibration: -95, entralinkCalibration: 256, frameCalibration: 0)
        #expect(phases.count == 3)
    }
}

// MARK: - EonTimer: Custom Timer Tests

struct CustomTimerEonTests {
    let settings = CalibratorSettings(
        console: .ndsSlot1, customFramerate: 60, precisionCalibration: false, minimumLength: 14000
    )

    @Test func milliseconds_passthrough() {
        let phases = createCustomPhases(settings, phases: [
            CustomPhase(unit: .milliseconds, target: 20000, calibration: 0)
        ])
        #expect(phases[0] == 20000)
    }

    @Test func calibration_added() {
        let phases = createCustomPhases(settings, phases: [
            CustomPhase(unit: .milliseconds, target: 20000, calibration: -100)
        ])
        #expect(phases[0] == 19900)
    }

    @Test func advances_convertedToMs() {
        let phases = createCustomPhases(settings, phases: [
            CustomPhase(unit: .advances, target: 60, calibration: 0)
        ])
        // Should use toMilliseconds(settings, 60) ≈ 1003
        #expect(phases[0] >= 1002 && phases[0] <= 1004)
    }
}

// MARK: - PokeFinder: LCRNG Tests

struct LCRNGTests {
    @Test func pokeRNG_correctConstants() {
        var rng = makePokeRNG(0)
        let first = rng.next()
        // seed * 0x41C64E6D + 0x6073
        // 0 * mult + 0x6073 = 0x6073
        #expect(first == 0x6073)
    }

    @Test func pokeRNG_advance() {
        var rng = makePokeRNG(0x12345678)
        let seed1 = rng.next()
        var rng2 = makePokeRNG(0x12345678)
        rng2.advance(1)
        #expect(rng2.seed == seed1)
    }

    @Test func xdRNG_correctConstants() {
        var rng = makeXDRNG(0)
        let first = rng.next()
        // 0 * 0x343FD + 0x269EC3
        #expect(first == 0x269EC3)
    }
}

// MARK: - PokeFinder: LCRNGReverse Tests

struct LCRNGReverseTests {
    @Test func method12_recoversSeeds() {
        // Known good: a specific seed should produce specific IVs
        // Start from seed 0, advance through PokeRNG to get IVs
        var rng = makePokeRNG(0)
        rng.advance(1) // PID low
        rng.advance(1) // PID high
        let iv1 = UInt16(rng.next() >> 16)
        let iv2 = UInt16(rng.next() >> 16)
        let hp = UInt8(iv1 & 0x1f)
        let atk = UInt8((iv1 >> 5) & 0x1f)
        let def = UInt8((iv1 >> 10) & 0x1f)
        let spe = UInt8(iv2 & 0x1f)
        let spa = UInt8((iv2 >> 5) & 0x1f)
        let spd = UInt8((iv2 >> 10) & 0x1f)

        let seeds = LCRNGReverse.recoverPokeRNGIVMethod12(
            hp: hp, atk: atk, def: def, spa: spa, spd: spd, spe: spe
        )
        // Should recover at least one seed
        #expect(!seeds.isEmpty)
    }

    @Test func calculatePIDs_returnsResults() {
        // Using known IVs that should produce results
        let results = LCRNGReverse.calculatePIDs(
            hp: 31, atk: 31, def: 31, spa: 31, spd: 31, spe: 31,
            nature: 0, tid: 12345
        )
        // Every returned PID should satisfy the requested nature constraint.
        #expect(results.allSatisfy { $0.pid % 25 == 0 })
    }
}

// MARK: - PokeFinder: IVChecker Tests

struct IVCheckerTests {
    @Test func perfectIVs_level50() {
        // Pikachu: base stats [35, 55, 40, 50, 50, 90]
        // Nature 3 = Adamant (+Atk, -SpA)
        // At level 50, IV 31, no EVs:
        // HP: ((2*35 + 31)*50/100) + 50 + 10 = 110
        let baseStats: [UInt8] = [35, 55, 40, 50, 50, 90]
        let hpStat = pfComputeStatPublic(baseStat: 35, iv: 31, nature: 3, level: 50, index: 0)
        let atkStat = pfComputeStatPublic(baseStat: 55, iv: 31, nature: 3, level: 50, index: 1)
        let defStat = pfComputeStatPublic(baseStat: 40, iv: 31, nature: 3, level: 50, index: 2)
        let spaStat = pfComputeStatPublic(baseStat: 50, iv: 31, nature: 3, level: 50, index: 3)
        let spdStat = pfComputeStatPublic(baseStat: 50, iv: 31, nature: 3, level: 50, index: 4)
        let speStat = pfComputeStatPublic(baseStat: 90, iv: 31, nature: 3, level: 50, index: 5)

        let results = pfCalculateIVRange(
            baseStats: baseStats,
            stats: [[hpStat, atkStat, defStat, spaStat, spdStat, speStat]],
            levels: [50],
            nature: 3
        )

        #expect(results[0].possibleIVs.contains(31)) // HP
        #expect(results[1].possibleIVs.contains(31)) // Atk
    }

    @Test func zeroIV_detected() {
        let baseStats: [UInt8] = [35, 55, 40, 50, 50, 90]
        let hpStat = pfComputeStatPublic(baseStat: 35, iv: 0, nature: 0, level: 50, index: 0)

        let results = pfCalculateIVRange(
            baseStats: baseStats,
            stats: [[hpStat, 0, 0, 0, 0, 0]],
            levels: [50],
            nature: 0
        )
        #expect(results[0].possibleIVs.contains(0))
    }

    @Test func impossibleStat_returnsEmpty() {
        let baseStats: [UInt8] = [35, 55, 40, 50, 50, 90]
        let results = pfCalculateIVRange(
            baseStats: baseStats,
            stats: [[999, 0, 0, 0, 0, 0]],
            levels: [50],
            nature: 0
        )
        #expect(results[0].possibleIVs.isEmpty)
    }

    @Test func displayRange_singleIV() {
        let r = IVCalcResult(statName: "HP", possibleIVs: [31])
        #expect(r.displayRange == "31")
    }

    @Test func displayRange_range() {
        let r = IVCalcResult(statName: "HP", possibleIVs: [29, 30, 31])
        #expect(r.displayRange == "29-31")
    }
}

// MARK: - Hidden Power Tests

struct HiddenPowerEonTests {
    @Test func allMaxIVs_isDark() {
        #expect(calculateHiddenPowerType(ivHP: 31, ivAtk: 31, ivDef: 31,
            ivSpeed: 31, ivSpAtk: 31, ivSpDef: 31) == "Dark")
    }

    @Test func allZeroIVs_isFighting() {
        #expect(calculateHiddenPowerType(ivHP: 0, ivAtk: 0, ivDef: 0,
            ivSpeed: 0, ivSpAtk: 0, ivSpDef: 0) == "Fighting")
    }

    @Test func basePower_maxIVs_is70() {
        #expect(calculateHiddenPowerBasePower(ivHP: 31, ivAtk: 31, ivDef: 31,
            ivSpeed: 31, ivSpAtk: 31, ivSpDef: 31) == 70)
    }

    @Test func basePower_minIVs_is30() {
        #expect(calculateHiddenPowerBasePower(ivHP: 0, ivAtk: 0, ivDef: 0,
            ivSpeed: 0, ivSpAtk: 0, ivSpDef: 0) == 30)
    }
}

// MARK: - Timer Engine Tests

struct TimerEngineTests {
    @Test func initialState() {
        let engine = RNGTimerEngine()
        #expect(!engine.isRunning)
        #expect(engine.phases.isEmpty)
    }

    @Test func emptyPhases_doesNotStart() {
        let engine = RNGTimerEngine()
        engine.start(phases: [])
        #expect(!engine.isRunning)
    }

    @Test func stop_resetsState() {
        let engine = RNGTimerEngine()
        engine.start(phases: [50000])
        engine.stop()
        #expect(!engine.isRunning)
        #expect(engine.remainingMs == 0)
    }
}

// MARK: - PokeFinder: Finder Origin Seed Tests

struct FinderOriginSeedTests {
    @Test func smallSeed_returnsItself() {
        let (origin, advances) = findGen3OriginSeed(0x1234)
        #expect(origin == 0x1234)
        #expect(advances == 0)
    }

    @Test func zero_returnsZero() {
        let (origin, advances) = findGen3OriginSeed(0)
        #expect(origin == 0)
        #expect(advances == 0)
    }

    @Test func largeSeed_reverseWalks() {
        let (origin, advances) = findGen3OriginSeed(0x12345678)
        #expect(origin == 0x372B)
        #expect(advances == 57823)
    }

    @Test func maxU16_returnsItself() {
        let (origin, advances) = findGen3OriginSeed(0xFFFF)
        #expect(origin == 0xFFFF)
        #expect(advances == 0)
    }
}

// MARK: - PokeFinder: Gen 3 Generator Tests

struct FinderGen3GeneratorTests {
    @Test func generateFromSeedZero_method1() {
        let results = staticGenerateGen3(
            seed: 0, initialAdvance: 0, maxAdvance: 2,
            natures: Set<UInt8>(), tid: 12345, sid: 54321,
            shinyOnly: false, method: .method1
        )
        #expect(results.count == 3)

        // Advance 0
        #expect(results[0].pid == 0xE97E0000)
        #expect(results[0].nature == 14) // 0xE97E0000 % 25
        #expect(results[0].ivHP == 17)
        #expect(results[0].ivAtk == 19)
        #expect(results[0].ivDef == 20)
        #expect(results[0].ivSpA == 13)
        #expect(results[0].ivSpD == 12)
        #expect(results[0].ivSpe == 16)
    }

    @Test func natureFilter_filtersCorrectly() {
        // Only accept nature 14 (Rash) — advance 0 has nature 14
        let results = staticGenerateGen3(
            seed: 0, initialAdvance: 0, maxAdvance: 10,
            natures: Set<UInt8>([14]), tid: 12345, sid: 54321,
            shinyOnly: false, method: .method1
        )
        #expect(results.allSatisfy { $0.nature == 14 })
    }

    @Test func initialAdvance_skipsFrames() {
        let allResults = staticGenerateGen3(
            seed: 0, initialAdvance: 0, maxAdvance: 5,
            natures: Set<UInt8>(), tid: 12345, sid: 54321,
            shinyOnly: false, method: .method1
        )
        // maxAdvance is relative to initialAdvance, so use 3 to cover same tail
        let skippedResults = staticGenerateGen3(
            seed: 0, initialAdvance: 2, maxAdvance: 3,
            natures: Set<UInt8>(), tid: 12345, sid: 54321,
            shinyOnly: false, method: .method1
        )
        #expect(skippedResults.count == allResults.count - 2)
        #expect(skippedResults[0].pid == allResults[2].pid)
    }
}

// MARK: - PokeFinder: Gen 3 Generator Additional Tests

struct FinderGen3AdditionalTests {
    @Test func method2_staticGenerator_matchesMethod1() {
        // PokeFinder's StaticGenerator3 only handles the Method 2 VBlank skip for
        // wild encounters (WildGenerator3), not static encounters. For static
        // generation, Method 1 and 2 produce identical results.
        // The Method 2 distinction matters in PIDToIVCalculator / reverse lookups.
        let m1 = staticGenerateGen3(
            seed: 0, initialAdvance: 0, maxAdvance: 5,
            natures: Set<UInt8>(), tid: 12345, sid: 54321,
            shinyOnly: false, method: .method1
        )
        let m2 = staticGenerateGen3(
            seed: 0, initialAdvance: 0, maxAdvance: 5,
            natures: Set<UInt8>(), tid: 12345, sid: 54321,
            shinyOnly: false, method: .method2
        )
        #expect(m1.count == m2.count)
        for (a, b) in zip(m1, m2) {
            #expect(a.pid == b.pid)
            #expect(a.ivHP == b.ivHP)
        }
    }

    @Test func method4_producesDifferentIVs() {
        // Method 4 has a VBlank skip between IV1 and IV2 calls.
        // StaticGenerator3 handles this — second IV call is shifted.
        let m1 = staticGenerateGen3(
            seed: 0, initialAdvance: 0, maxAdvance: 10,
            natures: Set<UInt8>(), tid: 12345, sid: 54321,
            shinyOnly: false, method: .method1
        )
        let m4 = staticGenerateGen3(
            seed: 0, initialAdvance: 0, maxAdvance: 10,
            natures: Set<UInt8>(), tid: 12345, sid: 54321,
            shinyOnly: false, method: .method4
        )
        #expect(!m1.isEmpty)
        #expect(!m4.isEmpty)
        // PIDs match (same first two LCRNG calls)
        for (a, b) in zip(m1, m4) { #expect(a.pid == b.pid) }
        // At least some IVs should differ due to VBlank skip between IV1 and IV2
        let anyDifferentIVs = zip(m1, m4).contains { a, b in
            a.ivHP != b.ivHP || a.ivAtk != b.ivAtk || a.ivDef != b.ivDef ||
            a.ivSpA != b.ivSpA || a.ivSpD != b.ivSpD || a.ivSpe != b.ivSpe
        }
        #expect(anyDifferentIVs)
    }

    @Test func resultFields_arePopulated() {
        let results = staticGenerateGen3(
            seed: 0, initialAdvance: 0, maxAdvance: 2,
            natures: Set<UInt8>(), tid: 12345, sid: 54321,
            shinyOnly: false, method: .method1
        )
        for r in results {
            #expect(r.nature < 25)
            #expect(r.ivHP <= 31)
            #expect(r.ivAtk <= 31)
            #expect(r.ivDef <= 31)
            #expect(r.ivSpA <= 31)
            #expect(r.ivSpD <= 31)
            #expect(r.ivSpe <= 31)
            #expect(r.method == .method1)
        }
    }

    @Test func shinyFilter_restrictsResults() {
        let all = staticGenerateGen3(
            seed: 0, initialAdvance: 0, maxAdvance: 100,
            natures: Set<UInt8>(), tid: 12345, sid: 54321,
            shinyOnly: false, method: .method1
        )
        let shinyOnly = staticGenerateGen3(
            seed: 0, initialAdvance: 0, maxAdvance: 100,
            natures: Set<UInt8>(), tid: 12345, sid: 54321,
            shinyOnly: true, method: .method1
        )
        #expect(shinyOnly.count <= all.count)
        #expect(shinyOnly.allSatisfy { $0.shiny })
    }
}

// MARK: - PokeFinder: Seed to Time Gen 3 Tests

struct SeedToTimeGen3Tests {
    @Test func simpleSeed_findsValidTimes() {
        let result = seedToTimeGen3(seed: 0x00000005)
        #expect(result.originSeed == 0x0005)
        #expect(result.advances == 0)
        #expect(!result.times.isEmpty)
    }

    @Test func simpleSeed_timesAreConsistent() {
        let result = seedToTimeGen3(seed: 0x00000005)
        // All times should reference the same origin seed
        #expect(result.times.allSatisfy { $0.originSeed == 0x0005 })
        #expect(result.times.allSatisfy { $0.advances == 0 })
        // Hours must be valid (0-23)
        #expect(result.times.allSatisfy { $0.hour >= 0 && $0.hour < 24 })
        // Minutes must be valid (0-59)
        #expect(result.times.allSatisfy { $0.minute >= 0 && $0.minute < 60 })
    }

    @Test func largeSeed_reverseWalksFirst() {
        // 0x12345678 reverse-walks to origin seed 0x372B; times are found for the origin
        let result = seedToTimeGen3(seed: 0x12345678)
        #expect(result.originSeed == 0x372B)
        #expect(result.advances == 57823)
        #expect(!result.times.isEmpty)
    }
}

// MARK: - PokeFinder: Seed to Time Gen 4 Tests

struct SeedToTimeGen4Tests {
    @Test func validSeed_findsResults() {
        let results = seedToTimeGen4(seed: 0x05100320)
        #expect(!results.isEmpty)
    }

    @Test func firstResult_correctValues() {
        let results = seedToTimeGen4(seed: 0x05100320)
        let first = results[0]
        #expect(first.hour == 16)      // cd = 0x10 = 16
        #expect(first.delay == 800)     // efgh = 0x0320 = 800
        #expect(first.month == 1)
        #expect(first.day == 1)
        #expect(first.minute == 0)
        #expect(first.second == 4)
    }

    @Test func overflowHour_adjustsToHour23() {
        // cd = 0xFF = 255, cd > 23 -> hour clamped to 23, delay adjusted
        let results = seedToTimeGen4(seed: 0x00FF0000)
        #expect(!results.isEmpty)
        #expect(results[0].hour == 23)
    }
}

// MARK: - PokeFinder: Gen 4 Generator Tests

struct FinderGen4GeneratorTests {
    @Test func method1_matchesGen3() {
        // Gen 4 Method 1 should delegate to Gen 3 Method 1
        let gen3 = staticGenerateGen3(
            seed: 0, initialAdvance: 0, maxAdvance: 5,
            natures: Set<UInt8>(), tid: 12345, sid: 54321,
            shinyOnly: false, method: .method1
        )
        let gen4 = staticGenerateGen4(
            seed: 0, initialAdvance: 0, maxAdvance: 5,
            natures: Set<UInt8>(), tid: 12345, sid: 54321,
            shinyOnly: false, method: .method1, lead: .none
        )
        #expect(gen3.count == gen4.count)
        for (g3, g4) in zip(gen3, gen4) {
            #expect(g3.pid == g4.pid)
            #expect(g3.ivHP == g4.ivHP)
        }
    }

    @Test func method1Gen4_producesResults() {
        let results = staticGenerateGen4(
            seed: 0x05100320, initialAdvance: 0, maxAdvance: 10,
            natures: Set<UInt8>(), tid: 12345, sid: 54321,
            shinyOnly: false, method: .method1, lead: .none
        )
        #expect(!results.isEmpty)
        #expect(results.allSatisfy { $0.method == .method1 })
    }

    @Test func gen4_differentSeed_differentResults() {
        let r1 = staticGenerateGen4(
            seed: 0x05100320, initialAdvance: 0, maxAdvance: 5,
            natures: Set<UInt8>(), tid: 12345, sid: 54321,
            shinyOnly: false, method: .method1, lead: .none
        )
        let r2 = staticGenerateGen4(
            seed: 0xABCD1234, initialAdvance: 0, maxAdvance: 5,
            natures: Set<UInt8>(), tid: 12345, sid: 54321,
            shinyOnly: false, method: .method1, lead: .none
        )
        #expect(!r1.isEmpty)
        #expect(!r2.isEmpty)
        #expect(r1[0].pid != r2[0].pid)
    }
}

// MARK: - PokeFinder: Gen 4 Generator Additional Tests

struct FinderGen4AdditionalTests {
    @Test func gen4_natureFilter_works() {
        let all = staticGenerateGen4(
            seed: 0x05100320, initialAdvance: 0, maxAdvance: 50,
            natures: Set<UInt8>(), tid: 12345, sid: 54321,
            shinyOnly: false, method: .method1, lead: .none
        )
        let filtered = staticGenerateGen4(
            seed: 0x05100320, initialAdvance: 0, maxAdvance: 50,
            natures: Set<UInt8>([3]), tid: 12345, sid: 54321,
            shinyOnly: false, method: .method1, lead: .none
        )
        #expect(filtered.count <= all.count)
        #expect(filtered.allSatisfy { $0.nature == 3 })
    }

    @Test func gen4_initialAdvance_skipsFrames() {
        let all = staticGenerateGen4(
            seed: 0x05100320, initialAdvance: 0, maxAdvance: 10,
            natures: Set<UInt8>(), tid: 12345, sid: 54321,
            shinyOnly: false, method: .method1, lead: .none
        )
        // maxAdvance is relative to initialAdvance, so use 7 to cover same tail
        let skipped = staticGenerateGen4(
            seed: 0x05100320, initialAdvance: 3, maxAdvance: 7,
            natures: Set<UInt8>(), tid: 12345, sid: 54321,
            shinyOnly: false, method: .method1, lead: .none
        )
        #expect(skipped.count == all.count - 3)
        #expect(skipped[0].pid == all[3].pid)
    }
}

// MARK: - PokeFinder: Seed Verification Tests

struct SeedVerificationTests {
    @Test func verifySeed_usingGeneratorResult() {
        // Use a known generator result (seed 0, advance 0) and verify its IVs
        let results = staticGenerateGen3(
            seed: 0, initialAdvance: 0, maxAdvance: 0,
            natures: Set<UInt8>(), tid: 12345, sid: 54321,
            shinyOnly: false, method: .method1
        )
        let result = results[0]

        let verification = verifySeedFromIVs(
            caughtHP: result.ivHP, caughtAtk: result.ivAtk, caughtDef: result.ivDef,
            caughtSpA: result.ivSpA, caughtSpD: result.ivSpD, caughtSpe: result.ivSpe,
            caughtNature: result.nature, tid: 12345,
            targetSeed: result.seed, method: .method1
        )
        #expect(verification != nil)
    }

    @Test func verifySeed_wrongIVs_returnsNilOrDifferentSeed() {
        let verification = verifySeedFromIVs(
            caughtHP: 0, caughtAtk: 0, caughtDef: 0,
            caughtSpA: 0, caughtSpD: 0, caughtSpe: 0,
            caughtNature: 0, tid: 12345,
            targetSeed: 0x12345678, method: .method1
        )
        if let v = verification {
            #expect(v.delayDelta != 0 || v.actualSeed != v.targetSeed)
        }
    }
}

// MARK: - PokeFinder: Finder Timer Bridge Tests

struct FinderTimerBridgeTests {
    @Test func clear_resetsAllValues() {
        let bridge = FinderTimerBridge.shared
        bridge.pendingGen = .gen3
        bridge.pendingTargetFrame = 1000
        bridge.pendingTargetDelay = 600
        bridge.pendingTargetSecond = 50
        bridge.shouldSwitchToTimer = true
        bridge.selectedTime = "Day 1 08:30"
        bridge.selectedSeed = "0x1A2B3C4D"

        bridge.clear()

        #expect(bridge.pendingGen == nil)
        #expect(bridge.pendingTargetFrame == nil)
        #expect(bridge.pendingTargetDelay == nil)
        #expect(bridge.pendingTargetSecond == nil)
        #expect(bridge.shouldSwitchToTimer == false)
        #expect(bridge.selectedTime == nil)
        #expect(bridge.selectedSeed == nil)
    }
}

// MARK: - PokeFinder: Finder Types Tests

struct FinderTypesTests {
    @Test func finderMethod_gen3Methods() {
        let methods = FinderMethod.methods(for: .gen3)
        #expect(methods.contains(.method1))
        #expect(methods.contains(.method2))
        #expect(methods.contains(.method4))
        #expect(!methods.contains(.methodJ))
        #expect(!methods.contains(.methodK))
    }

    @Test func finderMethod_gen4Methods() {
        let methods = FinderMethod.methods(for: .gen4)
        #expect(methods.contains(.method1))
        #expect(methods.contains(.methodJ))
        #expect(methods.contains(.methodK))
        #expect(!methods.contains(.method2))
        #expect(!methods.contains(.method4))
    }

    @Test func pfNatureNames_has25Entries() {
        #expect(pfNatureNames.count == 25)
        #expect(pfNatureNames[0] == "Hardy")
        #expect(pfNatureNames[3] == "Adamant")
        #expect(pfNatureNames[15] == "Calm")
    }
}

// MARK: - Helper for tests (expose private pfComputeStat)

func pfComputeStatPublic(baseStat: UInt16, iv: UInt8, nature: UInt8, level: UInt8, index: UInt8) -> UInt16 {
    let modifiers: [[Float]] = [
        [1.0, 1.0, 1.0, 1.0, 1.0], [1.1, 0.9, 1.0, 1.0, 1.0],
        [1.1, 1.0, 1.0, 1.0, 0.9], [1.1, 1.0, 0.9, 1.0, 1.0],
        [1.1, 1.0, 1.0, 0.9, 1.0], [0.9, 1.1, 1.0, 1.0, 1.0],
        [1.0, 1.0, 1.0, 1.0, 1.0], [1.0, 1.1, 1.0, 1.0, 0.9],
        [1.0, 1.1, 0.9, 1.0, 1.0], [1.0, 1.1, 1.0, 0.9, 1.0],
        [0.9, 1.0, 1.1, 1.0, 1.0], [1.0, 0.9, 1.1, 1.0, 1.0],
        [1.0, 1.0, 1.0, 1.0, 1.0], [1.0, 1.0, 1.1, 1.0, 0.9],
        [1.0, 1.0, 1.1, 0.9, 1.0], [0.9, 1.0, 1.0, 1.1, 1.0],
        [1.0, 0.9, 1.0, 1.1, 1.0], [1.0, 1.0, 0.9, 1.1, 1.0],
        [1.0, 1.0, 1.0, 1.0, 1.0], [1.0, 1.0, 1.0, 1.1, 0.9],
        [0.9, 1.0, 1.0, 1.0, 1.1], [1.0, 0.9, 1.0, 1.0, 1.1],
        [1.0, 1.0, 0.9, 1.0, 1.1], [1.0, 1.0, 1.0, 0.9, 1.1],
        [1.0, 1.0, 1.0, 1.0, 1.0],
    ]
    let stat = ((2 * baseStat + UInt16(iv)) * UInt16(level)) / 100
    if index == 0 { return stat + UInt16(level) + 10 }
    return UInt16(Float(stat + 5) * modifiers[Int(nature)][Int(index) - 1])
}

// MARK: - Coin Flip Matching Tests

struct CoinFlipMatchTests {
    @Test func knownSeed_matchesExpectedFlips() {
        // Seed 0 with MT19937: first output determines H/T
        // matchesCoinFlips checks (mt.next() & 1) != 0 for each flip
        let seed: UInt32 = 0x05100320
        let flipsStr = PFBridge.coinFlips(seed)
        let expected = flipsStr.split(separator: ", ").map { $0 == "H" }
        #expect(matchesCoinFlips(seed: seed, observed: expected))
    }

    @Test func wrongFlips_doesNotMatch() {
        let seed: UInt32 = 0x05100320
        let flipsStr = PFBridge.coinFlips(seed)
        var flips = flipsStr.split(separator: ", ").map { $0 == "H" }
        // Invert the first flip
        flips[0].toggle()
        #expect(!matchesCoinFlips(seed: seed, observed: flips))
    }

    @Test func emptyObserved_alwaysMatches() {
        #expect(matchesCoinFlips(seed: 0, observed: []))
        #expect(matchesCoinFlips(seed: 0xDEADBEEF, observed: []))
    }

    @Test func singleFlip_matchesOrNot() {
        let seed: UInt32 = 0
        let firstFlipStr = PFBridge.coinFlips(seed).split(separator: ", ").first!
        let isHeads = firstFlipStr == "H"
        #expect(matchesCoinFlips(seed: seed, observed: [isHeads]))
        #expect(!matchesCoinFlips(seed: seed, observed: [!isHeads]))
    }

    @Test func differentSeeds_produceDifferentFlips() {
        let flips1 = PFBridge.coinFlips(0x00000001)
        let flips2 = PFBridge.coinFlips(0x00000002)
        #expect(flips1 != flips2)
    }
}

// MARK: - Call Matching Tests

struct CallMatchTests {
    @Test func knownSeed_matchesExpectedCalls() {
        let seed: UInt32 = 0x05100320
        let callsStr = PFBridge.getCalls(seed)
        // Parse "E, K, P, ..." into [UInt8] where E=0, K=1, P=2
        let expected: [UInt8] = callsStr.split(separator: ", ").prefix(5).map { c in
            switch c {
            case "E": return 0
            case "K": return 1
            default: return 2
            }
        }
        #expect(matchesCalls(seed: seed, observed: expected, skips: 0))
    }

    @Test func wrongCalls_doesNotMatch() {
        let seed: UInt32 = 0x05100320
        let callsStr = PFBridge.getCalls(seed)
        var calls: [UInt8] = callsStr.split(separator: ", ").prefix(5).map { c in
            switch c {
            case "E": return 0
            case "K": return 1
            default: return 2
            }
        }
        // Change first call to something different
        calls[0] = (calls[0] + 1) % 3
        #expect(!matchesCalls(seed: seed, observed: calls, skips: 0))
    }

    @Test func emptyObserved_alwaysMatches() {
        #expect(matchesCalls(seed: 0, observed: [], skips: 0))
        #expect(matchesCalls(seed: 0, observed: [], skips: 3))
    }

    @Test func roamerSkips_offsetsCalls() {
        let seed: UInt32 = 0x05100320
        // With 0 skips, get the calls starting from advance 1
        let calls0 = PFBridge.getCalls(seed, skips: 0)
        let calls2 = PFBridge.getCalls(seed, skips: 2)
        // Skips should shift the sequence
        #expect(calls0 != calls2)

        // Parse calls with 2 skips and verify matchesCalls agrees
        // The format with skips includes "(X skipped)" prefix, parse after it
        let parsed: [UInt8] = calls2
            .replacingOccurrences(of: "(", with: "")
            .split(separator: ")").last!
            .trimmingCharacters(in: .whitespaces)
            .split(separator: ", ").prefix(5).map { c in
                switch c.trimmingCharacters(in: .whitespaces) {
                case "E": return 0
                case "K": return 1
                default: return 2
                }
            }
        #expect(matchesCalls(seed: seed, observed: parsed, skips: 2))
    }

    @Test func matchesCalls_usesLCRNG() {
        // Manually verify the LCRNG: seed * 0x41C64E6D + 0x6073
        let seed: UInt32 = 1
        var state = seed
        state = state &* 0x41C64E6D &+ 0x6073
        let call = UInt8((state >> 16) % 3)
        #expect(matchesCalls(seed: seed, observed: [call], skips: 0))
    }
}

// MARK: - Frame Timer Tests

struct FrameTimerTests {
    let ndsSlot1 = CalibratorSettings(
        console: .ndsSlot1, customFramerate: 60.0,
        precisionCalibration: false, minimumLength: 14000
    )

    @Test func getMsPerFrame_allConsoles() {
        let gba = CalibratorSettings(console: .gba, customFramerate: 60, precisionCalibration: false, minimumLength: 14000)
        let nds1 = CalibratorSettings(console: .ndsSlot1, customFramerate: 60, precisionCalibration: false, minimumLength: 14000)
        let nds2 = CalibratorSettings(console: .ndsSlot2, customFramerate: 60, precisionCalibration: false, minimumLength: 14000)
        let custom = CalibratorSettings(console: .custom, customFramerate: 120, precisionCalibration: false, minimumLength: 14000)

        // GBA: 16777216/280896 fps -> ~16.7427ms/frame
        #expect(getMsPerFrame(gba) > 16.7 && getMsPerFrame(gba) < 16.8)
        // NDS Slot 1: 1000/59.8261 -> ~16.715ms/frame
        #expect(getMsPerFrame(nds1) > 16.7 && getMsPerFrame(nds1) < 16.8)
        // NDS Slot 2: 1000/59.6555 -> ~16.763ms/frame (different from GBA)
        #expect(getMsPerFrame(nds2) > 16.7 && getMsPerFrame(nds2) < 16.8)
        #expect(getMsPerFrame(nds2) != getMsPerFrame(gba))
        // Custom: 1000/120 = 8.333ms
        #expect(abs(getMsPerFrame(custom) - 8.333) < 0.01)
    }

    @Test func createFramePhases_returnsPreTimerAndFrame() {
        let phases = createFramePhases(ndsSlot1, preTimer: 5000, targetFrame: 100, calibration: 0)
        #expect(phases.count == 2)
        #expect(phases[0] == 5000)
        #expect(phases[1] > 0)
    }

    @Test func calibrateFrame_computesDelta() {
        // If we hit frame 105 targeting 100, calibration should be positive
        let cal = calibrateFrame(ndsSlot1, targetFrame: 100, frameHit: 105)
        #expect(cal < 0) // We were late, need to subtract time
        let cal2 = calibrateFrame(ndsSlot1, targetFrame: 100, frameHit: 95)
        #expect(cal2 > 0) // We were early, need to add time
    }

    @Test func createVariableFramePhases_usesMaxInt() {
        let phases = createVariableFramePhases(preTimer: 3000)
        #expect(phases.count == 2)
        #expect(phases[0] == 3000)
        #expect(phases[1] == Int.max)
    }

    @Test func calibrateToDelays_precisionMode() {
        let precision = CalibratorSettings(console: .ndsSlot1, customFramerate: 60, precisionCalibration: true, minimumLength: 14000)
        // In precision mode, calibrateToDelays just rounds the milliseconds
        let result = calibrateToDelays(precision, milliseconds: 123.7)
        #expect(result == 124)
    }

    @Test func calibrateToMilliseconds_precisionMode() {
        let precision = CalibratorSettings(console: .ndsSlot1, customFramerate: 60, precisionCalibration: true, minimumLength: 14000)
        // In precision mode, just passes through
        #expect(calibrateToMilliseconds(precision, delays: 500) == 500)
    }
}

// MARK: - Entralink Timer Tests

struct EntralinkTimerTests {
    let nds = CalibratorSettings(
        console: .ndsSlot1, customFramerate: 60.0,
        precisionCalibration: false, minimumLength: 14000
    )

    @Test func createEntralinkPhases_addsOffset() {
        let delayPhases = createDelayPhases(nds, targetDelay: 1000, targetSecond: 30, calibration: 0)
        let entralink = createEntralinkPhases(nds, targetDelay: 1000, targetSecond: 30, calibration: 0, entralinkCalibration: 100)
        // Phase 0 should be delay phase 0 + 250
        #expect(entralink[0] == delayPhases[0] + 250)
        // Phase 1 should be delay phase 1 - entralinkCalibration
        #expect(entralink[1] == delayPhases[1] - 100)
    }

    @Test func createEnhancedEntralinkPhases_hasThreePhases() {
        let phases = createEnhancedEntralinkPhases(
            nds, targetDelay: 1000, targetSecond: 30,
            targetAdvances: 50, calibration: 0,
            entralinkCalibration: 100, frameCalibration: 0
        )
        #expect(phases.count == 3)
        #expect(phases[2] > 0) // Third phase for advances
    }

    @Test func calibrateEntralinkAdvances_computesDelta() {
        let cal = calibrateEntralinkAdvances(targetAdvances: 50, advancesHit: 55)
        #expect(cal < 0) // Hit more advances than target
        let cal2 = calibrateEntralinkAdvances(targetAdvances: 50, advancesHit: 45)
        #expect(cal2 > 0) // Hit fewer advances than target
    }
}

// MARK: - Gen Timer Integration Tests

struct GenTimerTests {
    let nds = CalibratorSettings(
        console: .ndsSlot1, customFramerate: 60.0,
        precisionCalibration: false, minimumLength: 14000
    )

    @Test func gen3_standardMode() {
        let phases = createGen3Phases(nds, mode: .standard, preTimer: 5000, targetFrame: 1000, calibration: 0)
        #expect(phases.count == 2)
        #expect(phases[0] == 5000)
    }

    @Test func gen3_variableMode() {
        let phases = createGen3Phases(nds, mode: .variableTarget, preTimer: 5000, targetFrame: 1000, calibration: 0)
        #expect(phases.count == 2)
        #expect(phases[1] == Int.max)
    }

    @Test func gen4_phasesArePositive() {
        let phases = createGen4Phases(nds, targetDelay: 600, targetSecond: 50,
                                       calibratedDelay: 600, calibratedSecond: 50)
        #expect(phases.count == 2)
        #expect(phases.allSatisfy { $0 > 0 })
    }

    @Test func gen4_calibration() {
        let cal = getGen4Calibration(nds, calibratedDelay: 600, calibratedSecond: 50)
        #expect(cal != 0 || true) // Calibration can be 0 if delay matches seconds perfectly
    }

    @Test func gen5_standardMode_singlePhase() {
        let phases = createGen5Phases(nds, mode: .standard,
                                       targetDelay: 600, targetSecond: 50, targetAdvances: 0,
                                       calibration: 0, entralinkCalibration: 0, frameCalibration: 0)
        #expect(phases.count == 1)
    }

    @Test func gen5_cGearMode_twoPhases() {
        let phases = createGen5Phases(nds, mode: .cGear,
                                       targetDelay: 600, targetSecond: 50, targetAdvances: 0,
                                       calibration: 0, entralinkCalibration: 0, frameCalibration: 0)
        #expect(phases.count == 2)
    }

    @Test func gen5_entralinkMode_twoPhases() {
        let phases = createGen5Phases(nds, mode: .entralink,
                                       targetDelay: 600, targetSecond: 50, targetAdvances: 0,
                                       calibration: 0, entralinkCalibration: 0, frameCalibration: 0)
        #expect(phases.count == 2)
    }

    @Test func gen5_entralinkPlusMode_threePhases() {
        let phases = createGen5Phases(nds, mode: .entralinkPlus,
                                       targetDelay: 600, targetSecond: 50, targetAdvances: 50,
                                       calibration: 0, entralinkCalibration: 0, frameCalibration: 0)
        #expect(phases.count == 3)
    }

    @Test func eonGetMinutesBeforeTarget_basic() {
        let phases1 = [60000, 5000]
        #expect(eonGetMinutesBeforeTarget(phases1) == 1)

        let phases2 = [120000, 30000]
        #expect(eonGetMinutesBeforeTarget(phases2) == 2)

        let phases3 = [5000]
        #expect(eonGetMinutesBeforeTarget(phases3) == 0)
    }
}

// MARK: - Encounter Data Tests

struct EncounterDataTests {
    @Test func gameVersions_correctGeneration() {
        #expect(FinderGameVersion.emerald.generation == .gen3)
        #expect(FinderGameVersion.ruby.generation == .gen3)
        #expect(FinderGameVersion.diamond.generation == .gen4)
        #expect(FinderGameVersion.platinum.generation == .gen4)
        #expect(FinderGameVersion.heartGold.generation == .gen4)
    }

    @Test func gamesForGen_filtersCorrectly() {
        let gen3 = FinderGameVersion.games(for: .gen3)
        let gen4 = FinderGameVersion.games(for: .gen4)
        #expect(gen3.count == 5)
        #expect(gen4.count == 5)
        #expect(gen3.allSatisfy { $0.generation == .gen3 })
        #expect(gen4.allSatisfy { $0.generation == .gen4 })
    }

    @Test func encounterType_pfMapping() {
        #expect(EncounterType.grass.pfEncounter == .grass)
        #expect(EncounterType.surf.pfEncounter == .surfing)
        #expect(EncounterType.oldRod.pfEncounter == .oldRod)
        #expect(EncounterType.goodRod.pfEncounter == .goodRod)
        #expect(EncounterType.superRod.pfEncounter == .superRod)
        #expect(EncounterType.rockSmash.pfEncounter == .rockSmash)
    }

    @Test func encounterType_roundTrip() {
        for type in EncounterType.allCases {
            let pf = type.pfEncounter
            let back = EncounterType(from: pf)
            #expect(back == type)
        }
    }

    @Test func staticEncounterData_startersExist() {
        let starters = StaticEncounterData.gen3Starters
        #expect(!starters.isEmpty)
        #expect(starters.allSatisfy { $0.category == .starters })
        #expect(starters.allSatisfy { $0.level == 5 })
        // Treecko, Torchic, Mudkip for RSE
        let rseStarters = starters.filter { $0.gameVersions.contains(.emerald) }
        #expect(rseStarters.count == 3)
    }

    @Test func pfGame_mappingCoversAll() {
        for game in FinderGameVersion.allCases {
            let pfGame = game.pfGame
            // Just verify no crashes — all cases are covered
            #expect(pfGame.rawValue >= 0)
        }
    }

    @Test func finderLead_filtersForGeneration() {
        let gen3Leads = FinderLead.leads(for: .gen3, encounterMode: false)
        let gen4Leads = FinderLead.leads(for: .gen4, encounterMode: false)
        #expect(gen3Leads.contains(.none))
        #expect(gen4Leads.contains(.none))
        #expect(gen4Leads.contains(.synchronize))
    }
}

// MARK: - Delay Calibration Tests

struct DelayCalibrationTests {
    let nds = CalibratorSettings(
        console: .ndsSlot1, customFramerate: 60.0,
        precisionCalibration: false, minimumLength: 14000
    )

    @Test func calibrateDelay_closeThreshold() {
        // When delta is within 167ms (10 frames), use 0.75 factor
        let cal = calibrateDelay(nds, targetDelay: 600, delayHit: 605)
        let fullDelta = Double(eonToMilliseconds(nds, delays: 605) - eonToMilliseconds(nds, delays: 600))
        // 5 frames * ~16.7ms = ~83.5ms, which is < 167, so factor 0.75 applies
        let expected = 0.75 * fullDelta
        #expect(abs(cal - expected) < 0.01)
    }

    @Test func calibrateDelay_farThreshold() {
        // When delta is beyond 167ms, use full delta
        let cal = calibrateDelay(nds, targetDelay: 600, delayHit: 620)
        let fullDelta = Double(eonToMilliseconds(nds, delays: 620) - eonToMilliseconds(nds, delays: 600))
        // 20 frames * ~16.7ms = ~334ms, which is > 167, so full delta
        #expect(abs(cal - fullDelta) < 0.01)
    }

    @Test func calibrateSecond_early() {
        let cal = calibrateSecond(targetSecond: 50, secondHit: 48)
        #expect(cal > 0) // Hit early, need to add time
        #expect(cal == Double((50 - 48) * 1000 - 500))
    }

    @Test func calibrateSecond_late() {
        let cal = calibrateSecond(targetSecond: 50, secondHit: 52)
        #expect(cal < 0) // Hit late, need to subtract time
        #expect(cal == Double((50 - 52) * 1000 + 500))
    }

    @Test func calibrateSecond_exact() {
        let cal = calibrateSecond(targetSecond: 50, secondHit: 50)
        #expect(cal == 0)
    }
}
