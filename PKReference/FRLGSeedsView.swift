//
//  FRLGSeedsView.swift
//  PKReference
//
//  The Finder's FireRed and LeafGreen initial seeds: the farmed seed lists
//  (bundled, or newer ones downloaded from the community's sheets), the
//  settings a player uses and the advances they can wait, and for each
//  target the seeds that reach it, when to press, and Send to Timer. The
//  search itself is in `FRLGSeeds.swift`, ported from Ten Lines.
//

import SwiftUI

// MARK: - The seed lists

/// The farmed lists: the bundled copies, or newer ones downloaded from the
/// public sheets into Application Support.
@MainActor @Observable
final class FRLGSeedStore {
    static let shared = FRLGSeedStore()

    /// When the downloaded copies were fetched; nil while the bundled ones
    /// are in use.
    private(set) var downloadedAt: Date?
    private(set) var updating = false
    private(set) var updateError: String?
    private var cache: [FRLGSeedSheet: FRLGSeedList] = [:]
    private let directory: URL

    init(directory: URL = URL.applicationSupportDirectory.appending(path: "FRLGSeeds", directoryHint: .isDirectory)) {
        self.directory = directory
        let stamp = try? String(contentsOf: directory.appending(path: "fetched-at.txt"), encoding: .utf8)
        downloadedAt = stamp.flatMap { try? Date($0.trimmingCharacters(in: .whitespacesAndNewlines), strategy: .iso8601) }
    }

    /// When the bundled copies were downloaded (`tools/update_frlg_seeds.sh`
    /// writes it).
    var bundledDate: String? {
        Bundle.main.url(forResource: "frlg-seeds-date", withExtension: "txt")
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) }?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func list(_ sheet: FRLGSeedSheet) async -> FRLGSeedList? {
        if let cached = cache[sheet] { return cached }
        let downloaded = directory.appending(path: sheet.resourceName + ".csv")
        let url = FileManager.default.fileExists(atPath: downloaded.path(percentEncoded: false))
            ? downloaded : Bundle.main.url(forResource: sheet.resourceName, withExtension: "csv")
        guard let url, let list = await Self.read(url, sheet) else { return nil }
        cache[sheet] = list
        return list
    }

    @concurrent
    nonisolated private static func read(_ url: URL, _ sheet: FRLGSeedSheet) async -> FRLGSeedList? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return FRLGSeedList(sheet: sheet, csv: text)
    }

    /// Downloads every list from its public sheet. Each has to read as a
    /// list before any replaces the copies in use.
    func update() async {
        updating = true
        updateError = nil
        defer { updating = false }
        do {
            var fetched: [(FRLGSeedSheet, Data)] = []
            for sheet in FRLGSeedSheet.allCases {
                let (data, response) = try await URLSession.shared.data(from: sheet.url)
                guard (response as? HTTPURLResponse)?.statusCode == 200,
                      let text = String(data: data, encoding: .utf8),
                      FRLGSeedList(sheet: sheet, csv: text).entries.count >= 100 else {
                    throw UpdateError.unreadable(sheet.rawValue)
                }
                fetched.append((sheet, data))
            }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for (sheet, data) in fetched {
                try data.write(to: directory.appending(path: sheet.resourceName + ".csv"), options: .atomic)
            }
            let now = Date()
            try now.ISO8601Format().write(to: directory.appending(path: "fetched-at.txt"), atomically: true, encoding: .utf8)
            downloadedAt = now
            cache = [:]
        } catch {
            updateError = error.localizedDescription
        }
    }

    enum UpdateError: LocalizedError {
        case unreadable(String)
        var errorDescription: String? {
            switch self {
            case .unreadable(let sheet): "The \(sheet) list didn't download as a seed list, so nothing was changed."
            }
        }
    }
}

// MARK: - What the player uses

/// The Finder's FRLG settings, kept between launches, and the index of
/// seeds they allow.
@MainActor @Observable
final class FRLGSeedSearch {
    var enabled: Bool { didSet { defaults.set(enabled, forKey: "frlg_enabled") } }
    var version: FRLGVersion {
        didSet {
            if !version.consoles.contains(console) { console = version.consoles[0] }
            defaults.set(version.rawValue, forKey: "frlg_version")
            if version != oldValue { applyDefaults() }
        }
    }
    var console: FRLGConsole { didSet { defaults.set(console.rawValue, forKey: "frlg_console") } }
    var sound: FRLGSound? { didSet { defaults.set(sound?.rawValue ?? "", forKey: "frlg_sound") } }
    var buttonMode: FRLGButtonMode? { didSet { defaults.set(buttonMode?.rawValue ?? "", forKey: "frlg_buttonMode") } }
    var seedButton: FRLGSeedButton? { didSet { defaults.set(seedButton?.rawValue ?? "", forKey: "frlg_seedButton") } }
    var held: FRLGHeldButton? { didSet { defaults.set(held?.rawValue ?? "", forKey: "frlg_held") } }
    var minimumAdvances: Int { didSet { defaults.set(minimumAdvances, forKey: "frlg_minimum") } }
    var maximumAdvances: Int { didSet { defaults.set(maximumAdvances, forKey: "frlg_maximum") } }
    var teachyTV: Bool { didSet { defaults.set(teachyTV, forKey: "frlg_teachyTV") } }
    var teachyTVMinimumOutside: Int { didSet { defaults.set(teachyTVMinimumOutside, forKey: "frlg_teachyTVOutside") } }

    /// The seeds the settings allow; nil until built.
    private(set) var index: FRLGSeedIndex?
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        enabled = defaults.object(forKey: "frlg_enabled") as? Bool ?? true
        let version = FRLGVersion(rawValue: defaults.string(forKey: "frlg_version") ?? "") ?? .fireRedSwitch
        self.version = version
        console = FRLGConsole(rawValue: defaults.string(forKey: "frlg_console") ?? "")
            .flatMap { version.consoles.contains($0) ? $0 : nil } ?? version.consoles[0]
        sound = FRLGSound(rawValue: defaults.string(forKey: "frlg_sound") ?? "")
        buttonMode = FRLGButtonMode(rawValue: defaults.string(forKey: "frlg_buttonMode") ?? "")
        seedButton = FRLGSeedButton(rawValue: defaults.string(forKey: "frlg_seedButton") ?? "")
        held = FRLGHeldButton(rawValue: defaults.string(forKey: "frlg_held") ?? "")
        minimumAdvances = defaults.object(forKey: "frlg_minimum") as? Int ?? 0
        maximumAdvances = defaults.object(forKey: "frlg_maximum") as? Int ?? 100_000
        teachyTV = defaults.bool(forKey: "frlg_teachyTV")
        teachyTVMinimumOutside = defaults.object(forKey: "frlg_teachyTVOutside") as? Int ?? 3600
        // The first time, start on what the list covers.
        if defaults.object(forKey: "frlg_buttonMode") == nil { applyDefaults() }
    }

    /// The game's own options, Mono sound and Help mode, pressing A: every
    /// list farms them.
    static let gameDefaults = FRLGSetting(sound: .mono, buttonMode: .help, seedButton: .a)

    /// Starts each option on a setting the version's list has: the game's
    /// defaults with no held button, or if a list lacks them, the first
    /// setting it has. Any is still there to choose.
    func applyDefaults() {
        let farmed = version.farmedSettings
        let setting = farmed.contains(Self.gameDefaults) ? Self.gameDefaults : farmed.first ?? Self.gameDefaults
        sound = setting.sound
        buttonMode = setting.buttonMode
        seedButton = setting.seedButton
        held = FRLGHeldButton.none
    }

    /// Whether the choices made can find any seed in the version's list.
    var isFarmed: Bool {
        version.isFarmed(sound: sound, buttonMode: buttonMode, seedButton: seedButton)
            && (held.map { version.heldButtons(buttonMode: buttonMode).contains($0) } ?? true)
    }

    var filter: FRLGSettingsFilter {
        FRLGSettingsFilter(sound: sound, buttonMode: buttonMode, seedButton: seedButton, held: held)
    }

    /// What the index depends on.
    struct IndexKey: Equatable {
        let version: FRLGVersion
        let filter: FRLGSettingsFilter
        let downloadedAt: Date?
    }

    var indexKey: IndexKey {
        IndexKey(version: version, filter: filter, downloadedAt: FRLGSeedStore.shared.downloadedAt)
    }

    func rebuildIndex(store: FRLGSeedStore = .shared) async {
        let key = indexKey
        guard let list = await store.list(key.version.sheet) else {
            index = nil
            return
        }
        let built = await Self.build(list, key.version, key.filter)
        guard key == indexKey else { return }
        index = built
    }

    @concurrent
    nonisolated private static func build(_ list: FRLGSeedList, _ version: FRLGVersion,
                                          _ filter: FRLGSettingsFilter) async -> FRLGSeedIndex {
        FRLGSeedIndex(list: list, version: version, filter: filter)
    }

    /// Teachy TV mode needs that many advances outside it, so they're the
    /// least a seed can be from its target.
    private var range: (minimum: UInt32, maximum: UInt32) {
        var minimum = max(0, minimumAdvances)
        if teachyTV, version.supportsTeachyTV { minimum = max(minimum, teachyTVMinimumOutside) }
        return (UInt32(clamping: minimum), UInt32(clamping: max(0, maximumAdvances)))
    }

    /// The fewest-advances seed that reaches `target` in range.
    func nearest(reaching target: UInt32) -> FRLGInitialSeed? {
        index?.nearest(reaching: target, minimum: range.minimum, maximum: range.maximum)
    }

    func seeds(reaching target: UInt32, limit: Int) -> [FRLGInitialSeed] {
        index?.seeds(reaching: target, minimum: range.minimum, maximum: range.maximum, limit: limit) ?? []
    }

    /// When to press, in milliseconds from startup.
    func seedTimeMS(_ seed: FRLGInitialSeed) -> Int {
        console.milliseconds(frames: Double(seed.seedTime) / 16)
    }

    /// The frame to press on after the seed is set: its advances, or with
    /// Teachy TV the frames spent there and the advances outside it.
    func targetFrame(_ seed: FRLGInitialSeed) -> (frame: UInt32, teachyTVFrames: UInt32) {
        guard teachyTV, version.supportsTeachyTV else { return (seed.advances, 0) }
        let split = TeachyTV.split(advances: seed.advances,
                                   minimumOutside: UInt32(clamping: max(0, teachyTVMinimumOutside)))
        return (split.ttvFrames + split.regularAdvances, split.ttvFrames)
    }
}

// MARK: - The settings card

/// The Finder's Initial Seed card, for FireRed and LeafGreen searches.
struct FRLGInitialSeedSection: View {
    @Bindable var search: FRLGSeedSearch
    /// Whether the Finder's game is FireRed (else LeafGreen).
    let fireRed: Bool
    private let store = FRLGSeedStore.shared

    var body: some View {
        SectionCard(title: "Initial Seed", icon: "power") {
            Toggle("Only targets I can reach", isOn: $search.enabled)
            Text("FireRed and LeafGreen seed the RNG when you press a button on the title screen. With this on, results are the targets reachable from a seed you can hit, fewest advances first.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if search.enabled {
                // Versions have long names, so the picker gets its own line.
                VStack(alignment: .leading, spacing: 2) {
                    Text("Version")
                    Picker("Version", selection: $search.version) {
                        ForEach(FRLGVersion.versions(fireRed: fireRed)) { Text($0.name).tag($0) }
                    }
                    .labelsHidden()
                }
                labeled("Console") {
                    Picker("Console", selection: $search.console) {
                        ForEach(search.version.consoles) { Text($0.name).tag($0) }
                    }
                }
                labeled("Sound") {
                    Picker("Sound", selection: $search.sound) {
                        Text("Any").tag(FRLGSound?.none)
                        ForEach(FRLGSound.allCases, id: \.self) { sound in
                            Text(marked(sound.name, search.version.farmedSounds.contains(sound))).tag(Optional(sound))
                        }
                    }
                }
                labeled("Button Mode") {
                    Picker("Button Mode", selection: $search.buttonMode) {
                        Text("Any").tag(FRLGButtonMode?.none)
                        ForEach(FRLGButtonMode.allCases, id: \.self) { mode in
                            Text(marked(mode.name, search.version.farmedButtonModes.contains(mode))).tag(Optional(mode))
                        }
                    }
                }
                labeled("Seed Button") {
                    Picker("Seed Button", selection: $search.seedButton) {
                        Text("Any").tag(FRLGSeedButton?.none)
                        ForEach(FRLGSeedButton.allCases, id: \.self) { button in
                            Text(marked(button.name, search.version.farmedSeedButtons.contains(button))).tag(Optional(button))
                        }
                    }
                }
                labeled("Held Button") {
                    Picker("Held Button", selection: $search.held) {
                        Text("Any").tag(FRLGHeldButton?.none)
                        ForEach(heldButtons, id: \.self) { held in
                            Text(marked(held.name, search.version.heldButtons(buttonMode: search.buttonMode).contains(held)))
                                .tag(Optional(held))
                        }
                    }
                }
                coverageNote
                RNGIntField(label: "Minimum Advances", value: $search.minimumAdvances)
                RNGIntField(label: "Maximum Advances", value: $search.maximumAdvances)
                if search.version.supportsTeachyTV {
                    Toggle("Teachy TV", isOn: $search.teachyTV)
                    if search.teachyTV {
                        RNGIntField(label: "Advances Outside Teachy TV", value: $search.teachyTVMinimumOutside)
                        Text("In the Teachy TV the RNG advances 313 times a frame, so most of a long wait can be spent there.")
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                seedListInfo
            }
        }
        .task(id: search.indexKey) { await search.rebuildIndex() }
        .onChange(of: fireRed, initial: true) {
            if search.version.isFireRed != fireRed {
                search.version = fireRed ? .fireRedSwitch : .leafGreenSwitch
            }
        }
    }

    /// A picker with its name beside it, since a menu picker shows only its
    /// value here.
    private func labeled(_ title: String, @ViewBuilder picker: () -> some View) -> some View {
        HStack {
            Text(title)
            Spacer(minLength: 8)
            picker().labelsHidden()
        }
    }

    /// The held buttons the version knows, in any button mode.
    private var heldButtons: [FRLGHeldButton] {
        let known = Set(FRLGHeldButtons.offsets(for: search.version).map(\.held))
        return FRLGHeldButton.allCases.filter(known.contains)
    }

    /// An option the version's list has no seeds for says so.
    private func marked(_ name: String, _ farmed: Bool) -> String {
        farmed ? name : "\(name) (not farmed)"
    }

    /// What a partly farmed list covers, and a warning when the choices
    /// made find nothing.
    @ViewBuilder
    private var coverageNote: some View {
        let version = search.version
        if !version.isFullyFarmed {
            Text("So far this version's seed list covers \(version.farmedSettings.map(\.name).joined(separator: "; ")). The community hasn't farmed the other settings yet, so they can't be searched.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        if !search.isFarmed {
            Label("No seeds are farmed for these settings on this version, so nothing can be found. Choose a setting without \"(not farmed)\", or set it to Any.",
                  systemImage: "exclamationmark.triangle")
                .font(.caption).foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var seedListInfo: some View {
        VStack(alignment: .leading, spacing: 6) {
            Group {
                if let index = search.index {
                    Text("\(index.count.formatted()) seeds you can hit with these settings, from the community's farmed list"
                         + (store.downloadedAt.map { ", updated \($0.formatted(date: .abbreviated, time: .omitted))." }
                            ?? store.bundledDate.map { " of \($0)." } ?? "."))
                } else {
                    Text("Loading the seed list…")
                }
            }
            .font(.caption).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            if store.updating {
                ProgressView().controlSize(.small)
            } else {
                Button("Update Seed Lists") { Task { await store.update() } }
                    .font(.subheadline)
            }
            if let error = store.updateError {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
    }
}

// MARK: - A result's seeds

/// One line under a Finder result: the seed that reaches it with the
/// fewest advances.
struct FRLGMatchLine: View {
    let seed: FRLGInitialSeed
    let search: FRLGSeedSearch

    var body: some View {
        Text("Seed \(String(format: "%04X", seed.seed)) · \(seed.advances.formatted()) advances · \(search.seedTimeMS(seed).formatted()) ms · \(seed.settingsName)")
            .font(.system(.caption2, design: .monospaced))
            .foregroundStyle(.secondary)
            .lineLimit(2)
    }
}

/// A target's reachable seeds, for its detail page.
struct FRLGInitialSeedList: View {
    let target: UInt32
    let search: FRLGSeedSearch
    /// Sends a seed's timing to the Timer: pre-timer (ms), target frame.
    var onSendToTimer: (FRLGInitialSeed, Int, UInt32) -> Void

    private static let shown = 100

    var body: some View {
        let seeds = FRLGHeldChoice.merged(search.seeds(reaching: target, limit: Self.shown))
        SectionCard(title: "Initial Seeds", icon: "power") {
            if seeds.isEmpty {
                Text("No seed you can hit with these settings reaches this target in \(search.minimumAdvances.formatted())–\(search.maximumAdvances.formatted()) advances.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                Text("Press the seed button at the seed time, then on the target frame. Fewest advances first\(seeds.count == Self.shown ? ", the first \(Self.shown)" : "").")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(seeds, id: \.seed) { choice in
                    row(choice)
                    Divider()
                }
            }
        }
    }

    private func row(_ choice: FRLGHeldChoice) -> some View {
        let seed = choice.seed
        let seedTime = search.seedTimeMS(seed)
        let target = search.targetFrame(seed)
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Seed \(String(format: "%04X", seed.seed))").font(.system(.subheadline, design: .monospaced).bold())
                Spacer()
                Text("\(seed.advances.formatted()) advances").font(.system(.caption, design: .monospaced))
            }
            Text(choice.settingsName).font(.caption)
            Text("Seed time \(seedTime.formatted()) ms · target frame \(target.frame.formatted())"
                 + (target.teachyTVFrames > 0 ? " (\(target.teachyTVFrames.formatted()) in Teachy TV)" : ""))
                .font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
            Button {
                onSendToTimer(seed, seedTime, target.frame)
            } label: {
                Label("Send to Timer", systemImage: "timer")
            }
            .font(.caption)
            .buttonStyle(.borderless)
        }
    }
}

/// One press that gives a seed, with every held button that gives it from
/// there (on Switch, holding R or L on the blackout screen does the same).
struct FRLGHeldChoice {
    let seed: FRLGInitialSeed
    let held: [FRLGHeldButton]

    /// "Mono · Help · A, holding Blackout R or Blackout L".
    var settingsName: String {
        let order = FRLGHeldButton.allCases
        let names = held.sorted { order.firstIndex(of: $0)! < order.firstIndex(of: $1)! }.map(\.name)
        return held == [.none] ? seed.setting.name : "\(seed.setting.name), holding \(names.joined(separator: " or "))"
    }

    /// Seeds in order, with neighbours that differ only by held button made
    /// one.
    static func merged(_ seeds: [FRLGInitialSeed]) -> [FRLGHeldChoice] {
        var merged: [FRLGHeldChoice] = []
        for seed in seeds {
            if let last = merged.last, last.seed.seed == seed.seed, last.seed.setting == seed.setting,
               last.seed.seedTime == seed.seedTime, last.seed.advances == seed.advances {
                merged[merged.count - 1] = FRLGHeldChoice(seed: last.seed, held: last.held + [seed.held])
            } else {
                merged.append(FRLGHeldChoice(seed: seed, held: [seed.held]))
            }
        }
        return merged
    }
}
