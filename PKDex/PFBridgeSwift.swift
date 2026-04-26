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
    case synchronizeEnd = 24
    case cuteCharmF = 25
    case cuteCharmM = 26
    case magnetPull = 27
    case staticLead = 28
    case harvest = 29
    case flashFire = 30
    case stormDrain = 31
    case pressure = 32
    case suctionCups = 33
    case compoundEyes = 34
    case arenaTrap = 35
}

enum PFGame: UInt32 {
    case none = 0
    case ruby = 1
    case sapphire = 2
    case emerald = 4
    case fireRed = 8
    case leafGreen = 16
    case gales = 32
    case colosseum = 64
    case diamond = 128
    case pearl = 256
    case platinum = 512
    case heartGold = 1024
    case soulSilver = 2048
    case black = 4096
    case white = 8192
    case black2 = 16384
    case white2 = 32768
    case sword = 16777216
    case shield = 33554432
    case bd = 67108864
    case sp = 134217728
}

enum PFEncounter: UInt8 {
    case grass = 0
    case grassDark = 1
    case grassRustling = 2
    case rockSmash = 3
    case surfing = 4
    case surfingRippling = 5
    case oldRod = 6
    case goodRod = 7
    case superRod = 8
    case superRodRippling = 9
    case staticEnc = 10
    case honeyTree = 11
    case bugCatchingContest = 12
    case headbutt = 13
    case headbuttAlt = 14
    case headbuttSpecial = 15
    case roamer = 16
    case gift = 17
    case entraLink = 18
    case giftEgg = 19
    case hiddenGrotto = 20

    var displayName: String {
        switch self {
        case .grass: return "Grass"
        case .grassDark: return "Dark Grass"
        case .grassRustling: return "Rustling Grass"
        case .rockSmash: return "Rock Smash"
        case .surfing: return "Surfing"
        case .surfingRippling: return "Rippling Water"
        case .oldRod: return "Old Rod"
        case .goodRod: return "Good Rod"
        case .superRod: return "Super Rod"
        case .superRodRippling: return "Rippling Super Rod"
        case .staticEnc: return "Static"
        case .honeyTree: return "Honey Tree"
        case .bugCatchingContest: return "Bug Catching Contest"
        case .headbutt: return "Headbutt"
        case .headbuttAlt: return "Headbutt (Alt)"
        case .headbuttSpecial: return "Headbutt (Special)"
        case .roamer: return "Roamer"
        case .gift: return "Gift"
        case .entraLink: return "Entralink"
        case .giftEgg: return "Gift Egg"
        case .hiddenGrotto: return "Hidden Grotto"
        }
    }
}

// MARK: - Encounter Types

struct PFSlotSwift: Identifiable {
    let id = UUID()
    let specie: UInt16
    let form: UInt8
    let minLevel: UInt8
    let maxLevel: UInt8
    var specieName: String { PFBridge.specieName(specie) }
}

struct PFEncounterAreaSwift: Identifiable {
    let id = UUID()
    let location: UInt8
    let rate: UInt8
    let encounter: PFEncounter
    let slots: [PFSlotSwift]
    var locationName: String = ""
}

struct PFStaticTemplateSwift: Identifiable {
    let id = UUID()
    let game: UInt32
    let specie: UInt16
    let form: UInt8
    let shiny: UInt8
    let ability: UInt8
    let gender: UInt8
    let level: UInt8
    var specieName: String { PFBridge.specieName(specie) }
}

struct PFWildGeneratorStateSwift: Identifiable {
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
    let encounterSlot: UInt8
    let level: UInt8
    let item: UInt16
    let specie: UInt16
    let form: UInt8
}

struct PFWildSearcherStateSwift: Identifiable {
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
    let encounterSlot: UInt8
    let level: UInt8
    let item: UInt16
    let specie: UInt16
    let form: UInt8
}

struct PFWildGeneratorState4Swift: Identifiable {
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
    let encounterSlot: UInt8
    let level: UInt8
    let item: UInt16
    let specie: UInt16
    let form: UInt8
    let call: UInt8
    let chatot: UInt8
}

struct PFWildSearcherState4Swift: Identifiable {
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
    let encounterSlot: UInt8
    let level: UInt8
    let item: UInt16
    let specie: UInt16
    let form: UInt8
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

    // MARK: Translator

    private static var translatorInitialized = false

    static func initTranslator(locale: String = "en") {
        guard !translatorInitialized else { return }
        pf_initTranslator(locale)
        translatorInitialized = true
    }

    static func specieName(_ specie: UInt16) -> String {
        initTranslator()
        guard specie > 0 else { return "???" }
        guard let cStr = pf_getSpecieName(specie) else { return "???" }
        defer { pf_freeString(cStr) }
        return String(cString: cStr)
    }

    static func abilityName(_ ability: UInt16) -> String {
        initTranslator()
        guard ability > 0 else { return "-" }
        guard let cStr = pf_getAbilityName(ability) else { return "-" }
        defer { pf_freeString(cStr) }
        return String(cString: cStr)
    }

    static func natureName(_ nature: UInt8) -> String {
        initTranslator()
        guard let cStr = pf_getNatureName(nature) else { return "-" }
        defer { pf_freeString(cStr) }
        return String(cString: cStr)
    }

    static func hiddenPowerName(_ power: UInt8) -> String {
        initTranslator()
        guard let cStr = pf_getHiddenPowerName(power) else { return "-" }
        defer { pf_freeString(cStr) }
        return String(cString: cStr)
    }

    static func itemName(_ item: UInt16) -> String {
        initTranslator()
        guard let cStr = pf_getItemName(item) else { return "-" }
        defer { pf_freeString(cStr) }
        return String(cString: cStr)
    }

    static func moveName(_ move: UInt16) -> String {
        initTranslator()
        guard let cStr = pf_getMoveName(move) else { return "-" }
        defer { pf_freeString(cStr) }
        return String(cString: cStr)
    }

    static func allNatureNames() -> [String] {
        initTranslator()
        var count: Int32 = 0
        guard let arr = pf_getNatureNames(&count) else { return [] }
        defer { pf_freeStringArray(arr, count) }
        return (0..<Int(count)).map { String(cString: arr[$0]!) }
    }

    static func allHiddenPowerNames() -> [String] {
        initTranslator()
        var count: Int32 = 0
        guard let arr = pf_getHiddenPowerNames(&count) else { return [] }
        defer { pf_freeStringArray(arr, count) }
        return (0..<Int(count)).map { String(cString: arr[$0]!) }
    }

    static func locationNames(_ locationNums: [UInt16], game: PFGame) -> [String] {
        initTranslator()
        let count = Int32(locationNums.count)
        guard let arr = pf_getLocationNames(locationNums, count, game.rawValue) else { return [] }
        defer { pf_freeStringArray(arr, count) }
        return (0..<Int(count)).map { String(cString: arr[$0]!) }
    }

    // MARK: Encounter Data

    static func getEncounters3(encounter: PFEncounter, game: PFGame,
                                feebasTile: Bool = false) -> [PFEncounterAreaSwift] {
        initTranslator()
        var count: Int32 = 0
        guard let ptr = pf_getEncounters3(encounter.rawValue, game.rawValue,
                                           feebasTile, &count) else { return [] }
        defer { pf_freeResults(ptr) }

        var areas = (0..<Int(count)).map { i -> PFEncounterAreaSwift in
            let r = ptr[i]
            let enc = PFEncounter(rawValue: r.encounter) ?? .grass
            return PFEncounterAreaSwift(location: r.location, rate: r.rate,
                                         encounter: enc, slots: extractSlots(from: r))
        }

        let locationNums = areas.map { UInt16($0.location) }
        let uniqueNums = Array(Set(locationNums))
        let names = locationNames(uniqueNums, game: game)
        let nameMap = Dictionary(uniqueKeysWithValues: zip(uniqueNums, names))
        for i in areas.indices {
            areas[i].locationName = nameMap[UInt16(areas[i].location)] ?? "Unknown"
        }
        return areas
    }

    static func getEncounters4(encounter: PFEncounter, game: PFGame,
                                tid: UInt16, sid: UInt16,
                                time: Int32 = 0, swarm: Bool = false,
                                dual: PFGame = .none,
                                replacement0: UInt16 = 0, replacement1: UInt16 = 0,
                                feebasTile: Bool = false, radar: Bool = false,
                                radio: Int32 = 0,
                                blocks: [UInt8] = [0,0,0,0,0]) -> [PFEncounterAreaSwift] {
        initTranslator()
        var count: Int32 = 0
        guard let ptr = pf_getEncounters4(encounter.rawValue, game.rawValue,
                                           tid, sid, time, swarm,
                                           dual.rawValue, replacement0, replacement1,
                                           feebasTile, radar, radio, blocks, &count) else { return [] }
        defer { pf_freeResults(ptr) }

        var areas = (0..<Int(count)).map { i -> PFEncounterAreaSwift in
            let r = ptr[i]
            let enc = PFEncounter(rawValue: r.encounter) ?? .grass
            return PFEncounterAreaSwift(location: r.location, rate: r.rate,
                                         encounter: enc, slots: extractSlots(from: r))
        }

        let locationNums = areas.map { UInt16($0.location) }
        let uniqueNums = Array(Set(locationNums))
        let names = locationNames(uniqueNums, game: game)
        let nameMap = Dictionary(uniqueKeysWithValues: zip(uniqueNums, names))
        for i in areas.indices {
            areas[i].locationName = nameMap[UInt16(areas[i].location)] ?? "Unknown"
        }
        return areas
    }

    static func getStaticEncounters3(type: Int32) -> [PFStaticTemplateSwift] {
        initTranslator()
        var count: Int32 = 0
        guard let ptr = pf_getStaticEncounters3(type, &count) else { return [] }
        defer { pf_freeResults(ptr) }

        return (0..<Int(count)).map { i in
            let r = ptr[i]
            return PFStaticTemplateSwift(game: r.game, specie: r.specie, form: r.form,
                                          shiny: r.shiny, ability: r.ability,
                                          gender: r.gender, level: r.level)
        }
    }

    static func getStaticEncounters4(type: Int32) -> [PFStaticTemplateSwift] {
        initTranslator()
        var count: Int32 = 0
        guard let ptr = pf_getStaticEncounters4(type, &count) else { return [] }
        defer { pf_freeResults(ptr) }

        return (0..<Int(count)).map { i in
            let r = ptr[i]
            return PFStaticTemplateSwift(game: r.game, specie: r.specie, form: r.form,
                                          shiny: r.shiny, ability: r.ability,
                                          gender: r.gender, level: r.level)
        }
    }

    // MARK: Wild Generators

    static func wildGenerate3(seed: UInt32,
                               initialAdvances: UInt32,
                               maxAdvances: UInt32,
                               offset: UInt32 = 0,
                               method: PFMethod,
                               lead: PFLead = .none,
                               tid: UInt16, sid: UInt16,
                               game: PFGame,
                               deadBattery: Bool = false,
                               feebasTile: Bool = false,
                               encounter: PFEncounter,
                               location: UInt8,
                               filterGender: UInt8 = 255,
                               filterAbility: UInt8 = 255,
                               filterShiny: UInt8 = 255,
                               ivMin: [UInt8] = [0,0,0,0,0,0],
                               ivMax: [UInt8] = [31,31,31,31,31,31],
                               natures: [Bool] = Array(repeating: true, count: 25),
                               powers: [Bool] = Array(repeating: true, count: 16),
                               encounterSlots: [Bool] = Array(repeating: true, count: 12)) -> [PFWildGeneratorStateSwift] {
        var count: Int32 = 0
        let ptr = pf_wildGenerate3(seed, initialAdvances, maxAdvances, offset,
                                    method.rawValue, lead.rawValue, tid, sid,
                                    game.rawValue, deadBattery, feebasTile,
                                    encounter.rawValue, location,
                                    filterGender, filterAbility, filterShiny,
                                    ivMin, ivMax, natures, powers, encounterSlots, &count)
        guard let ptr else { return [] }
        defer { pf_freeResults(ptr) }

        return (0..<Int(count)).map { i in
            let r = ptr[i]
            let ivs = [r.ivs.0, r.ivs.1, r.ivs.2, r.ivs.3, r.ivs.4, r.ivs.5]
            return PFWildGeneratorStateSwift(seed: r.seed, pid: r.pid, advances: r.advances,
                                              ivs: ivs, nature: r.nature, ability: r.ability,
                                              gender: r.gender, shiny: r.shiny,
                                              hiddenPower: r.hiddenPower,
                                              hiddenPowerStrength: r.hiddenPowerStrength,
                                              encounterSlot: r.encounterSlot, level: r.level,
                                              item: r.item, specie: r.specie, form: r.form)
        }
    }

    static func wildSearch3(method: PFMethod,
                             lead: PFLead = .none,
                             tid: UInt16, sid: UInt16,
                             game: PFGame,
                             deadBattery: Bool = false,
                             feebasTile: Bool = false,
                             encounter: PFEncounter,
                             location: UInt8,
                             filterGender: UInt8 = 255,
                             filterAbility: UInt8 = 255,
                             filterShiny: UInt8 = 255,
                             ivMin: [UInt8] = [0,0,0,0,0,0],
                             ivMax: [UInt8] = [31,31,31,31,31,31],
                             natures: [Bool] = Array(repeating: true, count: 25),
                             powers: [Bool] = Array(repeating: true, count: 16),
                             encounterSlots: [Bool] = Array(repeating: true, count: 12)) -> [PFWildSearcherStateSwift] {
        var count: Int32 = 0
        let ptr = pf_wildSearch3(method.rawValue, lead.rawValue, tid, sid,
                                  game.rawValue, deadBattery, feebasTile,
                                  encounter.rawValue, location,
                                  filterGender, filterAbility, filterShiny,
                                  ivMin, ivMax, natures, powers, encounterSlots, &count)
        guard let ptr else { return [] }
        defer { pf_freeResults(ptr) }

        return (0..<Int(count)).map { i in
            let r = ptr[i]
            let ivs = [r.ivs.0, r.ivs.1, r.ivs.2, r.ivs.3, r.ivs.4, r.ivs.5]
            return PFWildSearcherStateSwift(seed: r.seed, pid: r.pid,
                                             ivs: ivs, nature: r.nature, ability: r.ability,
                                             gender: r.gender, shiny: r.shiny,
                                             hiddenPower: r.hiddenPower,
                                             hiddenPowerStrength: r.hiddenPowerStrength,
                                             encounterSlot: r.encounterSlot, level: r.level,
                                             item: r.item, specie: r.specie, form: r.form)
        }
    }

    // MARK: Wild Gen 4

    static func wildGenerate4(seed: UInt32,
                               initialAdvances: UInt32,
                               maxAdvances: UInt32,
                               offset: UInt32 = 0,
                               method: PFMethod,
                               lead: PFLead = .none,
                               tid: UInt16, sid: UInt16,
                               game: PFGame,
                               feebasTile: Bool = false,
                               encounter: PFEncounter,
                               location: UInt8,
                               filterGender: UInt8 = 255,
                               filterAbility: UInt8 = 255,
                               filterShiny: UInt8 = 255,
                               ivMin: [UInt8] = [0,0,0,0,0,0],
                               ivMax: [UInt8] = [31,31,31,31,31,31],
                               natures: [Bool] = Array(repeating: true, count: 25),
                               powers: [Bool] = Array(repeating: true, count: 16),
                               encounterSlots: [Bool] = Array(repeating: true, count: 12)) -> [PFWildGeneratorState4Swift] {
        var count: Int32 = 0
        let ptr = pf_wildGenerate4(seed, initialAdvances, maxAdvances, offset,
                                    method.rawValue, lead.rawValue, tid, sid,
                                    game.rawValue, feebasTile,
                                    encounter.rawValue, location,
                                    filterGender, filterAbility, filterShiny,
                                    ivMin, ivMax, natures, powers, encounterSlots, &count)
        guard let ptr else { return [] }
        defer { pf_freeResults(ptr) }

        return (0..<Int(count)).map { i in
            let r = ptr[i]
            let ivs = [r.ivs.0, r.ivs.1, r.ivs.2, r.ivs.3, r.ivs.4, r.ivs.5]
            return PFWildGeneratorState4Swift(seed: r.seed, pid: r.pid, advances: r.advances,
                                               ivs: ivs, nature: r.nature, ability: r.ability,
                                               gender: r.gender, shiny: r.shiny,
                                               hiddenPower: r.hiddenPower,
                                               hiddenPowerStrength: r.hiddenPowerStrength,
                                               encounterSlot: r.encounterSlot, level: r.level,
                                               item: r.item, specie: r.specie, form: r.form,
                                               call: r.call, chatot: r.chatot)
        }
    }

    static func wildSearch4(minAdvance: UInt32 = 0,
                             maxAdvance: UInt32 = 0,
                             minDelay: UInt32 = 0,
                             maxDelay: UInt32 = 10000,
                             method: PFMethod,
                             lead: PFLead = .none,
                             tid: UInt16, sid: UInt16,
                             game: PFGame,
                             feebasTile: Bool = false,
                             encounter: PFEncounter,
                             location: UInt8,
                             filterGender: UInt8 = 255,
                             filterAbility: UInt8 = 255,
                             filterShiny: UInt8 = 255,
                             ivMin: [UInt8] = [0,0,0,0,0,0],
                             ivMax: [UInt8] = [31,31,31,31,31,31],
                             natures: [Bool] = Array(repeating: true, count: 25),
                             powers: [Bool] = Array(repeating: true, count: 16),
                             encounterSlots: [Bool] = Array(repeating: true, count: 12)) -> [PFWildSearcherState4Swift] {
        var count: Int32 = 0
        let ptr = pf_wildSearch4(minAdvance, maxAdvance, minDelay, maxDelay,
                                  method.rawValue, lead.rawValue, tid, sid,
                                  game.rawValue, feebasTile,
                                  encounter.rawValue, location,
                                  filterGender, filterAbility, filterShiny,
                                  ivMin, ivMax, natures, powers, encounterSlots, &count)
        guard let ptr else { return [] }
        defer { pf_freeResults(ptr) }

        return (0..<Int(count)).map { i in
            let r = ptr[i]
            let ivs = [r.ivs.0, r.ivs.1, r.ivs.2, r.ivs.3, r.ivs.4, r.ivs.5]
            return PFWildSearcherState4Swift(seed: r.seed, pid: r.pid, advances: r.advances,
                                              ivs: ivs, nature: r.nature, ability: r.ability,
                                              gender: r.gender, shiny: r.shiny,
                                              hiddenPower: r.hiddenPower,
                                              hiddenPowerStrength: r.hiddenPowerStrength,
                                              encounterSlot: r.encounterSlot, level: r.level,
                                              item: r.item, specie: r.specie, form: r.form)
        }
    }

    // MARK: Async Wild Search

    static func wildSearch3Async(method: PFMethod, lead: PFLead = .none,
                                  tid: UInt16, sid: UInt16, game: PFGame,
                                  deadBattery: Bool = false, feebasTile: Bool = false,
                                  encounter: PFEncounter, location: UInt8,
                                  filterGender: UInt8 = 255, filterAbility: UInt8 = 255, filterShiny: UInt8 = 255,
                                  ivMin: [UInt8] = [0,0,0,0,0,0], ivMax: [UInt8] = [31,31,31,31,31,31],
                                  natures: [Bool] = Array(repeating: true, count: 25),
                                  powers: [Bool] = Array(repeating: true, count: 16),
                                  encounterSlots: [Bool] = Array(repeating: true, count: 12)) -> OpaquePointer {
        let h = pf_wildSearch3_start(method.rawValue, lead.rawValue, tid, sid,
                                      game.rawValue, deadBattery, feebasTile,
                                      encounter.rawValue, location,
                                      filterGender, filterAbility, filterShiny,
                                      ivMin, ivMax, natures, powers, encounterSlots)!
        return OpaquePointer(h)
    }

    static func wildSearch4Async(minAdvance: UInt32 = 0, maxAdvance: UInt32 = 10000,
                                  minDelay: UInt32 = 500, maxDelay: UInt32 = 10000,
                                  method: PFMethod, lead: PFLead = .none,
                                  tid: UInt16, sid: UInt16, game: PFGame,
                                  feebasTile: Bool = false,
                                  encounter: PFEncounter, location: UInt8,
                                  filterGender: UInt8 = 255, filterAbility: UInt8 = 255, filterShiny: UInt8 = 255,
                                  ivMin: [UInt8] = [0,0,0,0,0,0], ivMax: [UInt8] = [31,31,31,31,31,31],
                                  natures: [Bool] = Array(repeating: true, count: 25),
                                  powers: [Bool] = Array(repeating: true, count: 16),
                                  encounterSlots: [Bool] = Array(repeating: true, count: 12)) -> OpaquePointer {
        let h = pf_wildSearch4_start(minAdvance, maxAdvance, minDelay, maxDelay,
                                      method.rawValue, lead.rawValue, tid, sid,
                                      game.rawValue, feebasTile,
                                      encounter.rawValue, location,
                                      filterGender, filterAbility, filterShiny,
                                      ivMin, ivMax, natures, powers, encounterSlots)!
        return OpaquePointer(h)
    }

    static func searchProgress(_ handle: OpaquePointer) -> Int {
        Int(pf_search_progress(UnsafeMutableRawPointer(handle)))
    }

    static func searchPollResults3(_ handle: OpaquePointer) -> [PFWildSearcherStateSwift] {
        var count: Int32 = 0
        guard let ptr = pf_search3_getResults(UnsafeMutableRawPointer(handle), &count) else { return [] }
        defer { pf_freeResults(ptr) }
        return (0..<Int(count)).map { i in
            let r = ptr[i]
            let ivs = [r.ivs.0, r.ivs.1, r.ivs.2, r.ivs.3, r.ivs.4, r.ivs.5]
            return PFWildSearcherStateSwift(seed: r.seed, pid: r.pid,
                                             ivs: ivs, nature: r.nature, ability: r.ability,
                                             gender: r.gender, shiny: r.shiny,
                                             hiddenPower: r.hiddenPower,
                                             hiddenPowerStrength: r.hiddenPowerStrength,
                                             encounterSlot: r.encounterSlot, level: r.level,
                                             item: r.item, specie: r.specie, form: r.form)
        }
    }

    static func searchPollResults4(_ handle: OpaquePointer) -> [PFWildSearcherState4Swift] {
        var count: Int32 = 0
        guard let ptr = pf_search4_getResults(UnsafeMutableRawPointer(handle), &count) else { return [] }
        defer { pf_freeResults(ptr) }
        return (0..<Int(count)).map { i in
            let r = ptr[i]
            let ivs = [r.ivs.0, r.ivs.1, r.ivs.2, r.ivs.3, r.ivs.4, r.ivs.5]
            return PFWildSearcherState4Swift(seed: r.seed, pid: r.pid, advances: r.advances,
                                              ivs: ivs, nature: r.nature, ability: r.ability,
                                              gender: r.gender, shiny: r.shiny,
                                              hiddenPower: r.hiddenPower,
                                              hiddenPowerStrength: r.hiddenPowerStrength,
                                              encounterSlot: r.encounterSlot, level: r.level,
                                              item: r.item, specie: r.specie, form: r.form)
        }
    }

    static func searchCancel(_ handle: OpaquePointer) {
        pf_search_cancel(UnsafeMutableRawPointer(handle))
    }

    static func searchFree(_ handle: OpaquePointer) {
        pf_search_free(UnsafeMutableRawPointer(handle))
    }

    // MARK: Egg Generator Gen 3

    struct EggResult3: Identifiable {
        let id = UUID()
        let pid: UInt32
        let advances: UInt32
        let ivs: [UInt8]
        let nature: UInt8
        let ability: UInt8
        let gender: UInt8
        let shiny: UInt8
        let inheritance: [UInt8]
        let redraws: UInt8
        let pickupAdvances: UInt32
    }

    struct EggResult4: Identifiable {
        let id = UUID()
        let pid: UInt32
        let advances: UInt32
        let ivs: [UInt8]
        let nature: UInt8
        let ability: UInt8
        let gender: UInt8
        let shiny: UInt8
        let inheritance: [UInt8]
        let pickupAdvances: UInt32
        let call: UInt8
        let chatot: UInt8
    }

    struct IDResult: Identifiable {
        let id = UUID()
        let advances: UInt32
        let tid: UInt16
        let sid: UInt16
        let tsv: UInt16
    }

    struct IDResult4: Identifiable {
        let id = UUID()
        let seed: UInt32
        let delay: UInt32
        let advances: UInt32
        let tid: UInt16
        let sid: UInt16
        let tsv: UInt16
        let seconds: UInt8
    }

    static func eggGenerate3(seedHeld: UInt32, seedPickup: UInt32,
                              initialAdvances: UInt32, maxAdvances: UInt32, offset: UInt32 = 0,
                              initialAdvancesPickup: UInt32, maxAdvancesPickup: UInt32, offsetPickup: UInt32 = 0,
                              calibration: UInt8 = 0, minRedraw: UInt8 = 0, maxRedraw: UInt8 = 0,
                              method: PFMethod, compatibility: UInt8,
                              parentAIVs: [UInt8], parentBIVs: [UInt8],
                              parentAAbility: UInt8, parentBAbility: UInt8,
                              parentAGender: UInt8, parentBGender: UInt8,
                              parentAItem: UInt8, parentBItem: UInt8,
                              parentANature: UInt8, parentBNature: UInt8,
                              eggSpecie: UInt16, masuda: Bool,
                              tid: UInt16, sid: UInt16,
                              game: UInt8, deadBattery: Bool = false,
                              filterGender: UInt8 = 255, filterAbility: UInt8 = 255, filterShiny: UInt8 = 255,
                              ivMin: [UInt8] = [0,0,0,0,0,0], ivMax: [UInt8] = [31,31,31,31,31,31],
                              natures: [Bool] = Array(repeating: false, count: 25),
                              powers: [Bool] = Array(repeating: false, count: 16)) -> [EggResult3] {
        var count: Int32 = 0
        let ptr = pf_eggGenerate3(seedHeld, seedPickup,
                                   initialAdvances, maxAdvances, offset,
                                   initialAdvancesPickup, maxAdvancesPickup, offsetPickup,
                                   calibration, minRedraw, maxRedraw,
                                   method.rawValue, compatibility,
                                   parentAIVs, parentBIVs,
                                   parentAAbility, parentBAbility,
                                   parentAGender, parentBGender,
                                   parentAItem, parentBItem,
                                   parentANature, parentBNature,
                                   eggSpecie, masuda,
                                   tid, sid, game, deadBattery,
                                   filterGender, filterAbility, filterShiny,
                                   ivMin, ivMax, natures, powers, &count)
        guard let ptr else { return [] }
        defer { pf_freeResults(ptr) }
        return (0..<Int(count)).map { i in
            let r = ptr[i]
            let ivs = [r.ivs.0, r.ivs.1, r.ivs.2, r.ivs.3, r.ivs.4, r.ivs.5]
            let inh = [r.inheritance.0, r.inheritance.1, r.inheritance.2,
                       r.inheritance.3, r.inheritance.4, r.inheritance.5]
            return EggResult3(pid: r.pid, advances: r.advances, ivs: ivs,
                              nature: r.nature, ability: r.ability, gender: r.gender,
                              shiny: r.shiny, inheritance: inh,
                              redraws: r.redraws, pickupAdvances: r.pickupAdvances)
        }
    }

    static func eggGenerate4(seedHeld: UInt32, seedPickup: UInt32,
                              initialAdvances: UInt32, maxAdvances: UInt32, offset: UInt32 = 0,
                              initialAdvancesPickup: UInt32, maxAdvancesPickup: UInt32, offsetPickup: UInt32 = 0,
                              parentAIVs: [UInt8], parentBIVs: [UInt8],
                              parentAAbility: UInt8, parentBAbility: UInt8,
                              parentAGender: UInt8, parentBGender: UInt8,
                              parentAItem: UInt8, parentBItem: UInt8,
                              parentANature: UInt8, parentBNature: UInt8,
                              eggSpecie: UInt16, masuda: Bool,
                              tid: UInt16, sid: UInt16, game: UInt8,
                              filterGender: UInt8 = 255, filterAbility: UInt8 = 255, filterShiny: UInt8 = 255,
                              ivMin: [UInt8] = [0,0,0,0,0,0], ivMax: [UInt8] = [31,31,31,31,31,31],
                              natures: [Bool] = Array(repeating: false, count: 25),
                              powers: [Bool] = Array(repeating: false, count: 16)) -> [EggResult4] {
        var count: Int32 = 0
        let ptr = pf_eggGenerate4(seedHeld, seedPickup,
                                   initialAdvances, maxAdvances, offset,
                                   initialAdvancesPickup, maxAdvancesPickup, offsetPickup,
                                   parentAIVs, parentBIVs,
                                   parentAAbility, parentBAbility,
                                   parentAGender, parentBGender,
                                   parentAItem, parentBItem,
                                   parentANature, parentBNature,
                                   eggSpecie, masuda,
                                   tid, sid, game,
                                   filterGender, filterAbility, filterShiny,
                                   ivMin, ivMax, natures, powers, &count)
        guard let ptr else { return [] }
        defer { pf_freeResults(ptr) }
        return (0..<Int(count)).map { i in
            let r = ptr[i]
            let ivs = [r.ivs.0, r.ivs.1, r.ivs.2, r.ivs.3, r.ivs.4, r.ivs.5]
            let inh = [r.inheritance.0, r.inheritance.1, r.inheritance.2,
                       r.inheritance.3, r.inheritance.4, r.inheritance.5]
            return EggResult4(pid: r.pid, advances: r.advances, ivs: ivs,
                              nature: r.nature, ability: r.ability, gender: r.gender,
                              shiny: r.shiny, inheritance: inh,
                              pickupAdvances: r.pickupAdvances,
                              call: r.call, chatot: r.chatot)
        }
    }

    // MARK: ID Generators

    static func idGenerate3RS(seed: UInt16, initialAdvances: UInt32, maxAdvances: UInt32) -> [IDResult] {
        var count: Int32 = 0
        guard let ptr = pf_idGenerate3_RS(seed, initialAdvances, maxAdvances, &count) else { return [] }
        defer { pf_freeResults(ptr) }
        return (0..<Int(count)).map { i in
            let r = ptr[i]
            return IDResult(advances: r.advances, tid: r.tid, sid: r.sid, tsv: r.tsv)
        }
    }

    static func idGenerate3FRLGE(tid: UInt16, initialAdvances: UInt32, maxAdvances: UInt32) -> [IDResult] {
        var count: Int32 = 0
        guard let ptr = pf_idGenerate3_FRLGE(tid, initialAdvances, maxAdvances, &count) else { return [] }
        defer { pf_freeResults(ptr) }
        return (0..<Int(count)).map { i in
            let r = ptr[i]
            return IDResult(advances: r.advances, tid: r.tid, sid: r.sid, tsv: r.tsv)
        }
    }

    static func idGenerate4(minDelay: UInt32, maxDelay: UInt32,
                             year: UInt16, month: UInt8, day: UInt8,
                             hour: UInt8, minute: UInt8,
                             targetTID: UInt16 = 0, filterTID: Bool = false,
                             targetSID: UInt16 = 0, filterSID: Bool = false) -> [IDResult4] {
        var count: Int32 = 0
        guard let ptr = pf_idGenerate4(minDelay, maxDelay, year, month, day, hour, minute,
                                        targetTID, filterTID, targetSID, filterSID, &count) else { return [] }
        defer { pf_freeResults(ptr) }
        return (0..<Int(count)).map { i in
            let r = ptr[i]
            return IDResult4(seed: r.seed, delay: r.delay, advances: r.advances,
                             tid: r.tid, sid: r.sid, tsv: r.tsv, seconds: r.seconds)
        }
    }

    // MARK: - GameCube

    struct ShadowTemplateInfo: Identifiable {
        let id: Int
        let specie: UInt16
        let level: UInt8
        let shadowType: UInt8
        let game: UInt32
        var specieName: String { PFBridge.specieName(specie) }
        var isColosseum: Bool { (game & PFGame.colosseum.rawValue) != 0 }
    }

    static func getShadowTemplates() -> [ShadowTemplateInfo] {
        var count: Int32 = 0
        guard let ptr = pf_getShadowTemplates(&count) else { return [] }
        defer { pf_freeResults(ptr) }
        return (0..<Int(count)).map { i in
            let r = ptr[i]
            return ShadowTemplateInfo(id: i, specie: r.specie, level: r.level,
                                       shadowType: r.shadowType, game: r.game)
        }
    }

    struct GameCubeResult: Identifiable {
        let id = UUID()
        let advances: UInt32
        let pid: UInt32
        let ivs: [UInt8]
        let nature: UInt8
        let ability: UInt8
        let gender: UInt8
        let shiny: UInt8
        let hiddenPower: UInt8
        let hiddenPowerStrength: UInt8
    }

    static func gamecubeGenerateShadow(seed: UInt32,
                                        initialAdvances: UInt32, maxAdvances: UInt32, offset: UInt32 = 0,
                                        shadowIndex: Int, unset: Bool,
                                        tid: UInt16, sid: UInt16, game: UInt32,
                                        filterGender: UInt8 = 255, filterAbility: UInt8 = 255, filterShiny: UInt8 = 255,
                                        ivMin: [UInt8] = [0,0,0,0,0,0], ivMax: [UInt8] = [31,31,31,31,31,31],
                                        natures: [Bool] = [Bool](repeating: false, count: 25),
                                        powers: [Bool] = [Bool](repeating: false, count: 16)) -> [GameCubeResult] {
        var count: Int32 = 0
        let ptr = pf_gamecubeGenerateShadow(seed, initialAdvances, maxAdvances, offset,
                                             Int32(shadowIndex), unset, tid, sid, game,
                                             filterGender, filterAbility, filterShiny,
                                             ivMin, ivMax, natures, powers, &count)
        guard let ptr else { return [] }
        defer { pf_freeResults(ptr) }
        return (0..<Int(count)).map { i in
            let r = ptr[i]
            let ivs = [r.ivs.0, r.ivs.1, r.ivs.2, r.ivs.3, r.ivs.4, r.ivs.5]
            return GameCubeResult(advances: r.advances, pid: r.pid, ivs: ivs,
                                   nature: r.nature, ability: r.ability, gender: r.gender,
                                   shiny: r.shiny, hiddenPower: r.hiddenPower,
                                   hiddenPowerStrength: r.hiddenPowerStrength)
        }
    }

    static func gamecubeGenerateStatic(seed: UInt32,
                                        initialAdvances: UInt32, maxAdvances: UInt32, offset: UInt32 = 0,
                                        method: PFMethod, staticType: Int, staticIndex: Int,
                                        tid: UInt16, sid: UInt16, game: UInt32,
                                        filterGender: UInt8 = 255, filterAbility: UInt8 = 255, filterShiny: UInt8 = 255,
                                        ivMin: [UInt8] = [0,0,0,0,0,0], ivMax: [UInt8] = [31,31,31,31,31,31],
                                        natures: [Bool] = [Bool](repeating: false, count: 25),
                                        powers: [Bool] = [Bool](repeating: false, count: 16)) -> [GameCubeResult] {
        var count: Int32 = 0
        let ptr = pf_gamecubeGenerateStatic(seed, initialAdvances, maxAdvances, offset,
                                             method.rawValue, Int32(staticType), Int32(staticIndex),
                                             tid, sid, game,
                                             filterGender, filterAbility, filterShiny,
                                             ivMin, ivMax, natures, powers, &count)
        guard let ptr else { return [] }
        defer { pf_freeResults(ptr) }
        return (0..<Int(count)).map { i in
            let r = ptr[i]
            let ivs = [r.ivs.0, r.ivs.1, r.ivs.2, r.ivs.3, r.ivs.4, r.ivs.5]
            return GameCubeResult(advances: r.advances, pid: r.pid, ivs: ivs,
                                   nature: r.nature, ability: r.ability, gender: r.gender,
                                   shiny: r.shiny, hiddenPower: r.hiddenPower,
                                   hiddenPowerStrength: r.hiddenPowerStrength)
        }
    }

    // MARK: - Seed Verification (Gen 4)

    static func coinFlips(_ seed: UInt32) -> String {
        let cStr = pf_coinFlips(seed)!
        let result = String(cString: cStr)
        free(cStr)
        return result
    }

    static func getCalls(_ seed: UInt32, skips: UInt8 = 0) -> String {
        let cStr = pf_getCalls(seed, skips)!
        let result = String(cString: cStr)
        free(cStr)
        return result
    }

    // MARK: Slot Extraction Helper

    private static func extractSlots(from area: PFEncounterArea) -> [PFSlotSwift] {
        let count = Int(area.slotCount)
        let mirror = Mirror(reflecting: area.slots)
        var slots: [PFSlotSwift] = []
        slots.reserveCapacity(count)
        for (i, child) in mirror.children.enumerated() {
            guard i < count else { break }
            let slot = child.value as! PFSlot
            slots.append(PFSlotSwift(specie: slot.specie, form: slot.form,
                                      minLevel: slot.minLevel, maxLevel: slot.maxLevel))
        }
        return slots
    }
}
