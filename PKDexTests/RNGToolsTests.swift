//
//  RNGToolsTests.swift
//  PKDexTests
//
//  Tests for EonTimer port and PokeFinder port
//

import Testing
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
        // Only accept nature 14 (Jolly) — advance 0 has nature 14
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
        let skippedResults = staticGenerateGen3(
            seed: 0, initialAdvance: 2, maxAdvance: 5,
            natures: Set<UInt8>(), tid: 12345, sid: 54321,
            shinyOnly: false, method: .method1
        )
        // Skipped should match tail of all
        #expect(skippedResults.count == allResults.count - 2)
        #expect(skippedResults[0].pid == allResults[2].pid)
    }
}

// MARK: - PokeFinder: Gen 3 Searcher Tests

struct FinderGen3SearcherTests {
    @Test func search6IV_findsResults() {
        let results = staticSearchGen3(
            minIVs: (31, 31, 31, 31, 31, 31),
            maxIVs: (31, 31, 31, 31, 31, 31),
            natures: Set<UInt8>(), tid: 12345, sid: 54321,
            shinyOnly: false, method: .method1
        )
        #expect(results.count == 6)
        // All results should have perfect IVs
        #expect(results.allSatisfy {
            $0.ivHP == 31 && $0.ivAtk == 31 && $0.ivDef == 31 &&
            $0.ivSpA == 31 && $0.ivSpD == 31 && $0.ivSpe == 31
        })
    }

    @Test func search6IV_knownSeed() {
        let results = staticSearchGen3(
            minIVs: (31, 31, 31, 31, 31, 31),
            maxIVs: (31, 31, 31, 31, 31, 31),
            natures: Set<UInt8>(), tid: 12345, sid: 54321,
            shinyOnly: false, method: .method1
        )
        // First result should have seed 0x00005433, advances 37294
        let first = results[0]
        #expect(first.seed == 0x00005433)
        #expect(first.advances == 37294)
    }

    @Test func searchWithNatureFilter_restrictsResults() {
        let all = staticSearchGen3(
            minIVs: (31, 31, 31, 31, 31, 31),
            maxIVs: (31, 31, 31, 31, 31, 31),
            natures: Set<UInt8>(), tid: 12345, sid: 54321,
            shinyOnly: false, method: .method1
        )
        // Filter to nature 15 (Modest) which matches 0x00005433 result
        let filtered = staticSearchGen3(
            minIVs: (31, 31, 31, 31, 31, 31),
            maxIVs: (31, 31, 31, 31, 31, 31),
            natures: Set<UInt8>([15]), tid: 12345, sid: 54321,
            shinyOnly: false, method: .method1
        )
        #expect(filtered.count <= all.count)
        #expect(filtered.allSatisfy { $0.nature == 15 })
    }
}

// MARK: - PokeFinder: Seed to Time Gen 3 Tests

struct SeedToTimeGen3Tests {
    @Test func simpleSeed_findsValidTimes() {
        let result = seedToTimeGen3(seed: 0x00000005)
        #expect(result.originSeed == 0x0005)
        #expect(result.advances == 0)
        #expect(result.times.count == 13)
    }

    @Test func firstTime_isDay0Hour0Minute5() {
        let result = seedToTimeGen3(seed: 0x00000005)
        let first = result.times[0]
        #expect(first.day == 0)
        #expect(first.hour == 0)
        #expect(first.minute == 5)
    }

    @Test func largeSeed_reverseWalksFirst() {
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

    @Test func invalidHour_returnsEmpty() {
        // cd = 0xFF = 255, hour >= 24 -> no results
        let results = seedToTimeGen4(seed: 0x00FF0000)
        #expect(results.isEmpty)
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

    @Test func methodJ_producesResults() {
        let results = staticGenerateGen4(
            seed: 0x05100320, initialAdvance: 0, maxAdvance: 100,
            natures: Set<UInt8>(), tid: 12345, sid: 54321,
            shinyOnly: false, method: .methodJ, lead: .none
        )
        #expect(!results.isEmpty)
        // All results should have Method J
        #expect(results.allSatisfy { $0.method == .methodJ })
    }

    @Test func methodK_producesResults() {
        let results = staticGenerateGen4(
            seed: 0x05100320, initialAdvance: 0, maxAdvance: 100,
            natures: Set<UInt8>(), tid: 12345, sid: 54321,
            shinyOnly: false, method: .methodK, lead: .none
        )
        #expect(!results.isEmpty)
        #expect(results.allSatisfy { $0.method == .methodK })
    }
}

// MARK: - PokeFinder: Gen 4 Searcher Tests

struct FinderGen4SearcherTests {
    @Test func search6IV_findsResults() {
        let results = staticSearchGen4(
            minIVs: (31, 31, 31, 31, 31, 31),
            maxIVs: (31, 31, 31, 31, 31, 31),
            natures: Set<UInt8>(), tid: 12345, sid: 54321,
            shinyOnly: false, method: .method1,
            minDelay: 0, maxDelay: 10000
        )
        #expect(!results.isEmpty)
        #expect(results.allSatisfy {
            $0.ivHP == 31 && $0.ivAtk == 31 && $0.ivDef == 31 &&
            $0.ivSpA == 31 && $0.ivSpD == 31 && $0.ivSpe == 31
        })
    }

    @Test func delayFilter_restrictsResults() {
        let wide = staticSearchGen4(
            minIVs: (31, 31, 31, 31, 31, 31),
            maxIVs: (31, 31, 31, 31, 31, 31),
            natures: Set<UInt8>(), tid: 12345, sid: 54321,
            shinyOnly: false, method: .method1,
            minDelay: 0, maxDelay: 65535
        )
        let narrow = staticSearchGen4(
            minIVs: (31, 31, 31, 31, 31, 31),
            maxIVs: (31, 31, 31, 31, 31, 31),
            natures: Set<UInt8>(), tid: 12345, sid: 54321,
            shinyOnly: false, method: .method1,
            minDelay: 0, maxDelay: 1000
        )
        #expect(narrow.count <= wide.count)
    }
}

// MARK: - PokeFinder: Seed Verification Tests

struct SeedVerificationTests {
    @Test func verifySeed_knownResult() {
        // Use a known Gen 3 result and verify against its seed
        let gen3Results = staticSearchGen3(
            minIVs: (31, 31, 31, 31, 31, 31),
            maxIVs: (31, 31, 31, 31, 31, 31),
            natures: Set<UInt8>(), tid: 12345, sid: 54321,
            shinyOnly: false, method: .method1
        )
        guard let result = gen3Results.first else {
            Issue.record("No Gen 3 search results found")
            return
        }

        // Verify using the result's own IVs should find its seed
        let verification = verifySeedFromIVs(
            caughtHP: result.ivHP, caughtAtk: result.ivAtk, caughtDef: result.ivDef,
            caughtSpA: result.ivSpA, caughtSpD: result.ivSpD, caughtSpe: result.ivSpe,
            caughtNature: result.nature, tid: 12345,
            targetSeed: result.seed, method: .method1
        )
        #expect(verification != nil)
    }

    @Test func verifySeed_wrongIVs_returnsNilOrDifferentSeed() {
        // Try verifying with completely wrong IVs
        let verification = verifySeedFromIVs(
            caughtHP: 0, caughtAtk: 0, caughtDef: 0,
            caughtSpA: 0, caughtSpD: 0, caughtSpe: 0,
            caughtNature: 0, tid: 12345,
            targetSeed: 0x12345678, method: .method1
        )
        // Should either return nil or return a different seed
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
