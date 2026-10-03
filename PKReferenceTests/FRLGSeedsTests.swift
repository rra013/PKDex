//
//  FRLGSeedsTests.swift
//  PKReferenceTests
//
//  Covers FireRed and LeafGreen initial seeds, ported from Ten Lines: the
//  RNG distance against walking the generator; the farmed lists read as
//  Ten Lines reads them (Switch and GBA layouts, skipped and repeated
//  seeds, seed times); held-button offsets; the search by advances; and,
//  end to end, that a target from PokéFinder's searcher comes back from
//  its initial seed after the advances found, by PokéFinder's generator.
//  Timing and Teachy TV follow Ten Lines' arithmetic.
//

import Testing
import Foundation
@testable import PKReference

@MainActor
@Suite("FRLG Initial Seeds")
struct FRLGSeedsTests {

    private func advanced(_ seed: UInt32, _ steps: Int) -> UInt32 {
        (0..<steps).reduce(seed) { state, _ in PokeRNG.next(state) }
    }

    private func bundled(_ sheet: FRLGSeedSheet) throws -> FRLGSeedList {
        let url = try #require(Bundle.main.url(forResource: sheet.resourceName, withExtension: "csv"),
                               "\(sheet.resourceName).csv isn't bundled")
        return FRLGSeedList(sheet: sheet, csv: try String(contentsOf: url, encoding: .utf8))
    }

    @Test("The distance between two states is the advances between them")
    func distance() {
        for (start, steps) in [(UInt32(0), 0), (0, 1), (0x11C7, 5_000), (0xDEAD_BEEF, 123_457), (0xFFFF, 1 << 20)] {
            #expect(PokeRNG.distance(from: start, to: advanced(start, steps)) == UInt32(steps), "\(steps)")
        }
        #expect(PokeRNG.distancesFromZero[0x11C7] == PokeRNG.distance(from: 0, to: 0x11C7))
    }

    @Test("Every list is bundled and reads as a seed list", arguments: FRLGSeedSheet.allCases)
    func bundledLists(sheet: FRLGSeedSheet) throws {
        let list = try bundled(sheet)
        #expect(list.entries.count > 1_000)
        #expect(Set(list.entries.map(\.setting)) == Set(sheet.columns.map(\.setting)))
    }

    /// The Switch FireRed list's first row: seed time 23385 (+5737), then
    /// 11C7 for Mono and Stereo Help/A, and 11BF for Mono Help/Start.
    @Test("A Switch list gives each row's time")
    func switchList() throws {
        let list = try bundled(.fireRedSwitch)
        let first = list.entries.filter { $0.seedTime == 23_385 + 5_737 }
        let help = FRLGSetting(sound: .mono, buttonMode: .help, seedButton: .a)
        #expect(first.contains(FRLGSeedEntry(setting: help, seedTime: 29_122, seed: 0x11C7)))
        #expect(first.contains(FRLGSeedEntry(setting: FRLGSetting(sound: .stereo, buttonMode: .help, seedButton: .a),
                                             seedTime: 29_122, seed: 0x11C7)))
        #expect(first.contains(FRLGSeedEntry(setting: FRLGSetting(sound: .mono, buttonMode: .help, seedButton: .start),
                                             seedTime: 29_122, seed: 0x11BF)))
    }

    /// GBA rows are consecutive frames from the list's starting frame; an
    /// empty or "-" seed is a gap, a repeat stands in for the first, and a
    /// row without a first cell doesn't count.
    @Test("A GBA list counts frames by row")
    func gbaList() {
        let csv = """
            "Frame","x","x","MonoLRA","MonoLA"
            "1","","","1234","ABCD"
            "","","","9999","9999"
            "2","","","-","ABCD"
            "3","","","5678","ABCE"
            """
        let list = FRLGSeedList(sheet: .fireRed, csv: csv)
        let lr = FRLGSetting(sound: .mono, buttonMode: .lr, seedButton: .a)
        let lEqualsA = FRLGSetting(sound: .mono, buttonMode: .lEqualsA, seedButton: .a)
        #expect(list.entries.filter { $0.setting == lr }
                == [FRLGSeedEntry(setting: lr, seedTime: 2031 * 16, seed: 0x1234),
                    FRLGSeedEntry(setting: lr, seedTime: 2033 * 16, seed: 0x5678)])
        #expect(list.entries.filter { $0.setting == lEqualsA }
                == [FRLGSeedEntry(setting: lEqualsA, seedTime: 2031 * 16, seed: 0xABCD),
                    FRLGSeedEntry(setting: lEqualsA, seedTime: 2033 * 16, seed: 0xABCE)])
    }

    /// On Switch, holding R or L on the blackout screen in Help mode takes
    /// 36 off the seed.
    @Test("Held buttons shift the seed by the version's offsets")
    func heldButtons() throws {
        let help = FRLGSetting(sound: .mono, buttonMode: .help, seedButton: .a)
        let list = try bundled(.fireRedSwitch)
        let index = FRLGSeedIndex(list: list, version: .fireRedSwitch,
                                  filter: FRLGSettingsFilter(sound: .mono, buttonMode: .help, seedButton: .a))
        let target: UInt32 = 0x11C7 - 36
        let held = index.seeds(reaching: target, minimum: 0, maximum: 0)
        // Both come from the press that gives 11C7 without a held button.
        #expect(held.contains { $0.seed == 0x11C7 - 36 && $0.held == .blackoutR && $0.seedTime == 29_122 && $0.setting == help })
        #expect(held.contains { $0.held == .blackoutL && $0.seedTime == 29_122 })
        let plain = FRLGSeedIndex(list: list, version: .fireRedSwitch,
                                  filter: FRLGSettingsFilter(sound: .mono, buttonMode: .help, seedButton: .a, held: FRLGHeldButton.none))
        #expect(plain.seeds(reaching: target, minimum: 0, maximum: 0).allSatisfy { $0.held == .none && $0.seedTime != 29_122 })
        #expect(plain.seeds(reaching: 0x11C7, minimum: 0, maximum: 0).first?.seedTime == 29_122)

        // Shown as one press: R and L do the same.
        let choices = FRLGHeldChoice.merged(held.filter { $0.seedTime == 29_122 })
        #expect(choices.map(\.settingsName) == ["Mono · Help · A, holding Blackout R or Blackout L"])
    }

    @Test("Seeds reaching a target come in range, fewest advances first")
    func search() throws {
        let index = FRLGSeedIndex(list: try bundled(.fireRedSwitch), version: .fireRedSwitch)
        let target = advanced(0x11C7, 5_000)
        let seeds = index.seeds(reaching: target, minimum: 1_000, maximum: 200_000)
        #expect(!seeds.isEmpty)
        #expect(seeds.map(\.advances) == seeds.map(\.advances).sorted())
        for seed in seeds.prefix(20) {
            #expect((1_000...200_000).contains(seed.advances))
            #expect(advanced(UInt32(seed.seed), Int(seed.advances)) == target)
        }
        #expect(index.nearest(reaching: target, minimum: 1_000, maximum: 200_000) == seeds.first)
        #expect(index.seeds(reaching: target, minimum: 0, maximum: 5_000).contains { $0.seed == 0x11C7 && $0.advances == 5_000 })
    }

    /// A 31-IV target from PokéFinder's Static 1 searcher, found from a seed
    /// on Switch FireRed: PokéFinder's generator, from that seed and that
    /// many advances, makes the same Pokémon.
    @Test("A target comes back from its initial seed, by PokéFinder's generator")
    func endToEnd() throws {
        let targets = staticSearchGen3(minIVs: (31, 31, 31, 31, 31, 31), maxIVs: (31, 31, 31, 31, 31, 31),
                                       natures: [], tid: 0, sid: 0, shinyOnly: false, method: .method1)
        let target = try #require(targets.first)
        let index = FRLGSeedIndex(list: try bundled(.fireRedSwitch), version: .fireRedSwitch)
        let seed = try #require(index.nearest(reaching: target.seed, minimum: 0, maximum: .max))
        let generated = PFBridge.staticGenerate3(seed: UInt32(seed.seed), initialAdvances: seed.advances,
                                                 maxAdvances: 0, method: .method1, tid: 0, sid: 0,
                                                 natures: Array(repeating: true, count: 25),
                                                 powers: Array(repeating: true, count: 16))
        let made = try #require(generated.first)
        #expect(made.advances == seed.advances)
        #expect(made.pid == target.pid && made.ivs == [31, 31, 31, 31, 31, 31])
    }

    @Test("Timing and Teachy TV follow Ten Lines")
    func timing() {
        // 59.7275 frames a second; Switch 2 is 750 ms earlier than Switch.
        #expect(FRLGConsole.switch1.milliseconds(frames: 29_122.0 / 16) == 30_473)
        #expect(FRLGConsole.switch2.milliseconds(frames: 29_122.0 / 16) == 30_473 - 750)
        #expect(FRLGConsole.gba.milliseconds(frames: 600) == 10_045 - 260)
        let split = TeachyTV.split(advances: 3_600 + 313 * 100 + 7, minimumOutside: 3_600)
        #expect(split.ttvFrames == 100 && split.regularAdvances == 3_607)
        #expect(TeachyTV.split(advances: 1_000, minimumOutside: 3_600) == (0, 1_000))
        #expect(!FRLGVersion.fireRedSwitch.supportsTeachyTV && FRLGVersion.fireRed.supportsTeachyTV)
    }

    /// Every version starts on Mono, Help and A, with no held button: the
    /// game's own options, which every list farms. A setting a list hasn't
    /// farmed can still be chosen, and says it finds nothing.
    @Test("Options start on what each version's list has farmed")
    func defaults() throws {
        let suite = "FRLGSeedsTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let search = FRLGSeedSearch(defaults: defaults)
        #expect(search.version == .fireRedSwitch)
        #expect(search.sound == .mono && search.buttonMode == .help && search.seedButton == .a && search.held == FRLGHeldButton.none)
        #expect(search.isFarmed)

        for version in FRLGVersion.allCases {
            #expect(version.farmedSettings.contains(FRLGSeedSearch.gameDefaults), "\(version)")
        }
        search.buttonMode = .lr
        #expect(!search.isFarmed)
        search.version = .leafGreenSwitch
        #expect(search.buttonMode == .help && search.isFarmed)

        #expect(FRLGVersion.fireRed.isFullyFarmed && !FRLGVersion.fireRedSwitch.isFullyFarmed)
        #expect(FRLGVersion.fireRedSwitch.farmedButtonModes == [.help])
        #expect(FRLGVersion.fireRedSwitch.heldButtons(buttonMode: .help) == [.none, .blackoutR, .blackoutL])
        #expect(FRLGVersion.fireRedSwitch.heldButtons(buttonMode: .lr).isEmpty)
        #expect(FRLGVersion.fireRedJPN10.farmedSeedButtons == [.a])
    }
}
