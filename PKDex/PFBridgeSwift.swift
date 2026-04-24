import Foundation

// MARK: - Method/Lead Mappings

enum PFMethod: UInt8 {
    case none = 0
    case method1 = 1
    case method1Reverse = 2
    case method2 = 3
    case method4 = 4
    case xdColo = 5
    case channel = 6
    case eBred = 7
    case eBredSplit = 8
    case eBredAlternate = 9
    case eBredPID = 10
    case rsFRLGBred = 11
    case rsFRLGBredSplit = 12
    case rsFRLGBredAlternate = 13
    case rsFRLGBredMixed = 14
    case cuteCharmDPPt = 15
    case cuteCharmHGSS = 16
    case methodJ = 17
    case methodK = 18
    case honeyTree = 19
    case pokeRadar = 20
    case wondercardIVs = 21
    case method5IVs = 22
    case method5CGear = 23
    case method5 = 24
}

enum PFLead: UInt8 {
    case none = 255
    case synchronize = 0
}

// MARK: - Swift Result Types

struct PFIVToPIDSwift: Identifiable {
    let id = UUID()
    let seed: UInt32
    let pid: UInt32
    let sid: UInt16
    let method: UInt8
}

struct PFPIDToIVSwift: Identifiable {
    let id = UUID()
    let seed: UInt32
    let ivs: [UInt8]
    let method: UInt8
}

struct PFDateTimeSwift: Identifiable, Hashable {
    let id = UUID()
    let year: Int
    let month: Int
    let day: Int
    let hour: Int
    let minute: Int
    let second: Int

    func hash(into hasher: inout Hasher) {
        hasher.combine(year)
        hasher.combine(month)
        hasher.combine(day)
        hasher.combine(hour)
        hasher.combine(minute)
        hasher.combine(second)
    }

    static func == (lhs: PFDateTimeSwift, rhs: PFDateTimeSwift) -> Bool {
        lhs.year == rhs.year && lhs.month == rhs.month && lhs.day == rhs.day &&
        lhs.hour == rhs.hour && lhs.minute == rhs.minute && lhs.second == rhs.second
    }
}

struct PFSeedTime4Swift: Identifiable, Hashable {
    let id = UUID()
    let dateTime: PFDateTimeSwift
    let delay: UInt32

    func hash(into hasher: inout Hasher) {
        hasher.combine(dateTime)
        hasher.combine(delay)
    }

    static func == (lhs: PFSeedTime4Swift, rhs: PFSeedTime4Swift) -> Bool {
        lhs.dateTime == rhs.dateTime && lhs.delay == rhs.delay
    }
}

struct PFGeneratorStateSwift: Identifiable {
    let id = UUID()
    let seed: UInt32
    let pid: UInt32
    let advances: UInt32
    let ivs: [UInt8]
    let nature: UInt8
    let ability: UInt8
    let gender: UInt8
    let shiny: UInt8
    let hiddenPower: UInt8
    let hiddenPowerStrength: UInt8
}

struct PFGeneratorState4Swift: Identifiable {
    let id = UUID()
    let seed: UInt32
    let pid: UInt32
    let advances: UInt32
    let ivs: [UInt8]
    let nature: UInt8
    let ability: UInt8
    let gender: UInt8
    let shiny: UInt8
    let hiddenPower: UInt8
    let hiddenPowerStrength: UInt8
    let call: UInt8
    let chatot: UInt8
}

struct PFSearcherStateSwift: Identifiable {
    let id = UUID()
    let seed: UInt32
    let pid: UInt32
    let ivs: [UInt8]
    let nature: UInt8
    let ability: UInt8
    let gender: UInt8
    let shiny: UInt8
    let hiddenPower: UInt8
    let hiddenPowerStrength: UInt8
}

struct PFSearcherState4Swift: Identifiable {
    let id = UUID()
    let seed: UInt32
    let pid: UInt32
    let advances: UInt32
    let ivs: [UInt8]
    let nature: UInt8
    let ability: UInt8
    let gender: UInt8
    let shiny: UInt8
    let hiddenPower: UInt8
    let hiddenPowerStrength: UInt8
}

// MARK: - Swift Bridge Functions

nonisolated enum PFBridge {

    // MARK: Tools

    static func ivToPID(hp: UInt8, atk: UInt8, def: UInt8,
                         spa: UInt8, spd: UInt8, spe: UInt8,
                         nature: UInt8, tid: UInt16) -> [PFIVToPIDSwift] {
        var count: Int32 = 0
        guard let ptr = pf_ivToPID(hp, atk, def, spa, spd, spe, nature, tid, &count) else {
            return []
        }
        defer { pf_freeResults(ptr) }

        return (0..<Int(count)).map { i in
            let r = ptr[i]
            return PFIVToPIDSwift(seed: r.seed, pid: r.pid, sid: r.sid, method: r.method)
        }
    }

    static func pidToIV(pid: UInt32) -> [PFPIDToIVSwift] {
        var count: Int32 = 0
        guard let ptr = pf_pidToIV(pid, &count) else {
            return []
        }
        defer { pf_freeResults(ptr) }

        return (0..<Int(count)).map { i in
            let r = ptr[i]
            let ivs = withUnsafePointer(to: ptr[i].ivs) { tuple in
                let bound = UnsafeRawPointer(tuple).assumingMemoryBound(to: UInt8.self)
                return Array(UnsafeBufferPointer(start: bound, count: 6))
            }
            return PFPIDToIVSwift(seed: r.seed, ivs: ivs, method: r.method)
        }
    }

    // MARK: Seed To Time

    static func seedToTimeOriginSeed3(seed: UInt32) -> (originSeed: UInt16, advances: UInt32) {
        let result = pf_seedToTimeOriginSeed3(seed)
        return (result.originSeed, result.advances)
    }

    static func seedToTime3(seed: UInt32, year: UInt16) -> [PFDateTimeSwift] {
        var count: Int32 = 0
        guard let ptr = pf_seedToTime3(seed, year, &count) else {
            return []
        }
        defer { pf_freeResults(ptr) }

        return (0..<Int(count)).map { i in
            let r = ptr[i]
            return PFDateTimeSwift(year: Int(r.year), month: Int(r.month), day: Int(r.day),
                                    hour: Int(r.hour), minute: Int(r.minute), second: Int(r.second))
        }
    }

    static func seedToTime4(seed: UInt32, year: UInt16,
                             forceSecond: Bool = false, forcedSecond: UInt8 = 0) -> [PFSeedTime4Swift] {
        var count: Int32 = 0
        guard let ptr = pf_seedToTime4(seed, year, forceSecond, forcedSecond, &count) else {
            return []
        }
        defer { pf_freeResults(ptr) }

        return (0..<Int(count)).map { i in
            let r = ptr[i]
            let dt = PFDateTimeSwift(year: Int(r.dateTime.year), month: Int(r.dateTime.month),
                                      day: Int(r.dateTime.day), hour: Int(r.dateTime.hour),
                                      minute: Int(r.dateTime.minute), second: Int(r.dateTime.second))
            return PFSeedTime4Swift(dateTime: dt, delay: r.delay)
        }
    }

    // MARK: Gen 3 Generator

    static func staticGenerate3(seed: UInt32,
                                 initialAdvances: UInt32,
                                 maxAdvances: UInt32,
                                 offset: UInt32 = 0,
                                 method: PFMethod,
                                 tid: UInt16, sid: UInt16,
                                 game: UInt8 = 0,
                                 deadBattery: Bool = false,
                                 filterGender: UInt8 = 255,
                                 filterAbility: UInt8 = 255,
                                 filterShiny: UInt8 = 255,
                                 ivMin: [UInt8] = [0,0,0,0,0,0],
                                 ivMax: [UInt8] = [31,31,31,31,31,31],
                                 natures: [Bool] = Array(repeating: false, count: 25),
                                 powers: [Bool] = Array(repeating: false, count: 16)) -> [PFGeneratorStateSwift] {
        var count: Int32 = 0
        let ptr = pf_staticGenerate3(seed, initialAdvances, maxAdvances, offset,
                                      method.rawValue, tid, sid, game, deadBattery,
                                      filterGender, filterAbility, filterShiny,
                                      ivMin, ivMax, natures, powers, &count)
        guard let ptr else { return [] }
        defer { pf_freeResults(ptr) }

        return (0..<Int(count)).map { i in
            let r = ptr[i]
            let ivs = [r.ivs.0, r.ivs.1, r.ivs.2, r.ivs.3, r.ivs.4, r.ivs.5]
            return PFGeneratorStateSwift(seed: r.seed, pid: r.pid, advances: r.advances,
                                          ivs: ivs, nature: r.nature, ability: r.ability,
                                          gender: r.gender, shiny: r.shiny,
                                          hiddenPower: r.hiddenPower,
                                          hiddenPowerStrength: r.hiddenPowerStrength)
        }
    }

    // MARK: Gen 3 Searcher

    static func staticSearch3(method: PFMethod,
                               tid: UInt16, sid: UInt16,
                               game: UInt8 = 0,
                               deadBattery: Bool = false,
                               filterGender: UInt8 = 255,
                               filterAbility: UInt8 = 255,
                               filterShiny: UInt8 = 255,
                               ivMin: [UInt8] = [0,0,0,0,0,0],
                               ivMax: [UInt8] = [31,31,31,31,31,31],
                               natures: [Bool] = Array(repeating: false, count: 25),
                               powers: [Bool] = Array(repeating: false, count: 16)) -> [PFSearcherStateSwift] {
        var count: Int32 = 0
        let ptr = pf_staticSearch3(method.rawValue, tid, sid, game, deadBattery,
                                    filterGender, filterAbility, filterShiny,
                                    ivMin, ivMax, natures, powers, &count)
        guard let ptr else { return [] }
        defer { pf_freeResults(ptr) }

        return (0..<Int(count)).map { i in
            let r = ptr[i]
            let ivs = [r.ivs.0, r.ivs.1, r.ivs.2, r.ivs.3, r.ivs.4, r.ivs.5]
            return PFSearcherStateSwift(seed: r.seed, pid: r.pid, ivs: ivs,
                                         nature: r.nature, ability: r.ability,
                                         gender: r.gender, shiny: r.shiny,
                                         hiddenPower: r.hiddenPower,
                                         hiddenPowerStrength: r.hiddenPowerStrength)
        }
    }

    // MARK: Gen 4 Generator

    static func staticGenerate4(seed: UInt32,
                                 initialAdvances: UInt32,
                                 maxAdvances: UInt32,
                                 offset: UInt32 = 0,
                                 method: PFMethod,
                                 lead: PFLead = .none,
                                 tid: UInt16, sid: UInt16,
                                 game: UInt8 = 0,
                                 filterGender: UInt8 = 255,
                                 filterAbility: UInt8 = 255,
                                 filterShiny: UInt8 = 255,
                                 ivMin: [UInt8] = [0,0,0,0,0,0],
                                 ivMax: [UInt8] = [31,31,31,31,31,31],
                                 natures: [Bool] = Array(repeating: false, count: 25),
                                 powers: [Bool] = Array(repeating: false, count: 16)) -> [PFGeneratorState4Swift] {
        var count: Int32 = 0
        let ptr = pf_staticGenerate4(seed, initialAdvances, maxAdvances, offset,
                                      method.rawValue, lead.rawValue, tid, sid, game,
                                      filterGender, filterAbility, filterShiny,
                                      ivMin, ivMax, natures, powers, &count)
        guard let ptr else { return [] }
        defer { pf_freeResults(ptr) }

        return (0..<Int(count)).map { i in
            let r = ptr[i]
            let ivs = [r.ivs.0, r.ivs.1, r.ivs.2, r.ivs.3, r.ivs.4, r.ivs.5]
            return PFGeneratorState4Swift(seed: r.seed, pid: r.pid, advances: r.advances,
                                           ivs: ivs, nature: r.nature, ability: r.ability,
                                           gender: r.gender, shiny: r.shiny,
                                           hiddenPower: r.hiddenPower,
                                           hiddenPowerStrength: r.hiddenPowerStrength,
                                           call: r.call, chatot: r.chatot)
        }
    }

    // MARK: Gen 4 Searcher

    static func staticSearch4(minAdvance: UInt32 = 0,
                               maxAdvance: UInt32 = 0,
                               minDelay: UInt32 = 0,
                               maxDelay: UInt32 = 0,
                               method: PFMethod,
                               lead: PFLead = .none,
                               tid: UInt16, sid: UInt16,
                               game: UInt8 = 0,
                               filterGender: UInt8 = 255,
                               filterAbility: UInt8 = 255,
                               filterShiny: UInt8 = 255,
                               ivMin: [UInt8] = [0,0,0,0,0,0],
                               ivMax: [UInt8] = [31,31,31,31,31,31],
                               natures: [Bool] = Array(repeating: false, count: 25),
                               powers: [Bool] = Array(repeating: false, count: 16)) -> [PFSearcherState4Swift] {
        var count: Int32 = 0
        let ptr = pf_staticSearch4(minAdvance, maxAdvance, minDelay, maxDelay,
                                    method.rawValue, lead.rawValue, tid, sid, game,
                                    filterGender, filterAbility, filterShiny,
                                    ivMin, ivMax, natures, powers, &count)
        guard let ptr else { return [] }
        defer { pf_freeResults(ptr) }

        return (0..<Int(count)).map { i in
            let r = ptr[i]
            let ivs = [r.ivs.0, r.ivs.1, r.ivs.2, r.ivs.3, r.ivs.4, r.ivs.5]
            return PFSearcherState4Swift(seed: r.seed, pid: r.pid, advances: r.advances,
                                          ivs: ivs, nature: r.nature, ability: r.ability,
                                          gender: r.gender, shiny: r.shiny,
                                          hiddenPower: r.hiddenPower,
                                          hiddenPowerStrength: r.hiddenPowerStrength)
        }
    }
}
