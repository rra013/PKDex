//
//  FRLGSeeds.swift
//  PKReference
//
//  FireRed and LeafGreen initial seeds: which 16-bit seeds a player can hit
//  on each version, from the RNG community's farmed seed lists, and how many
//  advances each takes to reach a target. Ported from Ten Lines by
//  Lincoln-LM (GPL-3.0, https://github.com/Lincoln-LM/ten-lines): the seed
//  list layouts (generate_ten_lines_precalc.py), the held-button offsets and
//  initial seed search (initial_seed.hpp, initial_seed.cpp), and the timing
//  and Teachy TV arithmetic (tenLines/index.ts).
//
//  FRLG seed the RNG once, from a 16-bit timer, when the player presses the
//  seed button on the title screen; that 16-bit value is the RNG's state,
//  and it advances once a frame from there. So a target, which the Finder's
//  searcher gives as the state that generates it, is reached from initial
//  seed `s` after `PokeRNG.distance(from: s, to: target)` advances. Each
//  farmed list says which seed a press at each moment gives, for each sound
//  and button setting; holding a button at startup or on the blackout
//  screen shifts the seed by a fixed amount.
//
//  `nonisolated` throughout: lists are parsed and searched off the main
//  actor.
//

import Foundation

// MARK: - The RNG

/// Gen 3's LCRNG, for distances between states.
nonisolated enum PokeRNG {
    static func next(_ state: UInt32) -> UInt32 { state &* 0x41C6_4E6D &+ 0x6073 }

    /// Multipliers and increments that jump 2^i advances, from Ten Lines'
    /// `JUMP_DATA`.
    private static let jumps: [(mult: UInt32, add: UInt32)] = [
        (0x41C64E6D, 0x6073), (0xC2A29A69, 0xE97E7B6A), (0xEE067F11, 0x31B0DDE4), (0xCFDDDF21, 0x67DBB608),
        (0x5F748241, 0xCBA72510), (0x8B2E1481, 0x1D29AE20), (0x76006901, 0xBA84EC40), (0x1711D201, 0x79F01880),
        (0xBE67A401, 0x08793100), (0xDDDF4801, 0x6B566200), (0x3FFE9001, 0x803CC400), (0x90FD2001, 0xA6B98800),
        (0x65FA4001, 0xE6731000), (0xDBF48001, 0x30E62000), (0xF7E90001, 0xF1CC4000), (0xEFD20001, 0x23988000),
        (0xDFA40001, 0x47310000), (0xBF480001, 0x8E620000), (0x7E900001, 0x1CC40000), (0xFD200001, 0x39880000),
        (0xFA400001, 0x73100000), (0xF4800001, 0xE6200000), (0xE9000001, 0xCC400000), (0xD2000001, 0x98800000),
        (0xA4000001, 0x31000000), (0x48000001, 0x62000000), (0x90000001, 0xC4000000), (0x20000001, 0x88000000),
        (0x40000001, 0x10000000), (0x80000001, 0x20000000), (0x00000001, 0x40000000), (0x00000001, 0x80000000),
    ]

    /// How many advances take `start` to `end`. The generator has full
    /// period, so every pair has exactly one answer below 2^32; each bit is
    /// settled in turn by whether a jump of that size is needed.
    static func distance(from start: UInt32, to end: UInt32) -> UInt32 {
        var state = start
        var result: UInt32 = 0
        for (bit, jump) in jumps.enumerated() where state != end {
            let mask = UInt32(1) << UInt32(bit)
            if (state ^ end) & mask != 0 {
                state = state &* jump.mult &+ jump.add
                result |= mask
            }
        }
        return result
    }

    /// `distance(from: 0, to: s)` for every 16-bit seed, so a distance from
    /// a seed to any target is one subtraction.
    static let distancesFromZero: [UInt32] = (0...0xFFFF).map { distance(from: 0, to: UInt32($0)) }
}

// MARK: - Versions and settings

/// A version of FireRed or LeafGreen, as the seed lists tell them apart.
nonisolated enum FRLGVersion: String, CaseIterable, Identifiable, Sendable {
    case fireRed = "fr", fireRedEU = "fr_eu", fireRedJPN10 = "fr_jpn_1_0", fireRedJPN11 = "fr_jpn_1_1"
    case fireRedSwitch = "fr_nx", fireRedSwitchJPN = "fr_jpn_nx", fireRedMGBA = "fr_mgba"
    case leafGreen = "lg", leafGreenEU = "lg_eu", leafGreenJPN = "lg_jpn"
    case leafGreenSwitch = "lg_nx", leafGreenSwitchJPN = "lg_jpn_nx", leafGreenMGBA = "lg_mgba"

    var id: String { rawValue }
    var isFireRed: Bool { rawValue.hasPrefix("fr") }
    var game: PFGame { isFireRed ? .fireRed : .leafGreen }
    var isSwitch: Bool { rawValue.hasSuffix("nx") }

    var name: String {
        switch self {
        case .fireRed: "FireRed (ENG)"
        case .fireRedEU: "FireRed (SPA/FRE/ITA/GER)"
        case .fireRedJPN10: "FireRed (JPN 1.0)"
        case .fireRedJPN11: "FireRed (JPN 1.1)"
        case .fireRedSwitch: "Switch FireRed (ENG/SPA/FRE/ITA/GER)"
        case .fireRedSwitchJPN: "Switch FireRed (JPN)"
        case .fireRedMGBA: "FireRed (ENG, mGBA 10.5)"
        case .leafGreen: "LeafGreen (ENG)"
        case .leafGreenEU: "LeafGreen (SPA/FRE/ITA/GER)"
        case .leafGreenJPN: "LeafGreen (JPN)"
        case .leafGreenSwitch: "Switch LeafGreen (ENG/SPA/FRE/ITA/GER)"
        case .leafGreenSwitchJPN: "Switch LeafGreen (JPN)"
        case .leafGreenMGBA: "LeafGreen (ENG, mGBA 10.5)"
        }
    }

    /// The farmed list it uses: the European versions share the English
    /// one, with their own held-button offsets.
    var sheet: FRLGSeedSheet {
        switch self {
        case .fireRed, .fireRedEU: .fireRed
        case .fireRedJPN10: .fireRedJPN10
        case .fireRedJPN11: .fireRedJPN11
        case .fireRedSwitch: .fireRedSwitch
        case .fireRedSwitchJPN: .fireRedSwitchJPN
        case .fireRedMGBA: .fireRedMGBA
        case .leafGreen, .leafGreenEU: .leafGreen
        case .leafGreenJPN: .leafGreenJPN
        case .leafGreenSwitch: .leafGreenSwitch
        case .leafGreenSwitchJPN: .leafGreenSwitchJPN
        case .leafGreenMGBA: .leafGreenMGBA
        }
    }

    var consoles: [FRLGConsole] { isSwitch ? [.switch1, .switch2] : [.gba, .gbp, .nds, .threeDS] }

    /// Teachy TV mode isn't worked out for the Switch yet (Ten Lines leaves
    /// it to GBA versions too).
    var supportsTeachyTV: Bool { !isSwitch }

    static func versions(fireRed: Bool) -> [FRLGVersion] { allCases.filter { $0.isFireRed == fireRed } }

    // What its list covers

    /// The settings its farmed list has seeds for.
    var farmedSettings: [FRLGSetting] { sheet.columns.map(\.setting) }

    /// Whether every setting the game has is farmed: the English GBA and
    /// mGBA lists, so far.
    var isFullyFarmed: Bool { farmedSettings.count == FRLGSeedSheet.fireRed.columns.count }

    var farmedSounds: Set<FRLGSound> { Set(farmedSettings.map(\.sound)) }
    var farmedButtonModes: Set<FRLGButtonMode> { Set(farmedSettings.map(\.buttonMode)) }
    var farmedSeedButtons: Set<FRLGSeedButton> { Set(farmedSettings.map(\.seedButton)) }

    /// Whether the list has seeds for these choices; nil is any.
    func isFarmed(sound: FRLGSound?, buttonMode: FRLGButtonMode?, seedButton: FRLGSeedButton?) -> Bool {
        farmedSettings.contains {
            (sound == nil || $0.sound == sound) && (buttonMode == nil || $0.buttonMode == buttonMode)
                && (seedButton == nil || $0.seedButton == seedButton)
        }
    }

    /// The held buttons that shift a farmed seed, in a button mode or any.
    func heldButtons(buttonMode: FRLGButtonMode?) -> [FRLGHeldButton] {
        let modes = farmedButtonModes
        let held = Set(FRLGHeldButtons.offsets(for: self)
            .filter { modes.contains($0.mode) && (buttonMode == nil || $0.mode == buttonMode) }
            .map(\.held))
        return FRLGHeldButton.allCases.filter(held.contains)
    }
}

/// The options menu's sound.
nonisolated enum FRLGSound: String, CaseIterable, Sendable {
    case mono, stereo
    var name: String { self == .mono ? "Mono" : "Stereo" }
}

/// The options menu's button mode: "L=A", "Help" or "LR".
nonisolated enum FRLGButtonMode: String, CaseIterable, Sendable {
    case lEqualsA = "a", help = "h", lr = "r"
    var name: String {
        switch self {
        case .lEqualsA: "L=A"
        case .help: "Help"
        case .lr: "LR"
        }
    }
}

/// The button pressed on the title screen to set the seed.
nonisolated enum FRLGSeedButton: String, CaseIterable, Sendable {
    case a, start, l
    var name: String {
        switch self {
        case .a: "A"
        case .start: "Start"
        case .l: "L"
        }
    }
}

/// A button held to shift the seed: from startup, or on the blackout
/// screen.
nonisolated enum FRLGHeldButton: String, CaseIterable, Sendable {
    case none
    case startupSelect = "startup_select", startupA = "startup_a"
    case blackoutR = "blackout_r", blackoutA = "blackout_a", blackoutL = "blackout_l", blackoutAL = "blackout_al"

    var name: String {
        switch self {
        case .none: "None"
        case .startupSelect: "Startup Select"
        case .startupA: "Startup A"
        case .blackoutR: "Blackout R"
        case .blackoutA: "Blackout A"
        case .blackoutL: "Blackout L"
        case .blackoutAL: "Blackout A+L"
        }
    }
}

/// A sound, button mode and seed button: one column of a farmed list.
nonisolated struct FRLGSetting: Hashable, Sendable {
    var sound: FRLGSound
    var buttonMode: FRLGButtonMode
    var seedButton: FRLGSeedButton

    /// "Mono · Help · A".
    var name: String { "\(sound.name) · \(buttonMode.name) · \(seedButton.name)" }
}

/// How a version's held buttons shift the seed, per button mode, from Ten
/// Lines' `HELD_BUTTON_OFFSETS`.
nonisolated enum FRLGHeldButtons {
    static func offsets(for version: FRLGVersion) -> [(mode: FRLGButtonMode, held: FRLGHeldButton, offset: Int16)] {
        func table(_ a: [(FRLGHeldButton, Int16)], _ h: [(FRLGHeldButton, Int16)], _ r: [(FRLGHeldButton, Int16)])
            -> [(mode: FRLGButtonMode, held: FRLGHeldButton, offset: Int16)] {
            a.map { (.lEqualsA, $0.0, $0.1) } + h.map { (.help, $0.0, $0.1) } + r.map { (.lr, $0.0, $0.1) }
        }
        switch version {
        case .fireRed, .leafGreen:
            return table([(.startupSelect, -1), (.startupA, -8), (.blackoutR, -23), (.blackoutA, -31),
                          (.blackoutL, 2), (.blackoutAL, -33), (.none, 0)],
                         [(.startupSelect, 7), (.startupA, 3), (.blackoutR, -23), (.blackoutA, -23), (.none, 0)],
                         [(.startupSelect, -1), (.startupA, -18), (.blackoutR, -23), (.blackoutA, -39), (.none, 0)])
        case .fireRedEU, .leafGreenEU:
            return table([(.startupSelect, 8), (.none, -1)],
                         [(.startupSelect, 7), (.none, 0)],
                         [(.startupSelect, -9), (.none, -8)])
        case .fireRedJPN10:
            return table([(.startupSelect, -1), (.startupA, 1), (.blackoutR, -10), (.blackoutA, -18),
                          (.blackoutL, -3), (.none, 0)],
                         [(.startupSelect, 7), (.startupA, 3), (.blackoutR, -27), (.blackoutA, -24), (.none, 0)],
                         [(.startupSelect, 0), (.startupA, -18), (.blackoutR, -23), (.blackoutA, -40), (.none, 0)])
        case .fireRedJPN11:
            return table([(.startupSelect, 10), (.startupA, -9), (.blackoutR, -23), (.blackoutA, -31),
                          (.blackoutL, -6), (.none, 0)],
                         [(.startupSelect, -7), (.startupA, -19), (.blackoutR, -21), (.blackoutA, -29), (.none, 0)],
                         [(.startupSelect, -7), (.startupA, -4), (.blackoutR, -29), (.blackoutA, -38), (.none, 0)])
        case .leafGreenJPN:
            return table([(.startupSelect, -1), (.startupA, -9), (.blackoutR, -22), (.blackoutA, -40),
                          (.blackoutL, -7), (.none, 0)],
                         [(.startupSelect, -1), (.startupA, -18), (.blackoutR, -23), (.blackoutA, -31), (.none, 0)],
                         [(.startupSelect, -1), (.startupA, -23), (.blackoutR, -23), (.blackoutA, -39), (.none, 0)])
        case .fireRedMGBA, .leafGreenMGBA, .fireRedSwitchJPN, .leafGreenSwitchJPN:
            return table([(.none, 0)], [(.none, 0)], [(.none, 0)])
        case .fireRedSwitch, .leafGreenSwitch:
            return table([(.none, 0)], [(.none, 0), (.blackoutR, -36), (.blackoutL, -36)], [(.none, 0)])
        }
    }
}

// MARK: - Consoles and timing

/// What the game runs on, for turning frames into milliseconds, from Ten
/// Lines' `SYSTEM_TIMING_DATA`.
nonisolated enum FRLGConsole: String, CaseIterable, Identifiable, Sendable {
    case gba, gbp, nds, threeDS = "3ds", switch1 = "nx", switch2 = "nx2"

    var id: String { rawValue }
    var name: String {
        switch self {
        case .gba: "Game Boy Advance"
        case .gbp: "Game Boy Player"
        case .nds: "Nintendo DS"
        case .threeDS: "Nintendo 3DS (open_agb_firm)"
        case .switch1: "Nintendo Switch"
        case .switch2: "Nintendo Switch 2"
        }
    }

    var framesPerSecond: Double {
        switch self {
        case .nds, .threeDS: 16_756_991 / 280_896
        default: 16_777_216 / 280_896
        }
    }

    var offsetMS: Int {
        switch self {
        case .gba: -260
        case .gbp: 200
        case .nds: 788
        case .threeDS: 1558
        case .switch1: 0
        case .switch2: -750
        }
    }

    func milliseconds(frames: Double) -> Int {
        Int((frames / framesPerSecond * 1000).rounded(.down)) + offsetMS
    }
}

/// While the Teachy TV is open, FRLG's RNG advances 313 times a frame, so
/// most of a long wait can be spent there.
nonisolated enum TeachyTV {
    static let advancesPerFrame: UInt32 = 313

    /// Frames in the Teachy TV and advances outside it, keeping at least
    /// `minimumOutside` outside.
    static func split(advances: UInt32, minimumOutside: UInt32) -> (ttvFrames: UInt32, regularAdvances: UInt32) {
        guard advances > minimumOutside else { return (0, advances) }
        let frames = (advances - minimumOutside) / advancesPerFrame
        return (frames, advances - frames * advancesPerFrame)
    }
}

// MARK: - Farmed seed lists

/// One of the community's farmed seed lists, as Ten Lines reads it: a
/// public sheet, the rows to skip, and which column holds which setting.
nonisolated enum FRLGSeedSheet: String, CaseIterable, Sendable {
    case fireRed = "fr_eng", leafGreen = "lg_eng"
    case fireRedJPN10 = "fr_jpn_1_0", fireRedJPN11 = "fr_jpn_1_1", leafGreenJPN = "lg_jpn"
    case fireRedMGBA = "fr_eng_mgba", leafGreenMGBA = "lg_eng_mgba"
    case fireRedSwitch = "fr_eng_nx", leafGreenSwitch = "lg_eng_nx"
    case fireRedSwitchJPN = "fr_jpn_nx", leafGreenSwitchJPN = "lg_jpn_nx"

    /// The bundled copy's name, without the .csv; `tools/update_frlg_seeds.sh`
    /// downloads them.
    var resourceName: String { "frlg-seeds-\(rawValue)" }

    var url: URL {
        let sheet: String = switch self {
        case .fireRed: "1ZNchTvoCpHFVPBscEJZG3JaaqR41D8VVnbXb23fzc44/gviz/tq?tqx=out:csv&gid=0"
        case .leafGreen: "12TUcXGbLY_bBDfVsgWZKvqrX13U6XAATQZrYnzBKP6Y/gviz/tq?tqx=out:csv&sheet=Leaf%20Green%20Seeds"
        case .fireRedJPN10: "1xSYuAuGSZQ4JbgQN262cfo80_A2CYko74bYGzl5ABTA/gviz/tq?tqx=out:csv&sheet=JPN%20Fire%20Red%201.0%20Seeds"
        case .fireRedJPN11: "1aQeWaZSi1ycSytrNEOwxJNoEg-K4eItYagU_dh9VIeU/gviz/tq?tqx=out:csv&sheet=JPN%20Fire%20Red%201.0%20Seeds"
        case .leafGreenJPN: "1LSRVD0_zK6vyd6ettUDfaCFJbm00g451d8s96dqAbA4/gviz/tq?tqx=out:csv&sheet=JPN%20Leaf%20Green%20Seeds"
        case .fireRedMGBA: "1aWo6FAjkLIut5TIKior4_04PlGessxUJhE8YWz_nQwc/gviz/tq?tqx=out:csv&sheet=Fire%20Red%20Seeds"
        case .leafGreenMGBA: "1YiQiII2v3AJK6RANMsQcBzVLk9dO6L99Zxt9FsCyKrI/gviz/tq?tqx=out:csv&sheet=Leaf%20Green%20Seeds"
        case .fireRedSwitch: "1mbn2-XAtmV7HZ1p4esgvUG710VX6FlfhN_HYL_zLJSk/gviz/tq?tqx=out:csv&sheet=FireRed%20Seeds"
        case .leafGreenSwitch: "1mbn2-XAtmV7HZ1p4esgvUG710VX6FlfhN_HYL_zLJSk/gviz/tq?tqx=out:csv&sheet=LeafGreen%20Seeds"
        case .fireRedSwitchJPN: "1mbn2-XAtmV7HZ1p4esgvUG710VX6FlfhN_HYL_zLJSk/gviz/tq?tqx=out:csv&sheet=JPN%20FireRed%20Seeds"
        case .leafGreenSwitchJPN: "1mbn2-XAtmV7HZ1p4esgvUG710VX6FlfhN_HYL_zLJSk/gviz/tq?tqx=out:csv&sheet=JPN%20LeafGreen%20Seeds"
        }
        return URL(string: "https://docs.google.com/spreadsheets/d/" + sheet)!
    }

    var isSwitch: Bool { rawValue.hasSuffix("nx") }

    /// Rows before the first seed.
    var headerRows: Int {
        switch self {
        case .fireRed, .leafGreen: 1
        case .fireRedJPN10, .fireRedJPN11, .leafGreenJPN: 3
        default: 2
        }
    }

    /// For a GBA list, the frame of the first row; each row is the next
    /// frame. The Switch lists give each row's time instead.
    var startingFrame: Int {
        switch self {
        case .fireRed, .leafGreen: 4062 / 2
        case .fireRedJPN10, .fireRedJPN11: 2090 - 45
        case .leafGreenJPN: 2090 - 41
        case .fireRedMGBA, .leafGreenMGBA: 4062 / 2 - 45
        default: 0
        }
    }

    /// A Switch list's times, in sixteenths of a frame, are this much short
    /// of the seed's.
    static let switchTimeOffset = 5737

    /// Which column holds which setting. The Switch lists leave the
    /// settings nobody has farmed yet out, as Ten Lines does.
    var columns: [(column: Int, setting: FRLGSetting)] {
        func s(_ sound: FRLGSound, _ mode: FRLGButtonMode, _ button: FRLGSeedButton) -> FRLGSetting {
            FRLGSetting(sound: sound, buttonMode: mode, seedButton: button)
        }
        let full: [FRLGSetting] = [
            s(.mono, .lr, .a), s(.mono, .lEqualsA, .a), s(.mono, .help, .a),
            s(.stereo, .lr, .a), s(.stereo, .lEqualsA, .a), s(.stereo, .help, .a),
            s(.mono, .lr, .start), s(.mono, .lEqualsA, .start), s(.mono, .help, .start),
            s(.stereo, .lr, .start), s(.stereo, .lEqualsA, .start), s(.stereo, .help, .start),
            s(.mono, .lEqualsA, .l), s(.stereo, .lEqualsA, .l),
        ]
        switch self {
        case .fireRed, .leafGreen: return full.enumerated().map { (3 + $0.offset, $0.element) }
        case .fireRedMGBA, .leafGreenMGBA: return full.enumerated().map { (2 + $0.offset, $0.element) }
        case .fireRedJPN10, .fireRedJPN11, .leafGreenJPN:
            return full.prefix(6).enumerated().map { (1 + $0.offset, $0.element) }
        case .fireRedSwitch:
            return [(2, s(.mono, .help, .a)), (3, s(.stereo, .help, .a)), (4, s(.mono, .help, .start))]
        case .leafGreenSwitch:
            return [(2, s(.mono, .help, .a)), (3, s(.stereo, .help, .a)), (4, s(.mono, .help, .start)),
                    (7, s(.stereo, .lr, .a))]
        case .fireRedSwitchJPN, .leafGreenSwitchJPN:
            return [(2, s(.mono, .help, .a))]
        }
    }
}

/// A seed a press can give: its setting, when (in sixteenths of a frame
/// from startup), and the seed.
nonisolated struct FRLGSeedEntry: Hashable, Sendable {
    var setting: FRLGSetting
    var seedTime: Int
    var seed: UInt16
}

/// A farmed list, read from its sheet's CSV.
nonisolated struct FRLGSeedList: Sendable {
    let sheet: FRLGSeedSheet
    let entries: [FRLGSeedEntry]

    /// Rows without a first cell are skipped; an empty, "-" or out-of-range
    /// seed is a moment nobody has farmed. Where the same seed comes on
    /// consecutive rows, the first stands for them.
    init(sheet: FRLGSeedSheet, csv: String) {
        self.sheet = sheet
        let rows = Self.rows(csv).dropFirst(sheet.headerRows).filter { !($0.first ?? "").isEmpty }
        var entries: [FRLGSeedEntry] = []
        for (column, setting) in sheet.columns {
            var last: UInt16?
            for (index, row) in rows.enumerated() {
                guard column < row.count, let seed = Self.seed(row[column]) else { continue }
                if seed == last { continue }
                last = seed
                let seedTime: Int
                if sheet.isSwitch {
                    guard row.count > 1, let time = Int(row[1]) else { continue }
                    seedTime = time + FRLGSeedSheet.switchTimeOffset
                } else {
                    seedTime = (sheet.startingFrame + index) * 16
                }
                entries.append(FRLGSeedEntry(setting: setting, seedTime: seedTime, seed: seed))
            }
        }
        self.entries = entries
    }

    private static func seed(_ text: String) -> UInt16? {
        guard !text.isEmpty, text != "-", let value = UInt32(text, radix: 16), value <= 0xFFFF else { return nil }
        return UInt16(value)
    }

    /// The cells of each line, for the sheets' plain quoted CSV.
    static func rows(_ csv: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var cell = ""
        var quoted = false
        var chars = csv.makeIterator()
        while let char = chars.next() {
            if quoted {
                if char == "\"" { quoted = false } else { cell.append(char) }
            } else {
                switch char {
                case "\"": quoted = true
                case ",": row.append(cell); cell = ""
                case "\n", "\r\n":
                    row.append(cell); rows.append(row); row = []; cell = ""
                case "\r": break
                default: cell.append(char)
                }
            }
        }
        if !cell.isEmpty || !row.isEmpty { row.append(cell); rows.append(row) }
        return rows
    }
}

// MARK: - Searching

/// A seed the player can hit, and how far it is from a target.
nonisolated struct FRLGInitialSeed: Hashable, Sendable {
    var seed: UInt16
    var setting: FRLGSetting
    var held: FRLGHeldButton
    /// When to press, in sixteenths of a frame from startup.
    var seedTime: Int
    /// Advances from this seed to the target.
    var advances: UInt32 = 0

    /// "Mono · Help · A", with any held button: "…, holding Blackout R".
    var settingsName: String {
        held == .none ? setting.name : "\(setting.name), holding \(held.name)"
    }
}

/// Which settings to count.
nonisolated struct FRLGSettingsFilter: Hashable, Sendable {
    var sound: FRLGSound?
    var buttonMode: FRLGButtonMode?
    var seedButton: FRLGSeedButton?
    var held: FRLGHeldButton?

    func allows(_ setting: FRLGSetting, held: FRLGHeldButton) -> Bool {
        (sound == nil || setting.sound == sound) && (buttonMode == nil || setting.buttonMode == buttonMode)
            && (seedButton == nil || setting.seedButton == seedButton) && (self.held == nil || held == self.held)
    }
}

/// Every seed a version's player can hit with the settings allowed, sorted
/// so the ones a range of advances away from any target can be found by
/// halving.
nonisolated struct FRLGSeedIndex: Sendable {
    let version: FRLGVersion
    /// By `distance(from: 0, to: seed)`.
    private let seeds: [(fromZero: UInt32, seed: FRLGInitialSeed)]

    init(list: FRLGSeedList, version: FRLGVersion, filter: FRLGSettingsFilter = FRLGSettingsFilter()) {
        self.version = version
        let offsets = FRLGHeldButtons.offsets(for: version)
        var seeds: [(UInt32, FRLGInitialSeed)] = []
        var seen = Set<FRLGInitialSeed>()
        for entry in list.entries {
            for (mode, held, offset) in offsets where mode == entry.setting.buttonMode {
                guard filter.allows(entry.setting, held: held) else { continue }
                let seed = UInt16(truncatingIfNeeded: Int(entry.seed) + Int(offset))
                let initial = FRLGInitialSeed(seed: seed, setting: entry.setting, held: held, seedTime: entry.seedTime)
                guard seen.insert(initial).inserted else { continue }
                seeds.append((PokeRNG.distancesFromZero[Int(seed)], initial))
            }
        }
        // Ties keep a press's held buttons together, so they can be shown as
        // one.
        self.seeds = seeds.sorted {
            ($0.0, $0.1.seedTime, $0.1.setting.name, $0.1.held.rawValue)
                < ($1.0, $1.1.seedTime, $1.1.setting.name, $1.1.held.rawValue)
        }
    }

    var count: Int { seeds.count }

    /// The seeds `minimum` to `maximum` advances short of `target`, fewest
    /// advances first.
    func seeds(reaching target: UInt32, minimum: UInt32, maximum: UInt32, limit: Int = .max) -> [FRLGInitialSeed] {
        guard !seeds.isEmpty, minimum <= maximum else { return [] }
        let toTarget = PokeRNG.distance(from: 0, to: target)
        // advances = toTarget - fromZero (mod 2^32): the fewest advances are
        // the seeds just below `toTarget - minimum`, going down.
        let highest = toTarget &- minimum
        var index = upperBound(highest)
        var found: [FRLGInitialSeed] = []
        for _ in 0..<seeds.count {
            index = index == 0 ? seeds.count - 1 : index - 1
            let candidate = seeds[index]
            let advances = toTarget &- candidate.fromZero
            guard advances >= minimum else { continue }
            guard advances <= maximum, found.count < limit else { break }
            var reached = candidate.seed
            reached.advances = advances
            found.append(reached)
        }
        return found
    }

    /// The fewest-advances seed in range, if any.
    func nearest(reaching target: UInt32, minimum: UInt32, maximum: UInt32) -> FRLGInitialSeed? {
        seeds(reaching: target, minimum: minimum, maximum: maximum, limit: 1).first
    }

    /// The first index whose `fromZero` is above `value`.
    private func upperBound(_ value: UInt32) -> Int {
        var (low, high) = (0, seeds.count)
        while low < high {
            let middle = (low + high) / 2
            if seeds[middle].fromZero <= value { low = middle + 1 } else { high = middle }
        }
        return low
    }
}

// MARK: - Calibration

/// What was caught, for calibration, filtered as Ten Lines filters it.
nonisolated struct FRLGCatch: Sendable, Equatable {
    /// Nil searches every nature, with any IVs: Ten Lines' "Any", which
    /// turns its IV calculation off.
    var nature: UInt8?
    var ivMin: [UInt8] = Array(repeating: 0, count: 6)
    var ivMax: [UInt8] = Array(repeating: 31, count: 6)
    /// PokéFinder's gender filter: 255 any, 0 male, 1 female.
    var gender: UInt8 = 255
    /// PokéFinder's shiny filter: 255 any, 1 star, 2 square, 3 either.
    var shiny: UInt8 = 255
}

/// A level and the six stats seen at it, for the IV calculator. Nil is a
/// stat not entered yet.
nonisolated struct FRLGStatsLine: Hashable, Identifiable, Sendable {
    var id = UUID()
    var level: Int?
    var stats: [Int?] = Array(repeating: nil, count: 6)

    var isBlank: Bool { stats.allSatisfy { $0 == nil } }
}

/// Ten Lines' IV calculator (IvCalculator.tsx, iv_calc.cpp): the IVs a
/// static encounter's stats allow with its nature, through PokéFinder's IV
/// checker and the template's base stats.
nonisolated enum FRLGIVCalculator {
    static let statNames = ["HP", "Attack", "Defense", "Special Attack", "Special Defense", "Speed"]
    /// Ten Lines' limits on what can be entered.
    static let statMaximums = [651, 437, 545, 435, 545, 479]

    enum Outcome: Equatable {
        /// Per stat, the lowest and highest IV that fits every line.
        case ivs(min: [UInt8], max: [UInt8])
        /// What's missing or wrong, as Ten Lines words it.
        case error(String)
    }

    /// Lines after the first with no stats yet are left out, so adding one
    /// doesn't stop a search.
    static func calculate(_ lines: [FRLGStatsLine], template: PFStaticTemplateRef, nature: UInt8) -> Outcome {
        var parsed: [(level: UInt8, stats: [UInt16])] = []
        for (number, line) in zip(1..., lines) where number == 1 || !line.isBlank {
            let name = lines.count > 1 ? "Line \(number): " : ""
            guard let level = line.level else { return .error(name + "Enter its level.") }
            guard (1...100).contains(level) else { return .error(name + "Level must be 1–100.") }
            var stats: [UInt16] = []
            for (index, stat) in line.stats.enumerated() {
                guard let stat else { return .error(name + "Enter its \(statNames[index]).") }
                guard (1...statMaximums[index]).contains(stat) else {
                    return .error(name + "\(statNames[index]) must be 1–\(statMaximums[index]).")
                }
                stats.append(UInt16(stat))
            }
            parsed.append((UInt8(level), stats))
        }
        guard let ranges = PFBridge.calcIVsStatic3(template: template, lines: parsed, nature: nature) else {
            return .error("This encounter isn't in PokéFinder's tables.")
        }
        if let index = ranges.firstIndex(where: { $0 == nil }) {
            return .error("No possible \(statNames[index]) IV. Check the nature, level and stats.")
        }
        let found = ranges.compactMap { $0 }
        return .ivs(min: found.map(\.lowerBound), max: found.map(\.upperBound))
    }
}

/// A press and advance that make what was caught.
nonisolated struct FRLGCalibrationHit: Hashable, Sendable {
    var seed: UInt16
    /// When that press is, in sixteenths of a frame from startup.
    var seedTime: Int
    /// Presses later in the list than the one aimed for; earlier ones are
    /// negative.
    var seedOffset: Int
    /// Advances from the seed to the Pokémon.
    var advances: UInt32
    /// Frames spent in the Teachy TV, when it's used.
    var teachyTVFrames: UInt32
    var pid: UInt32
    var ivs: [UInt8]
    var nature: UInt8
    var gender: UInt8
    var shiny: UInt8

    /// The frame of the final press: the advances, less the Teachy TV's
    /// 313 a frame.
    var finalFrame: UInt32 { advances - teachyTVFrames * TeachyTV.advancesPerFrame + teachyTVFrames }
}

nonisolated extension FRLGSeedList {
    /// The seeds a setting gives press by press, in time order, shifted by
    /// a held button.
    func timeline(_ setting: FRLGSetting, offset: Int16) -> [(seed: UInt16, seedTime: Int)] {
        entries.filter { $0.setting == setting }
            .map { (UInt16(truncatingIfNeeded: Int($0.seed) + Int(offset)), $0.seedTime) }
    }
}

/// Which seed and frame an attempt actually hit, from what was caught.
/// Ported from Ten Lines' calibration (calibration.cpp, check_seeds_static).
nonisolated enum FRLGCalibration {
    /// Every press `seedLeeway` either side of the one attempted (same
    /// setting and held button) and final frame in `frames` that makes
    /// `caught` from the encounter's `template`, nearest the attempt first.
    /// With Teachy TV, the frames spent there range over `teachyTVFrames`,
    /// 313 advances each.
    static func search(list: FRLGSeedList, version: FRLGVersion, attempted: FRLGInitialSeed, targetFrame: UInt32,
                       seedLeeway: Int, frames: ClosedRange<UInt32>, teachyTVFrames: ClosedRange<UInt32>? = nil,
                       method: PFMethod, template: PFStaticTemplateRef, tid: UInt16, sid: UInt16,
                       caught: FRLGCatch, limit: Int = 200) -> [FRLGCalibrationHit] {
        guard let offset = FRLGHeldButtons.offsets(for: version)
            .first(where: { $0.mode == attempted.setting.buttonMode && $0.held == attempted.held })?.offset
        else { return [] }
        let timeline = list.timeline(attempted.setting, offset: offset)
        guard let index = timeline.firstIndex(where: { $0.seed == attempted.seed && $0.seedTime == attempted.seedTime })
        else { return [] }
        var natures = Array(repeating: caught.nature == nil, count: 25)
        if let nature = caught.nature { natures[Int(nature)] = true }
        let anyIVs = caught.nature == nil
        var hits: [FRLGCalibrationHit] = []
        for place in max(0, index - seedLeeway)...min(timeline.count - 1, index + seedLeeway) {
            let (seed, seedTime) = timeline[place]
            for ttv in teachyTVFrames ?? 0...0 where ttv <= frames.upperBound {
                // The final frame is the frames in the Teachy TV plus the
                // advances outside it.
                let start = frames.lowerBound > ttv ? frames.lowerBound - ttv : 0
                let end = frames.upperBound - ttv
                let states = PFBridge.staticTemplateGenerate3(
                    seed: UInt32(seed), initialAdvances: start + ttv * TeachyTV.advancesPerFrame,
                    maxAdvances: end - start, method: method, template: template,
                    tid: tid, sid: sid, game: version.game,
                    filterGender: caught.gender, filterShiny: caught.shiny,
                    ivMin: anyIVs ? Array(repeating: 0, count: 6) : caught.ivMin,
                    ivMax: anyIVs ? Array(repeating: 31, count: 6) : caught.ivMax,
                    natures: natures, powers: Array(repeating: true, count: 16))
                for state in states {
                    hits.append(FRLGCalibrationHit(seed: seed, seedTime: seedTime, seedOffset: place - index,
                                                   advances: state.advances, teachyTVFrames: ttv, pid: state.pid,
                                                   ivs: state.ivs, nature: state.nature,
                                                   gender: state.gender, shiny: state.shiny))
                }
                // A loose filter matches nearly every frame: keep the
                // nearest as it goes.
                if hits.count > limit * 8 { hits = nearest(hits, to: targetFrame, limit: limit) }
            }
        }
        return nearest(hits, to: targetFrame, limit: limit)
    }

    /// The `limit` hits nearest the attempt: fewest seeds away, then fewest
    /// frames.
    private static func nearest(_ hits: [FRLGCalibrationHit], to targetFrame: UInt32, limit: Int) -> [FRLGCalibrationHit] {
        Array(hits.sorted {
            (abs($0.seedOffset), abs(Int($0.finalFrame) - Int(targetFrame)), $0.seedOffset)
                < (abs($1.seedOffset), abs(Int($1.finalFrame) - Int(targetFrame)), $1.seedOffset)
        }.prefix(limit))
    }
}
