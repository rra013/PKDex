//
//  RNGToolsView.swift
//  PKDex
//
//  RNG manipulation tools ported from:
//  - PokeFinder by Admiral_Fish, bumba, and EzPzStreamz
//    (https://github.com/Admiral-Fish/PokeFinder) — GPLv3
//  - EonTimer by DasAmpharos
//    (https://github.com/DasAmpharos/EonTimer) — MIT
//

import SwiftUI
import SwiftData
import AVFoundation

// ============================================================================
// MARK: - EonTimer Port: Constants (from utils/constants.ts)
// ============================================================================

/// Default minimum length in milliseconds (EonTimer default: 14 seconds)
let EONTIMER_MINIMUM_LENGTH = 14000

/// When a phase is below minimum, add 60s repeatedly (from toMinimumLength)
func eonToMinimumLength(_ value: Int, minimumLength: Int = EONTIMER_MINIMUM_LENGTH) -> Int {
    var v = value
    while v < minimumLength {
        v += 60000
    }
    return v
}

func eonGetMinutesBeforeTarget(_ phases: [Int]) -> Int {
    var total = 0
    for phase in phases {
        if phase == Int.max { continue } // INFINITY
        total += phase
    }
    return total / 60000
}

// Console framerates (from utils/constants.ts)
let GBA_FRAMERATE: Double = 16777216.0 / 280896.0
let NDS_SLOT1_FRAMERATE: Double = 59.8261
let NDS_SLOT2_FRAMERATE: Double = 59.6555

let GBA_MS_PER_FRAME: Double = 1000.0 / GBA_FRAMERATE
let NDS_SLOT1_MS_PER_FRAME: Double = 1000.0 / NDS_SLOT1_FRAMERATE
let NDS_SLOT2_MS_PER_FRAME: Double = 1000.0 / NDS_SLOT2_FRAMERATE

// ============================================================================
// MARK: - EonTimer Port: Console + Calibrator (from timers/calibrator.ts)
// ============================================================================

enum RNGConsole: String, CaseIterable, Identifiable {
    case gba = "GBA"
    case ndsSlot1 = "NDS - Slot 1"
    case ndsSlot2 = "NDS - Slot 2"
    case dsi = "DSi"
    case threeds = "3DS"
    case custom = "Custom"
    var id: String { rawValue }
}

struct CalibratorSettings {
    var console: RNGConsole
    var customFramerate: Double
    var precisionCalibration: Bool
    var minimumLength: Int // in milliseconds
}

let defaultCalibratorSettings = CalibratorSettings(
    console: .ndsSlot1,
    customFramerate: 60.0,
    precisionCalibration: false,
    minimumLength: EONTIMER_MINIMUM_LENGTH
)

/// Banker's rounding to match C# Math.Round behavior (from calibrator.ts)
func roundHalfToEven(_ value: Double) -> Int {
    guard value.isFinite else { return Int(value.rounded()) }
    let lower = floor(value)
    let upper = ceil(value)
    if lower == upper { return Int(lower) }
    let lowerDist = value - lower
    let upperDist = upper - value
    let epsilon = Double.ulpOfOne * max(1, abs(value))
    if abs(lowerDist - upperDist) <= epsilon {
        return Int(lower).isMultiple(of: 2) ? Int(lower) : Int(upper)
    }
    return lowerDist < upperDist ? Int(lower) : Int(upper)
}

func getMsPerFrame(_ settings: CalibratorSettings) -> Double {
    switch settings.console {
    case .gba: return GBA_MS_PER_FRAME
    case .ndsSlot2: return NDS_SLOT2_MS_PER_FRAME
    case .ndsSlot1, .dsi, .threeds: return NDS_SLOT1_MS_PER_FRAME
    case .custom:
        guard settings.customFramerate > 0 else { return NDS_SLOT1_MS_PER_FRAME }
        return 1000.0 / settings.customFramerate
    }
}

func eonToDelays(_ settings: CalibratorSettings, milliseconds: Double) -> Int {
    return roundHalfToEven(milliseconds / getMsPerFrame(settings))
}

func eonToMilliseconds(_ settings: CalibratorSettings, delays: Int) -> Int {
    return roundHalfToEven(getMsPerFrame(settings) * Double(delays))
}

func calibrateToDelays(_ settings: CalibratorSettings, milliseconds: Double) -> Int {
    return settings.precisionCalibration
        ? roundHalfToEven(milliseconds)
        : eonToDelays(settings, milliseconds: milliseconds)
}

func calibrateToMilliseconds(_ settings: CalibratorSettings, delays: Int) -> Int {
    return settings.precisionCalibration ? delays : eonToMilliseconds(settings, delays: delays)
}

func createCalibration(_ settings: CalibratorSettings, delays: Int, seconds: Int) -> Int {
    return eonToMilliseconds(settings, delays: delays - eonToDelays(settings, milliseconds: Double(seconds) * 1000.0))
}

// ============================================================================
// MARK: - EonTimer Port: Second Timer (from timers/secondTimer.ts)
// ============================================================================

func createSecondPhases(targetSecond: Int, calibration: Int, minimumLength: Int = EONTIMER_MINIMUM_LENGTH) -> [Int] {
    return [eonToMinimumLength(targetSecond * 1000 + calibration + 200, minimumLength: minimumLength)]
}

func calibrateSecond(targetSecond: Int, secondHit: Int) -> Double {
    if secondHit < targetSecond {
        return Double((targetSecond - secondHit) * 1000 - 500)
    } else if secondHit > targetSecond {
        return Double((targetSecond - secondHit) * 1000 + 500)
    }
    return 0
}

// ============================================================================
// MARK: - EonTimer Port: Delay Timer (from timers/delayTimer.ts)
// ============================================================================

private let CLOSE_THRESHOLD: Double = 167
private let CLOSE_UPDATE_FACTOR: Double = 0.75

func createDelayPhases(_ settings: CalibratorSettings, targetDelay: Int, targetSecond: Int, calibration: Int) -> [Int] {
    let secondPhases = createSecondPhases(targetSecond: targetSecond, calibration: calibration, minimumLength: settings.minimumLength)
    let delayMs = eonToMilliseconds(settings, delays: targetDelay)
    let phase1 = eonToMinimumLength(secondPhases[0] - delayMs, minimumLength: settings.minimumLength)
    let phase2 = delayMs - calibration
    return [phase1, phase2]
}

func calibrateDelay(_ settings: CalibratorSettings, targetDelay: Int, delayHit: Int) -> Double {
    let delta = Double(eonToMilliseconds(settings, delays: delayHit) - eonToMilliseconds(settings, delays: targetDelay))
    if abs(delta) <= CLOSE_THRESHOLD {
        return CLOSE_UPDATE_FACTOR * delta
    }
    return delta
}

// ============================================================================
// MARK: - EonTimer Port: Frame Timer (from timers/frameTimer.ts)
// ============================================================================

func createFramePhases(_ settings: CalibratorSettings, preTimer: Int, targetFrame: Int, calibration: Int) -> [Int] {
    return [preTimer, createFramePhase(settings, targetFrame: targetFrame, calibration: calibration)]
}

func createFramePhase(_ settings: CalibratorSettings, targetFrame: Int, calibration: Int) -> Int {
    return eonToMilliseconds(settings, delays: targetFrame) + calibration
}

func calibrateFrame(_ settings: CalibratorSettings, targetFrame: Int, frameHit: Int) -> Int {
    return eonToMilliseconds(settings, delays: targetFrame - frameHit)
}

func createVariableFramePhases(preTimer: Int) -> [Int] {
    return [preTimer, Int.max]
}

// ============================================================================
// MARK: - EonTimer Port: Entralink Timer (from timers/entralinkTimer.ts)
// ============================================================================

private let ENTRALINK_FRAME_RATE: Double = 0.837148929

func createEntralinkPhases(_ settings: CalibratorSettings, targetDelay: Int, targetSecond: Int,
                            calibration: Int, entralinkCalibration: Int) -> [Int] {
    var durations = createDelayPhases(settings, targetDelay: targetDelay, targetSecond: targetSecond, calibration: calibration)
    durations[0] += 250
    durations[1] -= entralinkCalibration
    return durations
}

func createEnhancedEntralinkPhases(_ settings: CalibratorSettings, targetDelay: Int, targetSecond: Int,
                                    targetAdvances: Int, calibration: Int,
                                    entralinkCalibration: Int, frameCalibration: Int) -> [Int] {
    var phases = createEntralinkPhases(settings, targetDelay: targetDelay, targetSecond: targetSecond,
                                        calibration: calibration, entralinkCalibration: entralinkCalibration)
    phases.append(Int((Double(targetAdvances) / ENTRALINK_FRAME_RATE) * 1000) + frameCalibration)
    return phases
}

func calibrateEntralinkAdvances(targetAdvances: Int, advancesHit: Int) -> Double {
    return (Double(targetAdvances - advancesHit) / ENTRALINK_FRAME_RATE) * 1000
}

// ============================================================================
// MARK: - EonTimer Port: Gen 3 Timer (from timers/gen3Timer.ts)
// ============================================================================

enum Gen3TimerMode: String, CaseIterable, Identifiable {
    case standard = "Standard"
    case variableTarget = "Variable Target"
    var id: String { rawValue }
}

func createGen3Phases(_ settings: CalibratorSettings, mode: Gen3TimerMode,
                       preTimer: Int, targetFrame: Int, calibration: Int) -> [Int] {
    switch mode {
    case .standard:
        return createFramePhases(settings, preTimer: preTimer, targetFrame: targetFrame, calibration: calibration)
    case .variableTarget:
        return createVariableFramePhases(preTimer: preTimer)
    }
}

func calibrateGen3(_ settings: CalibratorSettings, targetFrame: Int, frameHit: Int) -> Int {
    return calibrateFrame(settings, targetFrame: targetFrame, frameHit: frameHit)
}

// ============================================================================
// MARK: - EonTimer Port: Gen 4 Timer (from timers/gen4Timer.ts)
// ============================================================================

func getGen4Calibration(_ settings: CalibratorSettings, calibratedDelay: Int, calibratedSecond: Int) -> Int {
    return createCalibration(settings, delays: calibratedDelay, seconds: calibratedSecond)
}

func createGen4Phases(_ settings: CalibratorSettings, targetDelay: Int, targetSecond: Int,
                       calibratedDelay: Int, calibratedSecond: Int) -> [Int] {
    let cal = getGen4Calibration(settings, calibratedDelay: calibratedDelay, calibratedSecond: calibratedSecond)
    return createDelayPhases(settings, targetDelay: targetDelay, targetSecond: targetSecond, calibration: cal)
}

func calibrateGen4(_ settings: CalibratorSettings, targetDelay: Int, delayHit: Int) -> Int {
    guard delayHit > 0 else { return 0 }
    return eonToDelays(settings, milliseconds: calibrateDelay(settings, targetDelay: targetDelay, delayHit: delayHit))
}

// ============================================================================
// MARK: - EonTimer Port: Gen 5 Timer (from timers/gen5Timer.ts)
// ============================================================================

enum Gen5TimerMode: String, CaseIterable, Identifiable {
    case standard = "Standard"
    case cGear = "C-Gear"
    case entralink = "Entralink"
    case entralinkPlus = "Entralink+"
    var id: String { rawValue }
}

func createGen5Phases(_ settings: CalibratorSettings, mode: Gen5TimerMode,
                       targetDelay: Int, targetSecond: Int, targetAdvances: Int,
                       calibration: Int, entralinkCalibration: Int, frameCalibration: Int) -> [Int] {
    let calMs = calibrateToMilliseconds(settings, delays: calibration)
    let entCalMs = calibrateToMilliseconds(settings, delays: entralinkCalibration)

    switch mode {
    case .standard:
        return createSecondPhases(targetSecond: targetSecond, calibration: calMs, minimumLength: settings.minimumLength)
    case .cGear:
        return createDelayPhases(settings, targetDelay: targetDelay, targetSecond: targetSecond, calibration: calMs)
    case .entralink:
        return createEntralinkPhases(settings, targetDelay: targetDelay, targetSecond: targetSecond,
                                      calibration: calMs, entralinkCalibration: entCalMs)
    case .entralinkPlus:
        return createEnhancedEntralinkPhases(settings, targetDelay: targetDelay, targetSecond: targetSecond,
                                              targetAdvances: targetAdvances, calibration: calMs,
                                              entralinkCalibration: entCalMs, frameCalibration: frameCalibration)
    }
}

struct Gen5CalibrationResult {
    var calibrationDelta: Int
    var entralinkCalibrationDelta: Int
    var frameCalibrationDelta: Double
}

func calibrateGen5(_ settings: CalibratorSettings, mode: Gen5TimerMode,
                    targetDelay: Int, targetSecond: Int, targetAdvances: Int,
                    delayHit: Int?, secondHit: Int?, advancesHit: Int?) -> Gen5CalibrationResult {
    var result = Gen5CalibrationResult(calibrationDelta: 0, entralinkCalibrationDelta: 0, frameCalibrationDelta: 0)

    switch mode {
    case .standard:
        if let sh = secondHit {
            result.calibrationDelta = calibrateToDelays(settings, milliseconds: calibrateSecond(targetSecond: targetSecond, secondHit: sh))
        }
    case .cGear:
        if let dh = delayHit {
            result.calibrationDelta = calibrateToDelays(settings, milliseconds: calibrateDelay(settings, targetDelay: targetDelay, delayHit: dh))
        }
    case .entralink, .entralinkPlus:
        if let sh = secondHit, sh != targetSecond {
            result.calibrationDelta = calibrateToDelays(settings, milliseconds: calibrateSecond(targetSecond: targetSecond, secondHit: sh))
        }
        if let dh = delayHit, dh != targetDelay {
            result.entralinkCalibrationDelta = calibrateToDelays(settings,
                milliseconds: calibrateDelay(settings, targetDelay: targetDelay, delayHit: dh))
        }
        if mode == .entralinkPlus, let ah = advancesHit, ah != targetAdvances {
            result.frameCalibrationDelta = calibrateEntralinkAdvances(targetAdvances: targetAdvances, advancesHit: ah)
        }
    }

    return result
}

// ============================================================================
// MARK: - EonTimer Port: Custom Timer (from timers/customTimer.ts)
// ============================================================================

enum CustomTimerUnit: String, CaseIterable, Identifiable {
    case milliseconds = "ms"
    case advances = "Advances"
    case hex = "Seed (Hex)"
    var id: String { rawValue }
}

struct CustomPhase {
    var unit: CustomTimerUnit
    var target: Int
    var calibration: Int
}

func createCustomPhases(_ settings: CalibratorSettings, phases: [CustomPhase]) -> [Int] {
    return phases.map { phase in
        var value = phase.target
        if phase.unit == .advances || phase.unit == .hex {
            value = eonToMilliseconds(settings, delays: value)
        }
        return value + phase.calibration
    }
}

// ============================================================================
// MARK: - PokeFinder Port: LCRNG (from Core/RNG/LCRNG.hpp + LCRNG.cpp)
// ============================================================================

/// Linear Congruential RNG used in Pokemon Gen 3/4 games.
/// Ported from PokeFinder by Admiral_Fish, bumba, and EzPzStreamz (GPLv3)nonisolated .
nonisolated struct LCRNG {
    let mult: UInt32
    let add: UInt32
    var seed: UInt32

    init(mult: UInt32, add: UInt32, seed: UInt32) {
        self.mult = mult
        self.add = add
        self.seed = seed
    }

    @discardableResult
    mutating func next() -> UInt32 {
        seed = seed &* mult &+ add
        return seed
    }

    func nextUShort() -> UInt16 {
        return UInt16((seed &* mult &+ add) >> 16)
    }

    @discardableResult
    mutating func advance(_ count: Int) -> UInt32 {
        for _ in 0..<count { next() }
        return seed
    }
}

// Standard Pokemon RNG constants
nonisolated let pokeRNGMult: UInt32 = 0x41C64E6D
nonisolated let pokeRNGAdd: UInt32 = 0x6073
nonisolated let pokeRNGRMult: UInt32 = 0xEEB9EB65
nonisolated let pokeRNGRAdd: UInt32 = 0x0A3561A1

nonisolated let xdRNGMult: UInt32 = 0x343FD
nonisolated let xdRNGAdd: UInt32 = 0x269EC3
nonisolated let xdRNGRMult: UInt32 = 0xB9B33155
nonisolated let xdRNGRAdd: UInt32 = 0xA170F641

nonisolated func makePokeRNG(_ seed: UInt32) -> LCRNG { LCRNG(mult: pokeRNGMult, add: pokeRNGAdd, seed: seed) }
nonisolated func makePokeRNGR(_ seed: UInt32) -> LCRNG { LCRNG(mult: pokeRNGRMult, add: pokeRNGRAdd, seed: seed) }
nonisolated func makeXDRNG(_ seed: UInt32) -> LCRNG { LCRNG(mult: xdRNGMult, add: xdRNGAdd, seed: seed) }
nonisolated func makeXDRNGR(_ seed: UInt32) -> LCRNG { LCRNG(mult: xdRNGRMult, add: xdRNGRAdd, seed: seed) }

// ============================================================================
// MARK: - PokeFinder Port: LCRNGReverse (from Core/RNG/LCRNGReverse.cpp)
// ============================================================================

/// Recovers origin seeds from IVs using meet-in-the-middle attacks.
/// Ported from PokeFinder (GPLv3).
nonisolated enum LCRNGReverse {
    enum RNGMethod {
        case method1, method1Reverse, method2, method4
        case xdColo, channel
        case cuteCharmDPPt, cuteCharmHGSS
    }

    struct IVToPIDResult: Identifiable {
        let id = UUID()
        let seed: UInt32
        let pid: UInt32
        let sid: UInt16
        let method: RNGMethod
        var methodName: String {
            switch method {
            case .method1: return "Method 1"
            case .method1Reverse: return "Method 1 (R)"
            case .method2: return "Method 2"
            case .method4: return "Method 4"
            case .xdColo: return "XD/Colo"
            case .channel: return "Channel"
            case .cuteCharmDPPt: return "Cute Charm (DPPt)"
            case .cuteCharmHGSS: return "Cute Charm (HGSS)"
            }
        }
    }

    // Method 1/2 seed recovery (no gap between IV calls)
    static func recoverPokeRNGIVMethod12(hp: UInt8, atk: UInt8, def: UInt8,
                                          spa: UInt8, spd: UInt8, spe: UInt8) -> [(UInt32)] {
        let mult: UInt32 = 0x41c64e6d
        let add: UInt32 = 0x6073
        let mod: UInt32 = 0x67d3
        let pat: UInt32 = 0xd3e
        let inc: UInt32 = 0x4034

        var seeds: [UInt32] = []
        let firstIVs: UInt32 = UInt32(hp) | (UInt32(atk) << 5) | (UInt32(def) << 10)
        let first: UInt32 = firstIVs << 16
        let secondIVs: UInt32 = UInt32(spe) | (UInt32(spa) << 5) | (UInt32(spd) << 10)
        let second: UInt32 = secondIVs << 16

        let diff = UInt16(truncatingIfNeeded: (second &- first &* mult) >> 16)
        let s1a: UInt32 = (UInt32(diff) &* mod &+ inc) >> 16
        let start1 = UInt16(truncatingIfNeeded: (s1a &* pat) % mod)
        let s2a: UInt32 = (UInt32(diff ^ 0x8000) &* mod &+ inc) >> 16
        let start2 = UInt16(truncatingIfNeeded: (s2a &* pat) % mod)

        var low = UInt32(start1)
        while low < 0x10000 {
            let seed = first | low
            if (seed &* mult &+ add) & 0x7fff0000 == second {
                seeds.append(seed)
                seeds.append(seed ^ 0x80000000)
            }
            low += UInt32(mod)
        }

        low = UInt32(start2)
        while low < 0x10000 {
            let seed = first | low
            if (seed &* mult &+ add) & 0x7fff0000 == second {
                seeds.append(seed)
                seeds.append(seed ^ 0x80000000)
            }
            low += UInt32(mod)
        }

        return seeds
    }

    // Method 4 seed recovery (gap between IV calls)
    static func recoverPokeRNGIVMethod4(hp: UInt8, atk: UInt8, def: UInt8,
                                         spa: UInt8, spd: UInt8, spe: UInt8) -> [UInt32] {
        let mult: UInt32 = 0xc2a29a69
        let add: UInt32 = 0xe97e7b6a
        let mod: UInt32 = 0x3a89
        let pat: UInt32 = 0x2e4c
        let inc: UInt32 = 0x5831

        var seeds: [UInt32] = []
        let firstIVs: UInt32 = UInt32(hp) | (UInt32(atk) << 5) | (UInt32(def) << 10)
        let first: UInt32 = firstIVs << 16
        let secondIVs: UInt32 = UInt32(spe) | (UInt32(spa) << 5) | (UInt32(spd) << 10)
        let second: UInt32 = secondIVs << 16

        let diff = UInt16(truncatingIfNeeded: (second &- (first &* mult &+ add)) >> 16)
        let s1a: UInt32 = (UInt32(diff) &* mod &+ inc) >> 16
        let start1 = UInt16(truncatingIfNeeded: (s1a &* pat) % mod)
        let s2a: UInt32 = (UInt32(diff ^ 0x8000) &* mod &+ inc) >> 16
        let start2 = UInt16(truncatingIfNeeded: (s2a &* pat) % mod)

        var low = UInt32(start1)
        while low < 0x10000 {
            let seed = first | low
            if (seed &* mult &+ add) & 0x7fff0000 == second {
                seeds.append(seed)
                seeds.append(seed ^ 0x80000000)
            }
            low += UInt32(mod)
        }

        low = UInt32(start2)
        while low < 0x10000 {
            let seed = first | low
            if (seed &* mult &+ add) & 0x7fff0000 == second {
                seeds.append(seed)
                seeds.append(seed ^ 0x80000000)
            }
            low += UInt32(mod)
        }

        return seeds
    }

    // XDRNG IV seed recovery
    static func recoverXDRNGIV(hp: UInt8, atk: UInt8, def: UInt8,
                                spa: UInt8, spd: UInt8, spe: UInt8) -> [UInt32] {
        let mult: UInt32 = 0x343fd
        let sub: UInt32 = 0x259ec4
        let base: UInt64 = 0x343fabc02

        var seeds: [UInt32] = []
        let firstIVs: UInt32 = UInt32(hp) | (UInt32(atk) << 5) | (UInt32(def) << 10)
        let first: UInt32 = firstIVs << 16
        let secondIVs: UInt32 = UInt32(spe) | (UInt32(spa) << 5) | (UInt32(spd) << 10)
        let second: UInt32 = secondIVs << 16

        let rawT: UInt32 = (second &- mult &* first) &- sub
        var t = UInt64(rawT) & 0x7FFFFFFF
        let kmax = (base &- t) >> 31

        for _ in 0...kmax {
            if t % UInt64(mult) < 0x10000 {
                let seed = first | UInt32(t / UInt64(mult))
                seeds.append(seed)
                seeds.append(seed ^ 0x80000000)
            }
            t &+= 0x80000000
        }

        return seeds
    }

    /// Full IV-to-PID calculation (from IVToPIDCalculator.cpp)
    static func calculatePIDs(hp: UInt8, atk: UInt8, def: UInt8,
                               spa: UInt8, spd: UInt8, spe: UInt8,
                               nature: UInt8, tid: UInt16) -> [IVToPIDResult] {
        let bridgeResults = PFBridge.ivToPID(hp: hp, atk: atk, def: def,
                                              spa: spa, spd: spd, spe: spe,
                                              nature: nature, tid: tid)
        return bridgeResults.map { r in
            let method: RNGMethod = switch PFMethod(rawValue: r.method) {
            case .method1: .method1
            case .method1Reverse: .method1Reverse
            case .method2: .method2
            case .method4: .method4
            case .xdColo: .xdColo
            case .channel: .channel
            case .cuteCharmDPPt: .cuteCharmDPPt
            case .cuteCharmHGSS: .cuteCharmHGSS
            default: .method1
            }
            return IVToPIDResult(seed: r.seed, pid: r.pid, sid: r.sid, method: method)
        }
    }
}

// ============================================================================
// MARK: - PokeFinder Port: Finder Types & Models
// ============================================================================

/// Nature names in game-engine index order (pid % 25). Matches pfNatureModifiers.
let pfNatureNames: [String] = [
    "Hardy", "Lonely", "Brave", "Adamant", "Naughty",
    "Bold", "Docile", "Relaxed", "Impish", "Lax",
    "Modest", "Mild", "Bashful", "Quiet", "Rash",
    "Calm", "Gentle", "Careful", "Quirky", "Sassy",
    "Timid", "Hasty", "Jolly", "Naive", "Serious"
]

enum FinderGeneration: String, CaseIterable, Identifiable {
    case gen3 = "Gen 3"
    case gen4 = "Gen 4"
    var id: String { rawValue }
}

enum FinderMethod: String, CaseIterable, Identifiable {
    case method1 = "Method 1"
    case method2 = "Method 2"
    case method4 = "Method 4"
    case methodJ = "Method J"
    case methodK = "Method K"
    var id: String { rawValue }

    static func methods(for gen: FinderGeneration) -> [FinderMethod] {
        switch gen {
        case .gen3: return [.method1, .method2, .method4]
        case .gen4: return [.method1, .methodJ, .methodK]
        }
    }
}

enum FinderLead: String, CaseIterable, Identifiable {
    case none = "None"
    case synchronize = "Synchronize"
    var id: String { rawValue }
}

nonisolated func finderMethodToPF(_ method: FinderMethod) -> PFMethod {
    switch method {
    case .method1: return .method1
    case .method2: return .method2
    case .method4: return .method4
    case .methodJ: return .methodJ
    case .methodK: return .methodK
    }
}

struct StaticSearchResult: Identifiable {
    let id = UUID()
    let seed: UInt32
    let pid: UInt32
    let ivHP: UInt8
    let ivAtk: UInt8
    let ivDef: UInt8
    let ivSpA: UInt8
    let ivSpD: UInt8
    let ivSpe: UInt8
    let nature: UInt8
    let ability: UInt8
    let gender: UInt8
    let shiny: Bool
    let advances: UInt32
    let method: FinderMethod

    var natureName: String { pfNatureNames[Int(nature)] }
    var pidHex: String { String(format: "%08X", pid) }
    var seedHex: String { String(format: "%08X", seed) }
    var ivSummary: String { "\(ivHP)/\(ivAtk)/\(ivDef)/\(ivSpA)/\(ivSpD)/\(ivSpe)" }
}

struct SeedToTimeResult3: Identifiable, Hashable {
    let id = UUID()
    let originSeed: UInt16
    let advances: UInt32
    let day: Int
    let hour: Int
    let minute: Int

    var displayTime: String { String(format: "Day %d  %02d:%02d", day + 1, hour, minute) }
}

struct SeedToTimeResult4: Identifiable, Hashable {
    let id = UUID()
    let seed: UInt32
    let delay: UInt16
    let hour: UInt8
    let month: Int
    let day: Int
    let minute: Int
    let second: Int

    var displayTime: String {
        String(format: "%02d/%02d %02d:%02d:%02d  (delay %d)", month, day, hour, minute, second, delay)
    }
}

struct SeedVerificationResult {
    let actualSeed: UInt32
    let targetSeed: UInt32
    let delayDelta: Int
}

// ============================================================================
// MARK: - PokeFinder Port: Finder Profiles
// ============================================================================

struct FinderProfile: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var tid: UInt16
    var sid: UInt16
}

/// Manages saved TID/SID profiles via UserDefaults.
enum FinderProfileStore {
    private static let key = "finderProfiles"
    private static let lastKey = "finderLastProfileID"

    static func load() -> [FinderProfile] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let profiles = try? JSONDecoder().decode([FinderProfile].self, from: data)
        else { return [] }
        return profiles
    }

    static func save(_ profiles: [FinderProfile]) {
        if let data = try? JSONEncoder().encode(profiles) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static var lastProfileID: UUID? {
        get {
            guard let str = UserDefaults.standard.string(forKey: lastKey) else { return nil }
            return UUID(uuidString: str)
        }
        set { UserDefaults.standard.set(newValue?.uuidString, forKey: lastKey) }
    }
}

// ============================================================================
// MARK: - PokeFinder Port: Gen 3 Origin Seed Recovery
// ============================================================================

/// Walk backward from a 32-bit seed to find the 16-bit origin seed (Gen 3).
/// Returns (originSeed, advanceCount).
nonisolated func findGen3OriginSeed(_ seed: UInt32) -> (UInt16, UInt32) {
    if seed <= 0xFFFF { return (UInt16(seed), 0) }
    var rng = makePokeRNGR(seed)
    var count: UInt32 = 0
    var current = seed
    while current > 0xFFFF {
        current = rng.next()
        count += 1
    }
    return (UInt16(current), count)
}

// ============================================================================
// MARK: - PokeFinder Port: Static Generator (Gen 3)
// ============================================================================

/// Generate Pokemon at each advance from a known seed using Gen 3 methods.
nonisolated func staticGenerateGen3(
    seed: UInt32,
    initialAdvance: UInt32,
    maxAdvance: UInt32,
    natures: Set<UInt8>,
    tid: UInt16,
    sid: UInt16,
    shinyOnly: Bool,
    method: FinderMethod
) -> [StaticSearchResult] {
    var results: [StaticSearchResult] = []
    staticGenerateGen3Streaming(
        seed: seed, initialAdvance: initialAdvance, maxAdvance: maxAdvance,
        natures: natures, tid: tid, sid: sid, shinyOnly: shinyOnly, method: method
    ) { results.append($0) }
    return results
}

nonisolated func staticGenerateGen3Streaming(
    seed: UInt32,
    initialAdvance: UInt32,
    maxAdvance: UInt32,
    natures: Set<UInt8>,
    tid: UInt16,
    sid: UInt16,
    shinyOnly: Bool,
    method: FinderMethod,
    onResult: (StaticSearchResult) -> Void
) {
    let pfMethod = finderMethodToPF(method)
    var natArr = [Bool](repeating: false, count: 25)
    for n in natures { natArr[Int(n)] = true }
    let shinyFilter: UInt8 = shinyOnly ? 1 : 255

    let results = PFBridge.staticGenerate3(
        seed: seed, initialAdvances: initialAdvance, maxAdvances: maxAdvance,
        method: pfMethod, tid: tid, sid: sid,
        filterShiny: shinyFilter, natures: natArr)

    for r in results {
        if Task.isCancelled { return }
        onResult(StaticSearchResult(
            seed: seed, pid: r.pid,
            ivHP: r.ivs[0], ivAtk: r.ivs[1], ivDef: r.ivs[2],
            ivSpA: r.ivs[3], ivSpD: r.ivs[4], ivSpe: r.ivs[5],
            nature: r.nature, ability: r.ability,
            gender: r.gender, shiny: r.shiny > 0,
            advances: r.advances, method: method
        ))
    }
}

// ============================================================================
// MARK: - PokeFinder Port: Static Searcher (Gen 3)
// ============================================================================

/// Search for seeds producing Pokemon matching the given IV/nature/shiny filters.
/// CPU-intensive — call from a background task.
nonisolated func staticSearchGen3(
    minIVs: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8),
    maxIVs: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8),
    natures: Set<UInt8>,
    tid: UInt16,
    sid: UInt16,
    shinyOnly: Bool,
    method: FinderMethod
) -> [StaticSearchResult] {
    var results: [StaticSearchResult] = []
    staticSearchGen3Streaming(
        minIVs: minIVs, maxIVs: maxIVs, natures: natures,
        tid: tid, sid: sid, shinyOnly: shinyOnly, method: method
    ) { results.append($0) }
    return results
}

nonisolated func staticSearchGen3Streaming(
    minIVs: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8),
    maxIVs: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8),
    natures: Set<UInt8>,
    tid: UInt16,
    sid: UInt16,
    shinyOnly: Bool,
    method: FinderMethod,
    onResult: (StaticSearchResult) -> Void
) {
    let pfMethod = finderMethodToPF(method)
    var natArr = [Bool](repeating: false, count: 25)
    for n in natures { natArr[Int(n)] = true }
    let shinyFilter: UInt8 = shinyOnly ? 1 : 255
    let ivMin = [minIVs.0, minIVs.1, minIVs.2, minIVs.3, minIVs.4, minIVs.5]
    let ivMax = [maxIVs.0, maxIVs.1, maxIVs.2, maxIVs.3, maxIVs.4, maxIVs.5]

    let results = PFBridge.staticSearch3(
        method: pfMethod, tid: tid, sid: sid,
        filterShiny: shinyFilter, ivMin: ivMin, ivMax: ivMax, natures: natArr)

    for r in results {
        if Task.isCancelled { return }
        onResult(StaticSearchResult(
            seed: r.seed, pid: r.pid,
            ivHP: r.ivs[0], ivAtk: r.ivs[1], ivDef: r.ivs[2],
            ivSpA: r.ivs[3], ivSpD: r.ivs[4], ivSpe: r.ivs[5],
            nature: r.nature, ability: r.ability,
            gender: r.gender, shiny: r.shiny > 0,
            advances: 0, method: method
        ))
    }
}

// ============================================================================
// MARK: - PokeFinder Port: Seed to Time (Gen 3)
// ============================================================================

/// Convert a 32-bit seed to date/time combinations (Gen 3).
/// Ported from PokeFinder's SeedToTimeCalculator3.
nonisolated func seedToTimeGen3(seed: UInt32) -> (originSeed: UInt16, advances: UInt32, times: [SeedToTimeResult3]) {
    let origin = PFBridge.seedToTimeOriginSeed3(seed: seed)
    let dateTimes = PFBridge.seedToTime3(seed: seed, year: 2000)
    let times = dateTimes.prefix(200).map { dt in
        SeedToTimeResult3(originSeed: origin.originSeed, advances: origin.advances,
                          day: (dt.month - 1) * 31 + dt.day - 1, hour: dt.hour, minute: dt.minute)
    }
    return (origin.originSeed, origin.advances, times)
}

// ============================================================================
// MARK: - PokeFinder Port: Seed to Time (Gen 4)
// ============================================================================

/// Convert a 32-bit seed to date/time combinations (Gen 4).
/// Seed format: ab|cd|efgh where ab = hash, cd = hour, efgh = delay.
/// Ported from PokeFinder's SeedToTimeCalculator4.
nonisolated func seedToTimeGen4(seed: UInt32) -> [SeedToTimeResult4] {
    let bridgeResults = PFBridge.seedToTime4(seed: seed, year: 2000)
    return bridgeResults.prefix(300).map { r in
        SeedToTimeResult4(seed: seed, delay: UInt16(r.delay),
                          hour: UInt8(r.dateTime.hour),
                          month: r.dateTime.month, day: r.dateTime.day,
                          minute: r.dateTime.minute, second: r.dateTime.second)
    }
}

// ============================================================================
// MARK: - PokeFinder Port: Static Generator (Gen 4)
// ============================================================================

/// Generate Pokemon at each advance from a known seed using Gen 4 methods.
/// Method 1 is identical to Gen 3 Method 1.
/// Method J (DPPt) and Method K (HGSS) use nature-locked PID loops.
nonisolated func staticGenerateGen4(
    seed: UInt32,
    initialAdvance: UInt32,
    maxAdvance: UInt32,
    natures: Set<UInt8>,
    tid: UInt16,
    sid: UInt16,
    shinyOnly: Bool,
    method: FinderMethod,
    lead: FinderLead,
    syncNature: UInt8 = 0
) -> [StaticSearchResult] {
    var results: [StaticSearchResult] = []
    staticGenerateGen4Streaming(
        seed: seed, initialAdvance: initialAdvance, maxAdvance: maxAdvance,
        natures: natures, tid: tid, sid: sid, shinyOnly: shinyOnly,
        method: method, lead: lead, syncNature: syncNature
    ) { results.append($0) }
    return results
}

nonisolated func staticGenerateGen4Streaming(
    seed: UInt32,
    initialAdvance: UInt32,
    maxAdvance: UInt32,
    natures: Set<UInt8>,
    tid: UInt16,
    sid: UInt16,
    shinyOnly: Bool,
    method: FinderMethod,
    lead: FinderLead,
    syncNature: UInt8 = 0,
    onResult: (StaticSearchResult) -> Void
) {
    let pfMethod = finderMethodToPF(method)
    let pfLead: PFLead = lead == .synchronize ? .synchronize : .none
    var natArr = [Bool](repeating: false, count: 25)
    for n in natures { natArr[Int(n)] = true }
    let shinyFilter: UInt8 = shinyOnly ? 1 : 255

    let results = PFBridge.staticGenerate4(
        seed: seed, initialAdvances: initialAdvance, maxAdvances: maxAdvance,
        method: pfMethod, lead: pfLead, tid: tid, sid: sid,
        filterShiny: shinyFilter, natures: natArr)

    for r in results {
        if Task.isCancelled { return }
        onResult(StaticSearchResult(
            seed: seed, pid: r.pid,
            ivHP: r.ivs[0], ivAtk: r.ivs[1], ivDef: r.ivs[2],
            ivSpA: r.ivs[3], ivSpD: r.ivs[4], ivSpe: r.ivs[5],
            nature: r.nature, ability: r.ability,
            gender: r.gender, shiny: r.shiny > 0,
            advances: r.advances, method: method
        ))
    }
}

// ============================================================================
// MARK: - PokeFinder Port: Static Searcher (Gen 4)
// ============================================================================

/// Search for Gen 4 seeds matching the given filters.
/// Validates initial seeds against hour < 24 and delay range.
nonisolated func staticSearchGen4(
    minIVs: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8),
    maxIVs: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8),
    natures: Set<UInt8>,
    tid: UInt16,
    sid: UInt16,
    shinyOnly: Bool,
    method: FinderMethod,
    minDelay: UInt16,
    maxDelay: UInt16
) -> [StaticSearchResult] {
    var results: [StaticSearchResult] = []
    staticSearchGen4Streaming(
        minIVs: minIVs, maxIVs: maxIVs, natures: natures,
        tid: tid, sid: sid, shinyOnly: shinyOnly, method: method,
        minDelay: minDelay, maxDelay: maxDelay
    ) { results.append($0) }
    return results
}

nonisolated func staticSearchGen4Streaming(
    minIVs: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8),
    maxIVs: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8),
    natures: Set<UInt8>,
    tid: UInt16,
    sid: UInt16,
    shinyOnly: Bool,
    method: FinderMethod,
    minDelay: UInt16,
    maxDelay: UInt16,
    onResult: (StaticSearchResult) -> Void
) {
    let pfMethod = finderMethodToPF(method)
    var natArr = [Bool](repeating: false, count: 25)
    for n in natures { natArr[Int(n)] = true }
    let shinyFilter: UInt8 = shinyOnly ? 1 : 255
    let ivMin = [minIVs.0, minIVs.1, minIVs.2, minIVs.3, minIVs.4, minIVs.5]
    let ivMax = [maxIVs.0, maxIVs.1, maxIVs.2, maxIVs.3, maxIVs.4, maxIVs.5]

    let results = PFBridge.staticSearch4(
        minDelay: UInt32(minDelay), maxDelay: UInt32(maxDelay),
        method: pfMethod, tid: tid, sid: sid,
        filterShiny: shinyFilter, ivMin: ivMin, ivMax: ivMax, natures: natArr)

    for r in results {
        if Task.isCancelled { return }
        onResult(StaticSearchResult(
            seed: r.seed, pid: r.pid,
            ivHP: r.ivs[0], ivAtk: r.ivs[1], ivDef: r.ivs[2],
            ivSpA: r.ivs[3], ivSpD: r.ivs[4], ivSpe: r.ivs[5],
            nature: r.nature, ability: r.ability,
            gender: r.gender, shiny: r.shiny > 0,
            advances: r.advances, method: method
        ))
    }
}

// ============================================================================
// MARK: - PokeFinder Port: Seed Verification
// ============================================================================

/// Verify what seed was actually hit by reverse-calculating from caught Pokemon's IVs.
/// Returns the delta between actual and target seeds.
nonisolated func verifySeedFromIVs(
    caughtHP: UInt8, caughtAtk: UInt8, caughtDef: UInt8,
    caughtSpA: UInt8, caughtSpD: UInt8, caughtSpe: UInt8,
    caughtNature: UInt8,
    tid: UInt16,
    targetSeed: UInt32,
    method: FinderMethod
) -> SeedVerificationResult? {
    let pidResults = LCRNGReverse.calculatePIDs(
        hp: caughtHP, atk: caughtAtk, def: caughtDef,
        spa: caughtSpA, spd: caughtSpD, spe: caughtSpe,
        nature: caughtNature, tid: tid
    )

    // Find the result whose method matches
    let targetMethod: LCRNGReverse.RNGMethod
    switch method {
    case .method1, .methodJ, .methodK: targetMethod = .method1
    case .method2: targetMethod = .method2
    case .method4: targetMethod = .method4
    }

    let matching = pidResults.filter { $0.method == targetMethod }
    guard let closest = matching.first else { return nil }

    // Compute delay delta for Gen 4 seeds
    let actualDelay = Int(closest.seed & 0xFFFF)
    let targetDelay = Int(targetSeed & 0xFFFF)

    return SeedVerificationResult(
        actualSeed: closest.seed,
        targetSeed: targetSeed,
        delayDelta: actualDelay - targetDelay
    )
}

// ============================================================================
// MARK: - Finder Timer Bridge
// ============================================================================

/// Shared bridge for passing Finder results to the Timer view.
@Observable
final class FinderTimerBridge {
    static let shared = FinderTimerBridge()
    var pendingGen: TimerGeneration?
    var pendingTargetFrame: Int?
    var pendingTargetDelay: Int?
    var pendingTargetSecond: Int?
    var shouldSwitchToTimer: Bool = false
    var selectedTime: String?
    var selectedSeed: String?

    func clear() {
        pendingGen = nil
        pendingTargetFrame = nil
        pendingTargetDelay = nil
        pendingTargetSecond = nil
        shouldSwitchToTimer = false
        selectedTime = nil
        selectedSeed = nil
    }
}

// ============================================================================
// MARK: - PokeFinder Port: IVChecker (from Core/Util/IVChecker.cpp)
// ============================================================================

/// Nature modifiers table matching PokeFinder's Nature.hpp
private let pfNatureModifiers: [[Float]] = [
    // [Atk, Def, SpA, SpD, Spe]  — nature index 0-24
    [1.0, 1.0, 1.0, 1.0, 1.0], // Hardy
    [1.1, 0.9, 1.0, 1.0, 1.0], // Lonely
    [1.1, 1.0, 1.0, 1.0, 0.9], // Brave
    [1.1, 1.0, 0.9, 1.0, 1.0], // Adamant
    [1.1, 1.0, 1.0, 0.9, 1.0], // Naughty
    [0.9, 1.1, 1.0, 1.0, 1.0], // Bold
    [1.0, 1.0, 1.0, 1.0, 1.0], // Docile
    [1.0, 1.1, 1.0, 1.0, 0.9], // Relaxed
    [1.0, 1.1, 0.9, 1.0, 1.0], // Impish
    [1.0, 1.1, 1.0, 0.9, 1.0], // Lax
    [0.9, 1.0, 1.1, 1.0, 1.0], // Modest
    [1.0, 0.9, 1.1, 1.0, 1.0], // Mild
    [1.0, 1.0, 1.0, 1.0, 1.0], // Bashful
    [1.0, 1.0, 1.1, 1.0, 0.9], // Quiet
    [1.0, 1.0, 1.1, 0.9, 1.0], // Rash
    [0.9, 1.0, 1.0, 1.1, 1.0], // Calm
    [1.0, 0.9, 1.0, 1.1, 1.0], // Gentle
    [1.0, 1.0, 0.9, 1.1, 1.0], // Careful
    [1.0, 1.0, 1.0, 1.0, 1.0], // Quirky
    [1.0, 1.0, 1.0, 1.1, 0.9], // Sassy
    [0.9, 1.0, 1.0, 1.0, 1.1], // Timid
    [1.0, 0.9, 1.0, 1.0, 1.1], // Hasty
    [1.0, 1.0, 0.9, 1.0, 1.1], // Jolly
    [1.0, 1.0, 1.0, 0.9, 1.1], // Naive
    [1.0, 1.0, 1.0, 1.0, 1.0], // Serious
]

/// Compute stat matching PokeFinder's Nature::computeStat
private func pfComputeStat(baseStat: UInt16, iv: UInt8, nature: UInt8, level: UInt8, index: UInt8) -> UInt16 {
    let stat = ((2 * UInt16(baseStat) + UInt16(iv)) * UInt16(level)) / 100
    if index == 0 { // HP
        return stat + UInt16(level) + 10
    } else {
        return UInt16(Float(stat + 5) * pfNatureModifiers[Int(nature)][Int(index) - 1])
    }
}

struct IVCalcResult: Identifiable {
    let id = UUID()
    let statName: String
    let possibleIVs: [UInt8]

    var displayRange: String {
        guard let first = possibleIVs.first, let last = possibleIVs.last else { return "?" }
        if first == last { return "\(first)" }
        return "\(first)-\(last)"
    }
}

/// Full IV range calculator matching PokeFinder's IVChecker::calculateIVRange
func pfCalculateIVRange(baseStats: [UInt8], stats: [[UInt16]], levels: [UInt8],
                         nature: UInt8, characteristic: UInt8 = 255, hiddenPower: UInt8 = 255) -> [IVCalcResult] {
    let statNames = ["HP", "Attack", "Defense", "Sp. Atk", "Sp. Def", "Speed"]
    let ivOrder: [UInt8] = [0, 1, 2, 5, 3, 4]

    // Calculate IVs for each set of stats, then intersect
    var ivs: [[UInt8]] = Array(repeating: [], count: 6)

    for (si, statSet) in stats.enumerated() {
        var minIVs: [UInt8] = Array(repeating: 31, count: 6)
        var maxIVs: [UInt8] = Array(repeating: 0, count: 6)

        for i in 0..<6 {
            for iv: UInt8 in 0...31 {
                if nature != 255 {
                    let calc = pfComputeStat(baseStat: UInt16(baseStats[i]), iv: iv,
                                              nature: nature, level: levels[si], index: UInt8(i))
                    if calc == statSet[i] {
                        minIVs[i] = min(iv, minIVs[i])
                        maxIVs[i] = max(iv, maxIVs[i])
                    }
                } else {
                    // Unknown nature: check with Hardy (neutral) and also +/- 10%
                    let calc = pfComputeStat(baseStat: UInt16(baseStats[i]), iv: iv,
                                              nature: 0, level: levels[si], index: UInt8(i))
                    if calc == statSet[i] ||
                        (i != 0 && (UInt16(Float(calc) * 0.9) == statSet[i] || UInt16(Float(calc) * 1.1) == statSet[i])) {
                        minIVs[i] = min(iv, minIVs[i])
                        maxIVs[i] = max(iv, maxIVs[i])
                    }
                }
            }
        }

        // Build possible arrays with characteristic filtering
        var current: [[UInt8]] = Array(repeating: [], count: 6)
        var characteristicHigh: UInt8 = 31
        var charIndex: Int = -1

        if characteristic != 255 {
            charIndex = Int(ivOrder[Int(characteristic) / 5])
            let charResult = characteristic % 5

            for iv in minIVs[charIndex]...maxIVs[charIndex] {
                if (iv % 5) == charResult {
                    if minIVs.allSatisfy({ iv >= $0 }) {
                        current[charIndex].append(iv)
                        characteristicHigh = iv
                    }
                }
            }
        }

        for i in 0..<6 {
            if i == charIndex { continue }
            if minIVs[i] <= maxIVs[i] {
                for iv in minIVs[i]...min(maxIVs[i], characteristicHigh) {
                    current[i].append(iv)
                }
            }
        }

        if si == 0 {
            ivs = current
        } else {
            // Intersect
            for j in 0..<6 {
                let intersection = ivs[j].filter { current[j].contains($0) }
                ivs[j] = intersection
            }
        }
    }

    // Hidden power filtering
    if hiddenPower != 255 {
        var possible: [[UInt8]] = Array(repeating: [], count: 6)
        for i in 0..<6 {
            if ivs[i].contains(where: { $0 % 2 == 0 }) { possible[i].append(0) }
            if ivs[i].contains(where: { $0 % 2 == 1 }) { possible[i].append(1) }
        }

        var temp: [[UInt8]] = Array(repeating: [], count: 6)
        for hp in possible[0] {
            for atk in possible[1] {
                for def in possible[2] {
                    for spa in possible[3] {
                        for spd in possible[4] {
                            for spe in possible[5] {
                                let typeVal = (UInt8(hp) + 2 * atk + 4 * def + 16 * spa + 32 * spd + 8 * spe) * 15 / 63
                                if typeVal == hiddenPower {
                                    temp[0].append(contentsOf: ivs[0].filter { $0 % 2 == hp })
                                    temp[1].append(contentsOf: ivs[1].filter { $0 % 2 == atk })
                                    temp[2].append(contentsOf: ivs[2].filter { $0 % 2 == def })
                                    temp[3].append(contentsOf: ivs[3].filter { $0 % 2 == spa })
                                    temp[4].append(contentsOf: ivs[4].filter { $0 % 2 == spd })
                                    temp[5].append(contentsOf: ivs[5].filter { $0 % 2 == spe })
                                }
                            }
                        }
                    }
                }
            }
        }
        for i in 0..<6 {
            ivs[i] = Array(Set(temp[i])).sorted()
        }
    }

    return (0..<6).map { IVCalcResult(statName: statNames[$0], possibleIVs: ivs[$0]) }
}

// ============================================================================
// MARK: - Hidden Power Calculator
// ============================================================================

let hiddenPowerTypes = [
    "Fighting", "Flying", "Poison", "Ground", "Rock", "Bug",
    "Ghost", "Steel", "Fire", "Water", "Grass", "Electric",
    "Psychic", "Ice", "Dragon", "Dark"
]

func calculateHiddenPowerType(ivHP: Int, ivAtk: Int, ivDef: Int,
                               ivSpeed: Int, ivSpAtk: Int, ivSpDef: Int) -> String {
    let a = ivHP % 2
    let b = ivAtk % 2
    let c = ivDef % 2
    let d = ivSpeed % 2
    let e = ivSpAtk % 2
    let f = ivSpDef % 2
    let index = ((a + 2*b + 4*c + 8*d + 16*e + 32*f) * 15) / 63
    return hiddenPowerTypes[min(index, hiddenPowerTypes.count - 1)]
}

func calculateHiddenPowerBasePower(ivHP: Int, ivAtk: Int, ivDef: Int,
                                    ivSpeed: Int, ivSpAtk: Int, ivSpDef: Int) -> Int {
    let a = (ivHP / 2) % 2
    let b = (ivAtk / 2) % 2
    let c = (ivDef / 2) % 2
    let d = (ivSpeed / 2) % 2
    let e = (ivSpAtk / 2) % 2
    let f = (ivSpDef / 2) % 2
    return ((a + 2*b + 4*c + 8*d + 16*e + 32*f) * 40) / 63 + 30
}

// ============================================================================
// MARK: - Timer Engine
// ============================================================================

@Observable
final class RNGTimerEngine {
    var phases: [Int] = []
    var currentPhaseIndex: Int = 0
    var remainingMs: Int = 0
    var isRunning: Bool = false

    private var timer: Timer?
    private var phaseStartDate: Date?
    private var phaseTargetMs: Int = 0

    func start(phases: [Int]) {
        let finite = phases.filter { $0 != Int.max && $0 > 0 }
        guard !finite.isEmpty else { return }
        self.phases = phases
        currentPhaseIndex = 0
        isRunning = true
        beginPhase(index: 0)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isRunning = false
        currentPhaseIndex = 0
        remainingMs = 0
    }

    private func beginPhase(index: Int) {
        guard index < phases.count else {
            playBeep(count: 3)
            stop()
            return
        }
        if phases[index] == Int.max {
            // Variable target: just stay on this phase, user stops manually
            currentPhaseIndex = index
            remainingMs = 0
            return
        }
        currentPhaseIndex = index
        phaseTargetMs = phases[index]
        remainingMs = phaseTargetMs
        phaseStartDate = Date()

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func tick() {
        guard let start = phaseStartDate else { return }
        let elapsed = Int(Date().timeIntervalSince(start) * 1000)
        remainingMs = max(0, phaseTargetMs - elapsed)

        if remainingMs <= 0 {
            timer?.invalidate()
            playBeep(count: 1)
            beginPhase(index: currentPhaseIndex + 1)
        }
    }

    var totalPhases: Int { phases.count }
    var displaySeconds: Double { Double(remainingMs) / 1000.0 }
}

private func playBeep(count: Int) {
    for i in 0..<count {
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.15) {
            AudioServicesPlaySystemSound(1057)
        }
    }
}

// ============================================================================
// MARK: - Root RNG Tools View
// ============================================================================

enum TimerGeneration: String, CaseIterable, Identifiable {
    case gen3 = "Gen 3"
    case gen4 = "Gen 4"
    case gen5 = "Gen 5"
    case custom = "Custom"
    var id: String { rawValue }
}

struct RNGToolsView: View {
    @State private var selectedTool = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Tool", selection: $selectedTool) {
                    Text("Timer").tag(0)
                    Text("Finder").tag(5)
                    Text("IV Calc").tag(1)
                    Text("IV→PID").tag(2)
                    Text("HP").tag(3)
                    Text("Credits").tag(4)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)

                switch selectedTool {
                case 0: RNGTimerView()
                case 1: IVCalculatorView()
                case 2: IVToPIDView()
                case 3: HiddenPowerCalcView()
                case 5: FinderRootView(switchToTimer: { selectedTool = 0 })
                default: RNGCreditsView()
                }
            }
            .navigationTitle("RNG Tools")
            .onChange(of: FinderTimerBridge.shared.shouldSwitchToTimer) {
                if FinderTimerBridge.shared.shouldSwitchToTimer {
                    selectedTool = 0
                    FinderTimerBridge.shared.shouldSwitchToTimer = false
                }
            }
        }
    }
}

// ============================================================================
// MARK: - RNG Timer View
// ============================================================================

struct RNGTimerView: View {
    @State private var engine = RNGTimerEngine()
    @State private var generation: TimerGeneration = .gen5
    @State private var consoleType: RNGConsole = .ndsSlot1
    @State private var customFramerate: Double = 60.0
    @State private var precisionCalibration = false

    // Gen 3
    @State private var gen3Mode: Gen3TimerMode = .standard
    @State private var gen3PreTimer = 5000
    @State private var gen3TargetFrame = 1000
    @State private var gen3Calibration = 0
    @State private var gen3FrameHit = 0

    // Gen 4 (defaults from EonTimer store)
    @State private var gen4TargetDelay = 600
    @State private var gen4TargetSecond = 50
    @State private var gen4CalibratedDelay = 500
    @State private var gen4CalibratedSecond = 14
    @State private var gen4DelayHit = 0

    // Gen 5 (defaults from EonTimer store)
    @State private var gen5Mode: Gen5TimerMode = .standard
    @State private var gen5TargetDelay = 1200
    @State private var gen5TargetSecond = 50
    @State private var gen5TargetAdvances = 100
    @State private var gen5Calibration = -95
    @State private var gen5EntralinkCalibration = 256
    @State private var gen5FrameCalibration = 0
    @State private var gen5DelayHit: Int?
    @State private var gen5SecondHit: Int?
    @State private var gen5AdvancesHit: Int?

    // Finder reminder
    @State private var reminderText: String?

    // Custom
    @State private var customPhases: [CustomPhase] = [
        CustomPhase(unit: .milliseconds, target: 5000, calibration: 0)
    ]

    private var settings: CalibratorSettings {
        CalibratorSettings(console: consoleType, customFramerate: customFramerate,
                           precisionCalibration: precisionCalibration, minimumLength: EONTIMER_MINIMUM_LENGTH)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                timerDisplay

                if let reminderText {
                    HStack {
                        Image(systemName: "info.circle.fill")
                            .foregroundStyle(.blue)
                        Text(reminderText)
                            .font(.callout)
                        Spacer()
                        Button {
                            self.reminderText = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding()
                    .background(Color.blue.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                Picker("Generation", selection: $generation) {
                    ForEach(TimerGeneration.allCases) { gen in
                        Text(gen.rawValue).tag(gen)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(engine.isRunning)

                // Console picker
                RNGSection(title: "Console", icon: "gamecontroller") {
                    Picker("Console", selection: $consoleType) {
                        ForEach(RNGConsole.allCases) { c in Text(c.rawValue).tag(c) }
                    }
                    if consoleType == .custom {
                        RNGDoubleField(label: "Framerate", value: $customFramerate)
                    }
                    Toggle("Precision Calibration", isOn: $precisionCalibration)
                }

                RNGSection(title: "Settings", icon: "gearshape") {
                    switch generation {
                    case .gen3: gen3Settings
                    case .gen4: gen4Settings
                    case .gen5: gen5Settings
                    case .custom: customSettings
                    }
                }

                if generation != .custom {
                    RNGSection(title: "Calibration", icon: "tuningfork") {
                        calibrationSection
                    }
                }

                Button {
                    if engine.isRunning {
                        engine.stop()
                    } else {
                        engine.start(phases: computePhases())
                    }
                } label: {
                    Label(engine.isRunning ? "Stop" : "Start Timer",
                          systemImage: engine.isRunning ? "stop.fill" : "play.fill")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(engine.isRunning ? Color.red : Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(!engine.isRunning && computePhases().isEmpty)

                // Phase preview
                let phases = computePhases()
                if !phases.isEmpty && !engine.isRunning {
                    RNGSection(title: "Phase Preview", icon: "list.number") {
                        ForEach(Array(phases.enumerated()), id: \.offset) { i, ms in
                            HStack {
                                Text("Phase \(i + 1)")
                                Spacer()
                                if ms == Int.max {
                                    Text("Variable (manual stop)")
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text(String(format: "%.3fs", Double(ms) / 1000.0))
                                        .font(.system(.body, design: .monospaced))
                                }
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .onAppear {
            let bridge = FinderTimerBridge.shared
            if let gen = bridge.pendingGen {
                generation = gen
                if gen == .gen3, let frame = bridge.pendingTargetFrame {
                    gen3TargetFrame = frame
                }
                if gen == .gen4 {
                    if let delay = bridge.pendingTargetDelay {
                        gen4TargetDelay = delay
                    }
                    if let second = bridge.pendingTargetSecond {
                        gen4TargetSecond = second
                    }
                }
                if let time = bridge.selectedTime {
                    let seed = bridge.selectedSeed ?? "?"
                    reminderText = "Seed \(seed) — \(time)"
                }
                bridge.clear()
            }
        }
    }

    private var timerDisplay: some View {
        VStack(spacing: 8) {
            Text(String(format: "%.3f", engine.displaySeconds))
                .font(.system(size: 64, weight: .bold, design: .monospaced))
                .foregroundStyle(engine.isRunning ? .primary : .secondary)
                .contentTransition(.numericText())

            if engine.isRunning && engine.totalPhases > 1 {
                Text("Phase \(engine.currentPhaseIndex + 1) of \(engine.totalPhases)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: Gen Settings

    private var gen3Settings: some View {
        VStack(spacing: 12) {
            Picker("Mode", selection: $gen3Mode) {
                ForEach(Gen3TimerMode.allCases) { m in Text(m.rawValue).tag(m) }
            }
            RNGIntField(label: "Pre-Timer (ms)", value: $gen3PreTimer)
            RNGIntField(label: "Target Frame", value: $gen3TargetFrame)
            RNGIntField(label: "Calibration (ms)", value: $gen3Calibration)
        }
    }

    private var gen4Settings: some View {
        VStack(spacing: 12) {
            RNGIntField(label: "Calibrated Delay", value: $gen4CalibratedDelay)
            RNGIntField(label: "Calibrated Second", value: $gen4CalibratedSecond)
            RNGIntField(label: "Target Delay", value: $gen4TargetDelay)
            RNGIntField(label: "Target Second", value: $gen4TargetSecond)
        }
    }

    private var gen5Settings: some View {
        VStack(spacing: 12) {
            Picker("Mode", selection: $gen5Mode) {
                ForEach(Gen5TimerMode.allCases) { m in Text(m.rawValue).tag(m) }
            }
            RNGIntField(label: "Calibration", value: $gen5Calibration)
            if gen5Mode == .entralink || gen5Mode == .entralinkPlus {
                RNGIntField(label: "Entralink Cal.", value: $gen5EntralinkCalibration)
            }
            if gen5Mode == .entralinkPlus {
                RNGIntField(label: "Frame Cal.", value: $gen5FrameCalibration)
            }
            RNGIntField(label: "Target Delay", value: $gen5TargetDelay)
            RNGIntField(label: "Target Second", value: $gen5TargetSecond)
            if gen5Mode == .entralink || gen5Mode == .entralinkPlus {
                RNGIntField(label: "Target Advances", value: $gen5TargetAdvances)
            }
        }
    }

    private var customSettings: some View {
        VStack(spacing: 12) {
            ForEach(customPhases.indices, id: \.self) { i in
                HStack(spacing: 8) {
                    Text("Phase \(i + 1)").font(.caption).foregroundStyle(.secondary)
                        .frame(width: 56, alignment: .leading)
                    TextField("Value", value: Binding(
                        get: { customPhases[i].target },
                        set: { customPhases[i].target = $0 }
                    ), format: .number)
                    .textFieldStyle(.roundedBorder).frame(width: 80)

                    Picker("", selection: Binding(
                        get: { customPhases[i].unit },
                        set: { customPhases[i].unit = $0 }
                    )) {
                        ForEach(CustomTimerUnit.allCases) { u in Text(u.rawValue).tag(u) }
                    }.frame(width: 100)

                    TextField("Cal", value: Binding(
                        get: { customPhases[i].calibration },
                        set: { customPhases[i].calibration = $0 }
                    ), format: .number)
                    .textFieldStyle(.roundedBorder).frame(width: 60)

                    if customPhases.count > 1 {
                        Button { customPhases.remove(at: i) } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                        }.buttonStyle(.plain)
                    }
                }
            }
            Button { customPhases.append(CustomPhase(unit: .milliseconds, target: 5000, calibration: 0)) }
                label: { Label("Add Phase", systemImage: "plus.circle") }
        }
    }

    // MARK: Calibration

    private var calibrationSection: some View {
        VStack(spacing: 12) {
            switch generation {
            case .gen3:
                Text("Enter the frame you hit to adjust calibration.")
                    .font(.caption).foregroundStyle(.secondary)
                RNGIntField(label: "Frame Hit", value: $gen3FrameHit)
                Button("Update Calibration") {
                    gen3Calibration += calibrateGen3(settings, targetFrame: gen3TargetFrame, frameHit: gen3FrameHit)
                }
            case .gen4:
                Text("Enter the delay you hit.")
                    .font(.caption).foregroundStyle(.secondary)
                RNGIntField(label: "Delay Hit", value: $gen4DelayHit)
                Button("Update Calibration") {
                    let delta = calibrateGen4(settings, targetDelay: gen4TargetDelay, delayHit: gen4DelayHit)
                    gen4CalibratedDelay += delta
                }
            case .gen5:
                Text("Enter what you hit to refine calibration.")
                    .font(.caption).foregroundStyle(.secondary)
                RNGOptIntField(label: "Delay Hit", value: $gen5DelayHit)
                RNGOptIntField(label: "Second Hit", value: $gen5SecondHit)
                if gen5Mode == .entralinkPlus {
                    RNGOptIntField(label: "Advances Hit", value: $gen5AdvancesHit)
                }
                Button("Update Calibration") {
                    let result = calibrateGen5(settings, mode: gen5Mode,
                        targetDelay: gen5TargetDelay, targetSecond: gen5TargetSecond,
                        targetAdvances: gen5TargetAdvances,
                        delayHit: gen5DelayHit, secondHit: gen5SecondHit, advancesHit: gen5AdvancesHit)
                    gen5Calibration += result.calibrationDelta
                    gen5EntralinkCalibration += result.entralinkCalibrationDelta
                    gen5FrameCalibration += Int(result.frameCalibrationDelta)
                    gen5DelayHit = nil
                    gen5SecondHit = nil
                    gen5AdvancesHit = nil
                }
            case .custom:
                EmptyView()
            }
        }
    }

    private func computePhases() -> [Int] {
        switch generation {
        case .gen3:
            return createGen3Phases(settings, mode: gen3Mode, preTimer: gen3PreTimer,
                                     targetFrame: gen3TargetFrame, calibration: gen3Calibration)
        case .gen4:
            return createGen4Phases(settings, targetDelay: gen4TargetDelay, targetSecond: gen4TargetSecond,
                                     calibratedDelay: gen4CalibratedDelay, calibratedSecond: gen4CalibratedSecond)
        case .gen5:
            return createGen5Phases(settings, mode: gen5Mode,
                                     targetDelay: gen5TargetDelay, targetSecond: gen5TargetSecond,
                                     targetAdvances: gen5TargetAdvances, calibration: gen5Calibration,
                                     entralinkCalibration: gen5EntralinkCalibration, frameCalibration: gen5FrameCalibration)
        case .custom:
            return createCustomPhases(settings, phases: customPhases)
        }
    }
}

// ============================================================================
// MARK: - IV Calculator View
// ============================================================================

struct IVCalculatorView: View {
    @Query(sort: \PKMNStats.name) private var allPokemon: [PKMNStats]
    @State private var searchText = ""
    @State private var selectedPokemon: PKMNStats?
    @State private var level: UInt8 = 50
    @State private var natureIndex: UInt8 = 3 // Adamant

    @State private var evHP = 0; @State private var evAtk = 0; @State private var evDef = 0
    @State private var evSpAtk = 0; @State private var evSpDef = 0; @State private var evSpeed = 0

    @State private var statHP: UInt16 = 0; @State private var statAtk: UInt16 = 0
    @State private var statDef: UInt16 = 0; @State private var statSpAtk: UInt16 = 0
    @State private var statSpDef: UInt16 = 0; @State private var statSpeed: UInt16 = 0

    @State private var results: [IVCalcResult] = []

    private var filteredPokemon: [PKMNStats] {
        let t = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !t.isEmpty else { return [] }
        return Array(allPokemon.filter { $0.name.lowercased().contains(t) }.prefix(20))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if allPokemon.isEmpty {
                    ContentUnavailableView("Syncing Data", systemImage: "antenna.radiowaves.left.and.right",
                        description: Text("Waiting for Pokemon data to sync..."))
                } else {
                    pokemonSelector
                    if selectedPokemon != nil {
                        configSection
                        statEntrySection
                        calculateButton
                        resultsSection
                    }
                }
            }.padding()
        }
    }

    private var pokemonSelector: some View {
        RNGSection(title: "Pokemon", icon: "sparkles") {
            VStack(spacing: 8) {
                TextField("Search Pokemon...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: searchText) { selectedPokemon = nil; results = [] }

                if !filteredPokemon.isEmpty && selectedPokemon == nil {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(filteredPokemon, id: \.id) { pkmn in
                                Button {
                                    selectedPokemon = pkmn
                                    searchText = pkmn.name
                                    results = []
                                } label: {
                                    Text(pkmn.name).frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.vertical, 4).padding(.horizontal, 8)
                                }.buttonStyle(.plain)
                            }
                        }
                    }.frame(maxHeight: 200)
                }

                if let pkmn = selectedPokemon {
                    HStack(spacing: 12) {
                        baseStatPill("HP", pkmn.baseHP)
                        baseStatPill("Atk", pkmn.baseAtk)
                        baseStatPill("Def", pkmn.baseDef)
                        baseStatPill("SpA", pkmn.baseSpAtk)
                        baseStatPill("SpD", pkmn.baseSpDef)
                        baseStatPill("Spe", pkmn.baseSpeed)
                    }.font(.caption)

                    Button("Clear") { selectedPokemon = nil; searchText = ""; results = [] }.font(.caption)
                }
            }
        }
    }

    private func baseStatPill(_ label: String, _ value: Int) -> some View {
        VStack(spacing: 2) {
            Text(label).foregroundStyle(.secondary)
            Text("\(value)").bold()
        }.frame(maxWidth: .infinity)
    }

    private var configSection: some View {
        RNGSection(title: "Config", icon: "slider.horizontal.3") {
            HStack {
                Text("Level")
                Spacer()
                TextField("Lv", value: $level, format: .number)
                    .textFieldStyle(.roundedBorder).frame(width: 60)
            }
            Picker("Nature", selection: $natureIndex) {
                ForEach(Array(allNatures.enumerated()), id: \.element.id) { i, n in
                    Text("\(n.name) \(n.summary)").tag(UInt8(i))
                }
            }
        }
    }

    private var statEntrySection: some View {
        RNGSection(title: "Stats (from in-game summary)", icon: "number") {
            VStack(spacing: 8) {
                IVCalcRow16(label: "HP", stat: $statHP, ev: $evHP)
                IVCalcRow16(label: "Attack", stat: $statAtk, ev: $evAtk)
                IVCalcRow16(label: "Defense", stat: $statDef, ev: $evDef)
                IVCalcRow16(label: "Sp. Atk", stat: $statSpAtk, ev: $evSpAtk)
                IVCalcRow16(label: "Sp. Def", stat: $statSpDef, ev: $evSpDef)
                IVCalcRow16(label: "Speed", stat: $statSpeed, ev: $evSpeed)
            }
        }
    }

    private var calculateButton: some View {
        Button {
            guard let pkmn = selectedPokemon else { return }
            // PokeFinder's formula uses base stats without EVs in the stat formula
            // Our stats already include EVs from in-game, so pass them as-is
            let baseStats: [UInt8] = [UInt8(pkmn.baseHP), UInt8(pkmn.baseAtk), UInt8(pkmn.baseDef),
                                       UInt8(pkmn.baseSpAtk), UInt8(pkmn.baseSpDef), UInt8(pkmn.baseSpeed)]
            let stats: [[UInt16]] = [[statHP, statAtk, statDef, statSpAtk, statSpDef, statSpeed]]
            results = pfCalculateIVRange(baseStats: baseStats, stats: stats, levels: [level], nature: natureIndex)
        } label: {
            Label("Calculate IVs", systemImage: "function")
                .frame(maxWidth: .infinity).padding()
                .background(Color.accentColor).foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private var resultsSection: some View {
        Group {
            if !results.isEmpty {
                RNGSection(title: "Results", icon: "checkmark.circle") {
                    ForEach(results) { r in
                        HStack {
                            Text(r.statName).frame(width: 80, alignment: .leading)
                            Spacer()
                            if r.possibleIVs.isEmpty {
                                Text("Invalid").foregroundStyle(.red).bold()
                            } else {
                                Text(r.displayRange)
                                    .font(.system(.body, design: .monospaced)).bold()
                                    .foregroundStyle(ivColor(r.possibleIVs))
                            }
                        }
                    }
                }
            }
        }
    }

    private func ivColor(_ ivs: [UInt8]) -> Color {
        guard let best = ivs.last else { return .primary }
        if best == 31 { return .green }
        if best == 0 { return .red }
        if best >= 28 { return .blue }
        return .primary
    }
}

// ============================================================================
// MARK: - IV to PID View (PokeFinder feature)
// ============================================================================

struct IVToPIDView: View {
    @State private var hp: UInt8 = 31
    @State private var atk: UInt8 = 31
    @State private var def: UInt8 = 31
    @State private var spa: UInt8 = 31
    @State private var spd: UInt8 = 31
    @State private var spe: UInt8 = 31
    @State private var nature: UInt8 = 0
    @State private var tid: UInt16 = 0
    @State private var results: [LCRNGReverse.IVToPIDResult] = []

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                RNGSection(title: "IVs", icon: "number.square") {
                    IVSliderRow8(label: "HP", value: $hp)
                    IVSliderRow8(label: "Attack", value: $atk)
                    IVSliderRow8(label: "Defense", value: $def)
                    IVSliderRow8(label: "Sp. Atk", value: $spa)
                    IVSliderRow8(label: "Sp. Def", value: $spd)
                    IVSliderRow8(label: "Speed", value: $spe)
                }

                RNGSection(title: "Trainer Info", icon: "person") {
                    HStack {
                        Text("Nature (0-24)")
                        Spacer()
                        TextField("", value: $nature, format: .number)
                            .textFieldStyle(.roundedBorder).frame(width: 60)
                    }
                    HStack {
                        Text("Trainer ID")
                        Spacer()
                        TextField("", value: $tid, format: .number)
                            .textFieldStyle(.roundedBorder).frame(width: 80)
                    }
                }

                Button {
                    results = LCRNGReverse.calculatePIDs(hp: hp, atk: atk, def: def,
                                                          spa: spa, spd: spd, spe: spe,
                                                          nature: nature, tid: tid)
                } label: {
                    Label("Find PIDs", systemImage: "magnifyingglass")
                        .frame(maxWidth: .infinity).padding()
                        .background(Color.accentColor).foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                if !results.isEmpty {
                    RNGSection(title: "Results (\(results.count))", icon: "list.bullet") {
                        ForEach(results) { r in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(r.methodName).font(.caption).bold()
                                    Spacer()
                                    Text("PID: \(String(format: "%08X", r.pid))")
                                        .font(.system(.caption, design: .monospaced))
                                }
                                HStack {
                                    Text("Seed: \(String(format: "%08X", r.seed))")
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text("SID: \(r.sid)")
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Divider()
                        }
                    }
                } else if !results.isEmpty {
                    Text("No results found").foregroundStyle(.secondary)
                }
            }.padding()
        }
    }
}

// ============================================================================
// MARK: - Hidden Power Calculator View
// ============================================================================

struct HiddenPowerCalcView: View {
    @State private var ivHP = 31; @State private var ivAtk = 31; @State private var ivDef = 31
    @State private var ivSpAtk = 31; @State private var ivSpDef = 31; @State private var ivSpeed = 31

    private var hpType: String {
        calculateHiddenPowerType(ivHP: ivHP, ivAtk: ivAtk, ivDef: ivDef,
                                  ivSpeed: ivSpeed, ivSpAtk: ivSpAtk, ivSpDef: ivSpDef)
    }
    private var hpPower: Int {
        calculateHiddenPowerBasePower(ivHP: ivHP, ivAtk: ivAtk, ivDef: ivDef,
                                      ivSpeed: ivSpeed, ivSpAtk: ivSpAtk, ivSpDef: ivSpDef)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                RNGSection(title: "IVs", icon: "number.square") {
                    IVSliderRow(label: "HP", value: $ivHP)
                    IVSliderRow(label: "Attack", value: $ivAtk)
                    IVSliderRow(label: "Defense", value: $ivDef)
                    IVSliderRow(label: "Sp. Atk", value: $ivSpAtk)
                    IVSliderRow(label: "Sp. Def", value: $ivSpDef)
                    IVSliderRow(label: "Speed", value: $ivSpeed)
                }

                RNGSection(title: "Hidden Power", icon: "questionmark.diamond") {
                    HStack {
                        Text("Type"); Spacer()
                        Text(hpType).bold().padding(.horizontal, 12).padding(.vertical, 4)
                            .background(typeColor(hpType).opacity(0.2)).clipShape(Capsule())
                    }
                    HStack {
                        Text("Base Power (Gen V-VI)"); Spacer()
                        Text("\(hpPower)").bold().font(.system(.body, design: .monospaced))
                    }
                    Text("Note: In Gen VII+, Hidden Power always has 60 base power.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                RNGSection(title: "Common Hidden Power IVs", icon: "table") {
                    VStack(spacing: 6) {
                        hpPreset("Fire", ivs: "31/30/31/30/31/30")
                        hpPreset("Ice", ivs: "31/30/30/31/31/31")
                        hpPreset("Grass", ivs: "31/30/31/30/31/30")
                        hpPreset("Electric", ivs: "31/31/31/30/31/31")
                        hpPreset("Ground", ivs: "31/31/31/30/30/31")
                        hpPreset("Fighting", ivs: "31/31/30/30/30/30")
                        hpPreset("Flying", ivs: "30/30/30/30/30/31")
                    }
                }
            }.padding()
        }
    }

    private func hpPreset(_ type: String, ivs: String) -> some View {
        HStack {
            Text(type).frame(width: 80, alignment: .leading).foregroundStyle(typeColor(type))
            Spacer()
            Text(ivs).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
        }
    }
}

// ============================================================================
// MARK: - Finder Root View
// ============================================================================

struct FinderRootView: View {
    var switchToTimer: () -> Void

    @State private var generation: FinderGeneration = .gen3
    @State private var mode: FinderMode = .searcher
    @State private var method: FinderMethod = .method1
    @State private var lead: FinderLead = .none
    @State private var syncNature: UInt8 = 0

    // Profile
    @State private var tid: UInt16 = 0
    @State private var sid: UInt16 = 0
    @State private var savedProfiles: [FinderProfile] = FinderProfileStore.load()
    @State private var selectedProfileID: UUID? = FinderProfileStore.lastProfileID
    @State private var showSaveAlert = false
    @State private var newProfileName = ""

    // Encounter
    @State private var selectedGame: FinderGameVersion = .emerald
    @State private var encounterMode: EncounterMode = .static_
    @State private var encounterCategory: StaticEncounterCategory = .legends
    @State private var selectedEncounter: StaticEncounter?
    @State private var selectedLocation: String = ""
    @State private var selectedEncounterType: EncounterType = .grass

    enum EncounterMode: String, CaseIterable, Identifiable {
        case static_ = "Static"
        case wild = "Wild"
        var id: String { rawValue }
    }

    // Searcher IV ranges
    @State private var minHP: UInt8 = 0; @State private var maxHP: UInt8 = 31
    @State private var minAtk: UInt8 = 0; @State private var maxAtk: UInt8 = 31
    @State private var minDef: UInt8 = 0; @State private var maxDef: UInt8 = 31
    @State private var minSpA: UInt8 = 0; @State private var maxSpA: UInt8 = 31
    @State private var minSpD: UInt8 = 0; @State private var maxSpD: UInt8 = 31
    @State private var minSpe: UInt8 = 0; @State private var maxSpe: UInt8 = 31

    // Gen 4 delay range
    @State private var minDelay: UInt16 = 500
    @State private var maxDelay: UInt16 = 10000

    // Generator inputs
    @State private var genSeedText: String = ""
    @State private var genInitAdvance: Int = 0
    @State private var genMaxAdvance: Int = 10000

    // Filters
    @State private var selectedNatures: Set<UInt8> = []
    @State private var shinyOnly: Bool = false

    // State
    @State private var searchResults: [StaticSearchResult] = []
    @State private var searchTask: Task<Void, Never>?
    private var isSearching: Bool { searchTask != nil }
    @State private var selectedResult: StaticSearchResult?

    enum FinderMode: String, CaseIterable, Identifiable {
        case searcher = "Searcher"
        case generator = "Generator"
        var id: String { rawValue }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Generation picker
                Picker("Generation", selection: $generation) {
                    ForEach(FinderGeneration.allCases) { g in Text(g.rawValue).tag(g) }
                }
                .pickerStyle(.segmented)
                .onChange(of: generation) {
                    let available = FinderMethod.methods(for: generation)
                    if !available.contains(method) { method = available[0] }
                    let games = FinderGameVersion.games(for: generation)
                    if !games.contains(selectedGame) { selectedGame = games[0] }
                    let cats = StaticEncounterData.categories(for: selectedGame)
                    if !cats.contains(encounterCategory) { encounterCategory = cats.first ?? .legends }
                    selectedEncounter = nil
                }

                // Mode picker
                Picker("Mode", selection: $mode) {
                    ForEach(FinderMode.allCases) { m in Text(m.rawValue).tag(m) }
                }
                .pickerStyle(.segmented)

                // Encounter
                RNGSection(title: "Encounter", icon: "sparkles") {
                    Picker("Game", selection: $selectedGame) {
                        ForEach(FinderGameVersion.games(for: generation)) { g in
                            Text(g.rawValue).tag(g)
                        }
                    }
                    .onChange(of: selectedGame) {
                        let cats = StaticEncounterData.categories(for: selectedGame)
                        if !cats.contains(encounterCategory) {
                            encounterCategory = cats.first ?? .legends
                        }
                        selectedEncounter = nil
                        let locs = WildEncounterData.locationNames(for: selectedGame)
                        if !locs.contains(selectedLocation) {
                            selectedLocation = locs.first ?? ""
                        }
                    }

                    Picker("Type", selection: $encounterMode) {
                        ForEach(EncounterMode.allCases) { m in
                            Text(m.rawValue).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)

                    if encounterMode == .static_ {
                        let categories = StaticEncounterData.categories(for: selectedGame)
                        if !categories.isEmpty {
                            Picker("Category", selection: $encounterCategory) {
                                ForEach(categories) { cat in
                                    Text(cat.rawValue).tag(cat)
                                }
                            }
                            .onChange(of: encounterCategory) {
                                selectedEncounter = nil
                            }

                            let encounters = StaticEncounterData.encounters(for: selectedGame, category: encounterCategory)
                            if !encounters.isEmpty {
                                Picker("Pokemon", selection: $selectedEncounter) {
                                    Text("None").tag(StaticEncounter?.none)
                                    ForEach(encounters) { e in
                                        Text("\(e.speciesName) Lv\(e.level)").tag(StaticEncounter?.some(e))
                                    }
                                }
                            }
                        }

                        if let enc = selectedEncounter {
                            encounterInfoCard(name: enc.speciesName, level: enc.level,
                                              game: selectedGame.rawValue, method: enc.method.rawValue)
                        }
                    } else {
                        // Wild encounters
                        let locations = WildEncounterData.locationNames(for: selectedGame)
                        if !locations.isEmpty {
                            Picker("Location", selection: $selectedLocation) {
                                ForEach(locations, id: \.self) { loc in
                                    Text(loc).tag(loc)
                                }
                            }
                            .onAppear {
                                if selectedLocation.isEmpty {
                                    selectedLocation = locations.first ?? ""
                                }
                            }

                            let types = WildEncounterData.encounterTypes(for: selectedGame, location: selectedLocation)
                            if types.count > 1 {
                                Picker("Method", selection: $selectedEncounterType) {
                                    ForEach(types) { t in
                                        Text(t.rawValue).tag(t)
                                    }
                                }
                            }

                            if let route = WildEncounterData.wildEncounter(for: selectedGame, location: selectedLocation, type: selectedEncounterType) {
                                wildSlotTable(route: route)
                            }
                        } else {
                            Text("No wild data for \(selectedGame.rawValue)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }

                // Profile
                RNGSection(title: "Trainer", icon: "person") {
                    if !savedProfiles.isEmpty {
                        Picker("Profile", selection: $selectedProfileID) {
                            Text("None").tag(UUID?.none)
                            ForEach(savedProfiles) { p in
                                Text("\(p.name) (\(p.tid)/\(p.sid))").tag(UUID?.some(p.id))
                            }
                        }
                        .onChange(of: selectedProfileID) {
                            if let pid = selectedProfileID,
                               let profile = savedProfiles.first(where: { $0.id == pid }) {
                                tid = profile.tid
                                sid = profile.sid
                            }
                            FinderProfileStore.lastProfileID = selectedProfileID
                        }
                    }

                    FinderUInt16Field(label: "TID", value: $tid)
                    FinderUInt16Field(label: "SID", value: $sid)

                    HStack {
                        Button {
                            newProfileName = ""
                            showSaveAlert = true
                        } label: {
                            Label("Save Profile", systemImage: "plus.circle")
                        }
                        .buttonStyle(.borderless)

                        Spacer()

                        if let pid = selectedProfileID,
                           savedProfiles.contains(where: { $0.id == pid }) {
                            Button(role: .destructive) {
                                savedProfiles.removeAll { $0.id == pid }
                                selectedProfileID = nil
                                FinderProfileStore.save(savedProfiles)
                                FinderProfileStore.lastProfileID = nil
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }

                // Method
                RNGSection(title: "Method", icon: "cpu") {
                    Picker("Method", selection: $method) {
                        ForEach(FinderMethod.methods(for: generation)) { m in
                            Text(m.rawValue).tag(m)
                        }
                    }
                    if generation == .gen4 && (method == .methodJ || method == .methodK) {
                        Picker("Lead Ability", selection: $lead) {
                            ForEach(FinderLead.allCases) { l in Text(l.rawValue).tag(l) }
                        }
                        if lead == .synchronize {
                            Picker("Sync Nature", selection: $syncNature) {
                                ForEach(0..<25, id: \.self) { i in
                                    Text(pfNatureNames[i]).tag(UInt8(i))
                                }
                            }
                        }
                    }
                }

                if mode == .searcher {
                    searcherInputs
                } else {
                    generatorInputs
                }

                // Nature filter
                FinderNatureGrid(selected: $selectedNatures)

                // Shiny toggle
                Toggle("Shiny Only", isOn: $shinyOnly)
                    .padding(.horizontal)

                // Search / Stop button
                if isSearching {
                    Button {
                        searchTask?.cancel()
                        searchTask = nil
                    } label: {
                        Label("Stop (\(searchResults.count) found)",
                              systemImage: "stop.fill")
                            .frame(maxWidth: .infinity).padding()
                            .background(Color.red)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                } else {
                    Button {
                        startSearch()
                    } label: {
                        Label(mode == .searcher ? "Search" : "Generate",
                              systemImage: "magnifyingglass")
                            .frame(maxWidth: .infinity).padding()
                            .background(Color.accentColor)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }

                if !searchResults.isEmpty {
                    RNGSection(title: "Results (\(searchResults.count))", icon: "list.bullet") {
                        ForEach(searchResults.prefix(500)) { r in
                            Button { selectedResult = r } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text("Seed: \(r.seedHex)")
                                            .font(.system(.caption, design: .monospaced))
                                        Spacer()
                                        Text("Adv: \(r.advances)")
                                            .font(.system(.caption, design: .monospaced))
                                    }
                                    HStack {
                                        Text("PID: \(r.pidHex)")
                                            .font(.system(.caption2, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        Text(r.natureName).font(.caption2).bold()
                                        if r.shiny {
                                            Image(systemName: "star.fill")
                                                .font(.caption2).foregroundStyle(.yellow)
                                        }
                                    }
                                    Text("IVs: \(r.ivSummary)")
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            Divider()
                        }
                    }
                }
            }
            .padding()
        }
        .navigationDestination(item: $selectedResult) { result in
            SeedToTimeView(result: result, generation: generation,
                           tid: tid, sid: sid, method: method)
        }
        .alert("Save Profile", isPresented: $showSaveAlert) {
            TextField("Profile name", text: $newProfileName)
            Button("Save") {
                let name = newProfileName.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { return }
                let profile = FinderProfile(name: name, tid: tid, sid: sid)
                savedProfiles.append(profile)
                selectedProfileID = profile.id
                FinderProfileStore.save(savedProfiles)
                FinderProfileStore.lastProfileID = profile.id
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Enter a name for TID \(tid) / SID \(sid)")
        }
    }

    // MARK: Encounter Helpers

    private func encounterInfoCard(name: String, level: UInt8, game: String, method: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "target")
                .foregroundStyle(.orange)
            Text("\(name) Lv\(level)")
                .font(.callout).bold()
            Text("(\(game), \(method))")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.vertical, 4)
    }

    private func wildSlotTable(route: WildEncounterRoute) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(route.slots) { slot in
                HStack {
                    Text(slot.slotRate)
                        .font(.system(.caption2, design: .monospaced))
                        .frame(width: 36, alignment: .trailing)
                        .foregroundStyle(.secondary)
                    Text(slot.speciesName)
                        .font(.caption)
                    Spacer()
                    if slot.minLevel == slot.maxLevel {
                        Text("Lv\(slot.minLevel)")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Lv\(slot.minLevel)-\(slot.maxLevel)")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: Searcher Inputs

    private var searcherInputs: some View {
        Group {
            RNGSection(title: "IV Ranges", icon: "number.square") {
                FinderIVRangeRow(label: "HP", min: $minHP, max: $maxHP)
                FinderIVRangeRow(label: "Attack", min: $minAtk, max: $maxAtk)
                FinderIVRangeRow(label: "Defense", min: $minDef, max: $maxDef)
                FinderIVRangeRow(label: "Sp. Atk", min: $minSpA, max: $maxSpA)
                FinderIVRangeRow(label: "Sp. Def", min: $minSpD, max: $maxSpD)
                FinderIVRangeRow(label: "Speed", min: $minSpe, max: $maxSpe)
            }

            if generation == .gen4 {
                RNGSection(title: "Delay Range", icon: "clock") {
                    FinderUInt16Field(label: "Min Delay", value: $minDelay)
                    FinderUInt16Field(label: "Max Delay", value: $maxDelay)
                }
            }
        }
    }

    // MARK: Generator Inputs

    private var generatorInputs: some View {
        RNGSection(title: "Seed & Advances", icon: "number") {
            HStack {
                Text("Seed (hex)")
                Spacer()
                TextField("e.g. 1A2B3C4D", text: $genSeedText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 140)
                    .multilineTextAlignment(.trailing)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.characters)
                    #endif
            }
            RNGIntField(label: "Initial Advance", value: $genInitAdvance)
            RNGIntField(label: "Max Advance", value: $genMaxAdvance)
        }
    }

    // MARK: Search Logic

    private func startSearch() {
        searchResults = []

        // Capture all @State values before entering task
        let gen = generation
        let m = mode
        let meth = method
        let natFilter = selectedNatures
        let tID = tid, sID = sid
        let shiny = shinyOnly
        let hpMin = minHP, hpMax = maxHP
        let atkMin = minAtk, atkMax = maxAtk
        let defMin = minDef, defMax = maxDef
        let spaMin = minSpA, spaMax = maxSpA
        let spdMin = minSpD, spdMax = maxSpD
        let speMin = minSpe, speMax = maxSpe
        let delMin = minDelay, delMax = maxDelay
        let ld = lead, sNat = syncNature
        let seedVal = UInt32(genSeedText, radix: 16) ?? 0
        let initAdv = UInt32(genInitAdvance)
        let maxAdv = UInt32(genMaxAdvance)

        let stream = AsyncStream<StaticSearchResult> { continuation in
            let work = Task.detached {
                if m == .searcher {
                    if gen == .gen3 {
                        staticSearchGen3Streaming(
                            minIVs: (hpMin, atkMin, defMin, spaMin, spdMin, speMin),
                            maxIVs: (hpMax, atkMax, defMax, spaMax, spdMax, speMax),
                            natures: natFilter, tid: tID, sid: sID,
                            shinyOnly: shiny, method: meth
                        ) { continuation.yield($0) }
                    } else {
                        staticSearchGen4Streaming(
                            minIVs: (hpMin, atkMin, defMin, spaMin, spdMin, speMin),
                            maxIVs: (hpMax, atkMax, defMax, spaMax, spdMax, speMax),
                            natures: natFilter, tid: tID, sid: sID,
                            shinyOnly: shiny, method: meth,
                            minDelay: delMin, maxDelay: delMax
                        ) { continuation.yield($0) }
                    }
                } else {
                    if gen == .gen3 {
                        staticGenerateGen3Streaming(
                            seed: seedVal, initialAdvance: initAdv,
                            maxAdvance: maxAdv,
                            natures: natFilter, tid: tID, sid: sID,
                            shinyOnly: shiny, method: meth
                        ) { continuation.yield($0) }
                    } else {
                        staticGenerateGen4Streaming(
                            seed: seedVal, initialAdvance: initAdv,
                            maxAdvance: maxAdv,
                            natures: natFilter, tid: tID, sid: sID,
                            shinyOnly: shiny, method: meth,
                            lead: ld, syncNature: sNat
                        ) { continuation.yield($0) }
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in work.cancel() }
        }

        searchTask = Task {
            for await result in stream {
                searchResults.append(result)
            }
            searchTask = nil
        }
    }
}

// ============================================================================
// MARK: - Seed to Time View
// ============================================================================

struct SeedToTimeView: View {
    let result: StaticSearchResult
    let generation: FinderGeneration
    let tid: UInt16
    let sid: UInt16
    let method: FinderMethod

    @State private var timeResults3: [SeedToTimeResult3] = []
    @State private var timeResults4: [SeedToTimeResult4] = []
    @State private var originSeed: UInt16 = 0
    @State private var advances: UInt32 = 0
    @State private var isComputing = false

    @Environment(\.dismiss) private var dismiss

    // Verification
    @State private var showVerify = false
    @State private var verifyHP: UInt8 = 0
    @State private var verifyAtk: UInt8 = 0
    @State private var verifyDef: UInt8 = 0
    @State private var verifySpA: UInt8 = 0
    @State private var verifySpD: UInt8 = 0
    @State private var verifySpe: UInt8 = 0
    @State private var verifyNature: UInt8 = 0
    @State private var verificationResult: SeedVerificationResult?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                targetSummary
                timeResultsSection
                verifySection
            }
            .padding()
        }
        .navigationTitle("Seed to Time")
        .task { await computeTimes() }
    }

    private var targetSummary: some View {
        Group {
            RNGSection(title: "Target", icon: "target") {
                LabeledContent("Seed", value: result.seedHex)
                    .font(.system(.body, design: .monospaced))
                LabeledContent("PID", value: result.pidHex)
                    .font(.system(.body, design: .monospaced))
                LabeledContent("IVs", value: result.ivSummary)
                    .font(.system(.body, design: .monospaced))
                LabeledContent("Nature", value: result.natureName)
                LabeledContent("Advances", value: "\(result.advances)")
                if result.shiny {
                    HStack {
                        Text("Shiny")
                        Spacer()
                        Image(systemName: "star.fill").foregroundStyle(.yellow)
                    }
                }
            }

            if generation == .gen3 {
                RNGSection(title: "Origin Seed", icon: "arrow.uturn.backward") {
                    LabeledContent("16-bit Seed", value: String(format: "%04X", originSeed))
                        .font(.system(.body, design: .monospaced))
                    LabeledContent("Advances", value: "\(advances)")
                }
            }
        }
    }

    @ViewBuilder
    private var timeResultsSection: some View {
        if isComputing {
            ProgressView("Computing times...").padding()
        }

        if generation == .gen3 && !timeResults3.isEmpty {
            gen3TimeSection
        }

        if generation == .gen4 && !timeResults4.isEmpty {
            gen4TimeSection
        }

        if !isComputing && (
            (generation == .gen3 && timeResults3.isEmpty) ||
            (generation == .gen4 && timeResults4.isEmpty)
        ) {
            Text("No date/time combos found for this seed.")
                .foregroundStyle(.secondary)
        }
    }

    private var verifySection: some View {
        RNGSection(title: "Verify Catch", icon: "checkmark.shield") {
            DisclosureGroup("Enter Caught Pokemon IVs", isExpanded: $showVerify) {
                VStack(spacing: 8) {
                    IVSliderRow8(label: "HP", value: $verifyHP)
                    IVSliderRow8(label: "Attack", value: $verifyAtk)
                    IVSliderRow8(label: "Defense", value: $verifyDef)
                    IVSliderRow8(label: "Sp. Atk", value: $verifySpA)
                    IVSliderRow8(label: "Sp. Def", value: $verifySpD)
                    IVSliderRow8(label: "Speed", value: $verifySpe)

                    Picker("Nature", selection: $verifyNature) {
                        ForEach(0..<25, id: \.self) { i in
                            Text(pfNatureNames[i]).tag(UInt8(i))
                        }
                    }

                    Button {
                        verificationResult = verifySeedFromIVs(
                            caughtHP: verifyHP, caughtAtk: verifyAtk,
                            caughtDef: verifyDef, caughtSpA: verifySpA,
                            caughtSpD: verifySpD, caughtSpe: verifySpe,
                            caughtNature: verifyNature,
                            tid: tid, targetSeed: result.seed,
                            method: method
                        )
                    } label: {
                        Label("Verify", systemImage: "checkmark.circle")
                            .frame(maxWidth: .infinity).padding()
                            .background(Color.accentColor).foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    if let vr = verificationResult {
                        VStack(alignment: .leading, spacing: 4) {
                            LabeledContent("Actual Seed", value: String(format: "%08X", vr.actualSeed))
                                .font(.system(.body, design: .monospaced))
                            LabeledContent("Target Seed", value: String(format: "%08X", vr.targetSeed))
                                .font(.system(.body, design: .monospaced))
                            HStack {
                                Text("Delay Delta")
                                Spacer()
                                Text("\(vr.delayDelta > 0 ? "+" : "")\(vr.delayDelta)")
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundStyle(vr.delayDelta == 0 ? .green : .red)
                            }
                        }
                        .padding(.top, 8)
                    }
                }
            }
        }
    }

    private var gen3TimeSection: some View {
        SeedToTimeListGen3(
            times: timeResults3,
            totalCount: timeResults3.count,
            onSelect: { timeText in sendToTimerGen3(advances: advances, timeText: timeText) }
        )
    }

    private var gen4TimeSection: some View {
        SeedToTimeListGen4(
            times: timeResults4,
            totalCount: timeResults4.count,
            onSelect: { delay, second, timeText in sendToTimerGen4(delay: delay, second: second, timeText: timeText) }
        )
    }

    private func computeTimes() async {
        isComputing = true
        let gen = generation
        let seedVal = result.seed
        if gen == .gen3 {
            let r = await Task.detached {
                return seedToTimeGen3(seed: seedVal)
            }.value
            originSeed = r.originSeed
            advances = r.advances
            timeResults3 = r.times
        } else {
            let r = await Task.detached {
                return seedToTimeGen4(seed: seedVal)
            }.value
            timeResults4 = r
        }
        isComputing = false
    }

    private func sendToTimerGen3(advances: UInt32, timeText: String) {
        let bridge = FinderTimerBridge.shared
        bridge.pendingGen = .gen3
        bridge.pendingTargetFrame = Int(advances)
        bridge.selectedTime = timeText
        bridge.selectedSeed = result.seedHex
        bridge.shouldSwitchToTimer = true
        dismiss()
    }

    private func sendToTimerGen4(delay: Int, second: Int, timeText: String) {
        let bridge = FinderTimerBridge.shared
        bridge.pendingGen = .gen4
        bridge.pendingTargetDelay = delay
        bridge.pendingTargetSecond = second
        bridge.selectedTime = timeText
        bridge.selectedSeed = result.seedHex
        bridge.shouldSwitchToTimer = true
        dismiss()
    }
}

// Make StaticSearchResult Hashable for navigationDestination
extension StaticSearchResult: Hashable {
    static func == (lhs: StaticSearchResult, rhs: StaticSearchResult) -> Bool {
        lhs.id == rhs.id
    }
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// ============================================================================
// MARK: - Seed to Time List Views (extracted for type checker)
// ============================================================================

struct SeedToTimeListGen3: View {
    let times: [SeedToTimeResult3]
    let totalCount: Int
    let onSelect: (String) -> Void

    private var limited: ArraySlice<SeedToTimeResult3> {
        times.prefix(100)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Date/Time Combos (\(totalCount))", systemImage: "calendar")
                .font(.headline)
            Divider()
            ForEach(limited) { t in
                SeedToTimeRow3(time: t, onSelect: onSelect)
            }
        }
        .padding()
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
    }
}

private struct SeedToTimeRow3: View {
    let time: SeedToTimeResult3
    let onSelect: (String) -> Void
    var body: some View {
        Button { onSelect(time.displayTime) } label: {
            HStack {
                Text(time.displayTime)
                    .font(.system(.body, design: .monospaced))
                Spacer()
                Image(systemName: "timer")
                    .foregroundColor(.accentColor)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct SeedToTimeListGen4: View {
    let times: [SeedToTimeResult4]
    let totalCount: Int
    let onSelect: (Int, Int, String) -> Void

    private var limited: ArraySlice<SeedToTimeResult4> {
        times.prefix(100)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Date/Time Combos (\(totalCount))", systemImage: "calendar")
                .font(.headline)
            Divider()
            ForEach(limited) { t in
                SeedToTimeRow4(time: t, onSelect: onSelect)
            }
        }
        .padding()
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
    }
}

private struct SeedToTimeRow4: View {
    let time: SeedToTimeResult4
    let onSelect: (Int, Int, String) -> Void
    var body: some View {
        Button { onSelect(Int(time.delay), time.second, time.displayTime) } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(time.displayTime)
                    .font(.system(.caption, design: .monospaced))
            }
        }
        .buttonStyle(.plain)
        Divider()
    }
}

// ============================================================================
// MARK: - Finder Reusable Components
// ============================================================================

struct FinderIVRangeRow: View {
    let label: String
    @Binding var min: UInt8
    @Binding var max: UInt8

    var body: some View {
        HStack(spacing: 8) {
            Text(label).frame(width: 70, alignment: .leading)
            TextField("Min", value: $min, format: .number)
                .textFieldStyle(.roundedBorder).frame(width: 50)
                .multilineTextAlignment(.trailing)
            Text("–")
            TextField("Max", value: $max, format: .number)
                .textFieldStyle(.roundedBorder).frame(width: 50)
                .multilineTextAlignment(.trailing)
            Spacer()
        }
    }
}

struct FinderUInt16Field: View {
    let label: String
    @Binding var value: UInt16
    @State private var text: String = ""
    var body: some View {
        HStack {
            Text(label)
            Spacer()
            TextField("00000", text: $text)
                .textFieldStyle(.roundedBorder).frame(width: 100).multilineTextAlignment(.trailing)
                #if os(iOS)
                .keyboardType(.numberPad)
                #endif
                .onAppear { text = String(value) }
                .onChange(of: text) {
                    let filtered = String(text.prefix(5).filter { $0.isNumber })
                    if filtered != text { text = filtered }
                    if let n = UInt16(filtered), n <= 65535 {
                        value = n
                    }
                }
                .onChange(of: value) {
                    let s = String(value)
                    if text != s { text = s }
                }
        }
    }
}

struct FinderNatureGrid: View {
    @Binding var selected: Set<UInt8>

    var body: some View {
        RNGSection(title: "Nature Filter", icon: "leaf") {
            Text("Tap natures to filter (none = all)")
                .font(.caption).foregroundStyle(.secondary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 6) {
                ForEach(0..<25, id: \.self) { i in
                    let idx = UInt8(i)
                    Button {
                        if selected.contains(idx) { selected.remove(idx) }
                        else { selected.insert(idx) }
                    } label: {
                        Text(pfNatureNames[i])
                            .font(.caption2)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .padding(.horizontal, 4).padding(.vertical, 3)
                            .frame(maxWidth: .infinity)
                            .background(selected.contains(idx) ? Color.accentColor : Color.gray.opacity(0.2))
                            .foregroundStyle(selected.contains(idx) ? .white : .primary)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            if !selected.isEmpty {
                Button("Clear All") { selected.removeAll() }
                    .font(.caption)
            }
        }
    }
}

// ============================================================================
// MARK: - Credits View
// ============================================================================

struct RNGCreditsView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Image(systemName: "dice").font(.system(size: 48)).foregroundColor(.accentColor)
                    Text("RNG Tools").font(.title2.bold())
                    Text("Pokemon RNG manipulation utilities").font(.subheadline).foregroundStyle(.secondary)
                }.padding(.top, 24)

                RNGSection(title: "Timer", icon: "timer") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Ported from EonTimer").font(.headline)
                        Text("by DasAmpharos (MIT License)").foregroundStyle(.secondary)
                        Text("Precision timer for Pokemon RNG manipulation. Supports Gen 3/4/5 and custom multi-phase timers with calibration. Timer phase calculations, calibration logic, console-specific framerates, and banker's rounding are faithfully ported from the TypeScript source.")
                            .font(.caption).foregroundStyle(.secondary)
                        Link("github.com/DasAmpharos/EonTimer",
                             destination: URL(string: "https://github.com/DasAmpharos/EonTimer")!)
                            .font(.caption)
                    }
                }

                RNGSection(title: "RNG Calculator", icon: "function") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Ported from PokeFinder").font(.headline)
                        Text("by Admiral_Fish, bumba, and EzPzStreamz (GPLv3)").foregroundStyle(.secondary)
                        Text("IV Calculator with characteristic/hidden power filtering, IV-to-PID reverse calculator using LCRNG meet-in-the-middle attacks, and seed recovery for Method 1/2/4, XD/Colo, and Cute Charm. All algorithms are faithfully ported from the C++ source.")
                            .font(.caption).foregroundStyle(.secondary)
                        Link("github.com/Admiral-Fish/PokeFinder",
                             destination: URL(string: "https://github.com/Admiral-Fish/PokeFinder")!)
                            .font(.caption)
                    }
                }

                RNGSection(title: "Acknowledgments", icon: "heart") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Built on research from the Pokemon RNG community, including insights from RNG Reporter, PPRNG, and 3DSRNG Tool.")
                            .font(.caption).foregroundStyle(.secondary)
                        Text("LCRNG reverse algorithms are based on meet-in-the-middle attacks and Euclidean divisor methods as described on crypto.stackexchange.com.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }.padding()
        }
    }
}

// ============================================================================
// MARK: - Reusable Components
// ============================================================================

struct RNGSection<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon).font(.headline)
            Divider()
            content
        }
        .padding()
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
    }
}

struct RNGIntField: View {
    let label: String
    @Binding var value: Int
    var body: some View {
        HStack {
            Text(label).lineLimit(1).minimumScaleFactor(0.8)
            Spacer()
            TextField("", value: $value, format: .number)
                .textFieldStyle(.roundedBorder).frame(width: 100).multilineTextAlignment(.trailing)
        }
    }
}

struct RNGDoubleField: View {
    let label: String
    @Binding var value: Double
    var body: some View {
        HStack {
            Text(label).lineLimit(1).minimumScaleFactor(0.8)
            Spacer()
            TextField("", value: $value, format: .number)
                .textFieldStyle(.roundedBorder).frame(width: 100).multilineTextAlignment(.trailing)
        }
    }
}

struct RNGOptIntField: View {
    let label: String
    @Binding var value: Int?
    var body: some View {
        HStack {
            Text(label).lineLimit(1).minimumScaleFactor(0.8)
            Spacer()
            TextField("", value: $value, format: .number, prompt: Text("—"))
                .textFieldStyle(.roundedBorder).frame(width: 100).multilineTextAlignment(.trailing)
        }
    }
}

struct IVCalcRow16: View {
    let label: String
    @Binding var stat: UInt16
    @Binding var ev: Int
    var body: some View {
        HStack(spacing: 8) {
            Text(label).frame(width: 70, alignment: .leading)
            TextField("Stat", value: $stat, format: .number)
                .textFieldStyle(.roundedBorder).frame(width: 70)
            Text("EV:").font(.caption).foregroundStyle(.secondary)
            TextField("EV", value: $ev, format: .number)
                .textFieldStyle(.roundedBorder).frame(width: 60)
        }
    }
}

struct IVSliderRow: View {
    let label: String
    @Binding var value: Int
    var body: some View {
        HStack {
            Text(label).frame(width: 70, alignment: .leading)
            Slider(value: Binding(get: { Double(value) }, set: { value = Int($0) }), in: 0...31, step: 1)
            Text("\(value)").frame(width: 30, alignment: .trailing).font(.system(.body, design: .monospaced))
        }
    }
}

struct IVSliderRow8: View {
    let label: String
    @Binding var value: UInt8
    var body: some View {
        HStack {
            Text(label).frame(width: 70, alignment: .leading)
            Slider(value: Binding(get: { Double(value) }, set: { value = UInt8($0) }), in: 0...31, step: 1)
            Text("\(value)").frame(width: 30, alignment: .trailing).font(.system(.body, design: .monospaced))
        }
    }
}

// MARK: - Type Color Helper

private func typeColor(_ type: String) -> Color {
    switch type.lowercased() {
    case "fire": return .red; case "water": return .blue; case "grass": return .green
    case "electric": return .yellow; case "ice": return .cyan; case "fighting": return .brown
    case "poison": return .purple; case "ground": return .brown.opacity(0.7)
    case "flying": return .indigo; case "psychic": return .pink
    case "bug": return .green.opacity(0.7); case "rock": return .brown.opacity(0.5)
    case "ghost": return .purple.opacity(0.7); case "dragon": return .indigo.opacity(0.8)
    case "dark": return .gray; case "steel": return .gray.opacity(0.7)
    default: return .primary
    }
}
