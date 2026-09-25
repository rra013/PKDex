//
//  SmogonUsage.swift
//  PKDex
//
//  Smogon's monthly ladder usage statistics for Champions doubles, as Team
//  Search uses them: how often each Pokémon is used and which teammates it's
//  paired with. Smogon publishes whole-team data only as these pairwise
//  statistics, so they complement Limitless's tournament teams rather than
//  replace them.
//
//  Stats are published monthly per format (gen9championsvgc2026regmb), at
//  https://www.smogon.com/stats/<month>/chaos/<format>-<rating>.json. Each
//  file is about 13 MB, so `SmogonUsageStore` reduces it to what Team Search
//  needs and caches that. A published month never changes, so the cache
//  never expires; only the choice of month does.
//
//  A regulation has no stats until the month after it starts, so when the
//  selected regulation has none, the store falls back to the newest month
//  of an earlier regulation. `SmogonUsage.format` and `month` say which one
//  it used, for labelling.
//

import Foundation

// MARK: - Usage

nonisolated struct SmogonUsage: Codable, Sendable, Equatable {

    struct Teammate: Codable, Sendable, Equatable {
        /// Smogon's species name: "Charizard-Mega-Y".
        let name: String
        /// Share of this species' teams that also run the teammate, 0–1.
        let share: Double
    }

    struct Species: Codable, Sendable, Equatable {
        let name: String
        /// Share of all teams that run it, 0–1.
        let usage: Double
        /// Most-paired first.
        let teammates: [Teammate]
    }

    /// Smogon's format ID: "gen9championsvgc2026regmb".
    let format: String
    /// "2026-08".
    let month: String
    /// The ladder rating cutoff the stats are weighted for.
    let rating: Int
    let battles: Int
    /// Most-used first.
    let species: [Species]

    /// The Champions regulation the format is for, from its "reg<id>" suffix.
    var regulation: ChampionsRegulation? { Self.regulation(inFormat: format) }

    /// Reads a chaos JSON file. A teammate's share is its co-occurrence
    /// weight divided by the species' own weight, which is the sum of its
    /// ability weights: the same figure Smogon's moveset files print.
    static func reduce(chaos: Data, format: String, month: String, rating: Int,
                       teammateLimit: Int = 24) throws -> SmogonUsage {
        guard let root = try JSONSerialization.jsonObject(with: chaos) as? [String: Any],
              let data = root["data"] as? [String: [String: Any]] else {
            throw SmogonUsageError.unreadableStats
        }
        let info = root["info"] as? [String: Any]
        let battles = (info?["number of battles"] as? NSNumber)?.intValue ?? 0

        var species: [Species] = []
        for (name, entry) in data {
            let usage = (entry["usage"] as? NSNumber)?.doubleValue ?? 0
            let weight = (entry["Abilities"] as? [String: NSNumber] ?? [:])
                .values.reduce(0) { $0 + $1.doubleValue }
            guard usage > 0, weight > 0 else { continue }
            let counts = entry["Teammates"] as? [String: NSNumber] ?? [:]
            var teammates: [Teammate] = []
            for (mate, count) in counts {
                let share = count.doubleValue / weight
                if share > 0 { teammates.append(Teammate(name: mate, share: share)) }
            }
            teammates.sort { $0.share != $1.share ? $0.share > $1.share : $0.name < $1.name }
            species.append(Species(name: name, usage: usage,
                                   teammates: Array(teammates.prefix(teammateLimit))))
        }
        species.sort { $0.usage != $1.usage ? $0.usage > $1.usage : $0.name < $1.name }
        return SmogonUsage(format: format, month: month, rating: rating, battles: battles,
                           species: species)
    }

    /// Smogon's doubles format for a regulation ends in "reg" plus the
    /// regulation's ID without its hyphen: M-B → "regmb".
    static func regulation(inFormat format: String) -> ChampionsRegulation? {
        guard let range = format.range(of: "reg", options: .backwards) else { return nil }
        let id = format[range.upperBound...]
        return ChampionsRegulation.allCases.first { $0.rawValue.replacingOccurrences(of: "-", with: "") == id }
    }

    /// A chaos file name for a Champions doubles regulation at `rating`:
    /// "gen9championsvgc2026regmb-1760.json" → M-B. The best-of-three
    /// variant ("…regmbbo3-1760.json") and other formats don't match.
    static func regulation(inFileName file: String, rating: Int) -> (format: String, regulation: ChampionsRegulation)? {
        let suffix = "-\(rating).json"
        guard file.hasPrefix("gen9championsvgc"), file.hasSuffix(suffix) else { return nil }
        let format = String(file.dropLast(suffix.count))
        guard let regulation = regulation(inFormat: format) else { return nil }
        return (format, regulation)
    }
}

nonisolated enum SmogonUsageError: LocalizedError, Equatable, Sendable {
    case unreadableStats
    case http(status: Int)

    var errorDescription: String? {
        switch self {
        case .unreadableStats: return "Smogon's usage stats couldn't be read."
        case .http(let status): return "Smogon returned an error (HTTP \(status))."
        }
    }
}

// MARK: - Fetching

/// Smogon's stats directory. A protocol so tests can serve canned listings.
nonisolated protocol SmogonFetching: Sendable {
    /// Month directories on the stats index, e.g. "2026-08".
    func months() async throws -> [String]
    /// File names in a month's chaos directory.
    func chaosFiles(month: String) async throws -> [String]
    func chaos(month: String, file: String) async throws -> Data
}

nonisolated struct SmogonLiveFetcher: SmogonFetching {
    private static let base = URL(string: "https://www.smogon.com/stats/")!

    func months() async throws -> [String] {
        try await Self.links(at: Self.base)
            .filter { $0.range(of: #"^\d{4}-\d{2}/$"#, options: .regularExpression) != nil }
            .map { String($0.dropLast()) }
    }

    func chaosFiles(month: String) async throws -> [String] {
        try await Self.links(at: Self.base.appending(path: "\(month)/chaos/"))
            .filter { $0.hasSuffix(".json") }
    }

    func chaos(month: String, file: String) async throws -> Data {
        try await Self.get(Self.base.appending(path: "\(month)/chaos/\(file)"))
    }

    /// The href targets on a directory listing page.
    private static func links(at url: URL) async throws -> [String] {
        let html = String(decoding: try await get(url), as: UTF8.self)
        let regex = try NSRegularExpression(pattern: #"href="([^"]+)""#)
        return regex.matches(in: html, range: NSRange(html.startIndex..., in: html)).compactMap {
            Range($0.range(at: 1), in: html).map { String(html[$0]) }
        }
    }

    private static func get(_ url: URL) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw SmogonUsageError.http(status: http.statusCode)
        }
        return data
    }
}

// MARK: - Store

nonisolated struct SmogonUsageConfiguration: Sendable {
    /// The ladder cutoff. 1760 weights the stats toward strong players.
    var rating = 1760
    /// How many recent months to search for the selected regulation's own stats.
    var lookbackMonths = 4
    /// How long the choice of month is reused before checking for a newer one.
    var resolutionTTL: TimeInterval = 12 * 60 * 60
    var teammateLimit = 24
}

actor SmogonUsageStore {
    static let shared = SmogonUsageStore()

    private let fetcher: any SmogonFetching
    private let directory: URL
    private let configuration: SmogonUsageConfiguration
    private let now: @Sendable () -> Date

    nonisolated private static let cacheVersion = "v1"

    nonisolated static var defaultDirectory: URL {
        URL.cachesDirectory.appending(path: "SmogonUsage", directoryHint: .isDirectory)
    }

    init(fetcher: any SmogonFetching = SmogonLiveFetcher(),
         directory: URL = SmogonUsageStore.defaultDirectory,
         configuration: SmogonUsageConfiguration = SmogonUsageConfiguration(),
         now: @escaping @Sendable () -> Date = { Date() }) {
        self.fetcher = fetcher
        self.directory = directory.appending(path: Self.cacheVersion, directoryHint: .isDirectory)
        self.configuration = configuration
        self.now = now
    }

    /// The stats to use for `regulation`, without touching the network: the
    /// last month chosen for it, if its stats are cached.
    func cachedUsage(for regulation: ChampionsRegulation) -> SmogonUsage? {
        guard let choice = readChoice(for: regulation), let file = choice.file else { return nil }
        return readUsage(month: choice.month ?? "", file: file)
    }

    /// The stats to use for `regulation`: its own newest month within
    /// `lookbackMonths` if Smogon has one, otherwise the newest month of the
    /// latest earlier regulation. nil when Smogon has nothing usable.
    ///
    /// If Smogon can't be reached, the last choice is used even if stale.
    /// Throws only when there's no cached choice to fall back on.
    func usage(for regulation: ChampionsRegulation, forceRefresh: Bool = false) async throws -> SmogonUsage? {
        let cachedChoice = readChoice(for: regulation)
        if !forceRefresh, let cachedChoice,
           now().timeIntervalSince(cachedChoice.chosenAt) < configuration.resolutionTTL {
            return try await load(cachedChoice)
        }
        let choice: Choice
        do {
            choice = try await choose(for: regulation)
        } catch {
            guard let cachedChoice else { throw error }
            return try await load(cachedChoice)
        }
        write(choice, to: choiceURL(for: regulation))
        return try await load(choice)
    }

    func clearCache() throws {
        if FileManager.default.fileExists(atPath: directory.path()) {
            try FileManager.default.removeItem(at: directory)
        }
    }

    /// Bytes on disk, for Settings.
    func cacheSize() -> Int {
        guard let files = FileManager.default.enumerator(
            at: directory, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total = 0
        for case let url as URL in files {
            total += (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        }
        return total
    }

    // MARK: Choosing a month

    /// Which month and file to use for a regulation. `file` is nil when
    /// Smogon has nothing usable.
    private struct Choice: Codable {
        let chosenAt: Date
        let month: String?
        let file: String?
    }

    private func choose(for regulation: ChampionsRegulation) async throws -> Choice {
        let months = try await fetcher.months().sorted(by: >).prefix(configuration.lookbackMonths)
        let requestedStart = regulation.validFrom ?? .distantFuture
        var fallback: (month: String, file: String, start: Date)?
        for month in months {
            let files = try await fetcher.chaosFiles(month: month)
            for file in files {
                guard let hit = SmogonUsage.regulation(inFileName: file, rating: configuration.rating)
                else { continue }
                if hit.regulation == regulation {
                    return Choice(chosenAt: now(), month: month, file: file)
                }
                // An earlier regulation, newest month first, then newest regulation.
                let start = hit.regulation.validFrom ?? .distantPast
                if start <= requestedStart, fallback == nil
                    || (fallback!.month == month && start > fallback!.start) {
                    fallback = (month, file, start)
                }
            }
            // Keep looking in older months for the regulation's own stats,
            // but never prefer an older month's fallback.
        }
        return Choice(chosenAt: now(), month: fallback?.month, file: fallback?.file)
    }

    // MARK: Loading a month

    private func load(_ choice: Choice) async throws -> SmogonUsage? {
        guard let month = choice.month, let file = choice.file else { return nil }
        if let cached = readUsage(month: month, file: file) { return cached }
        let data = try await fetcher.chaos(month: month, file: file)
        let format = String(file.dropLast("-\(configuration.rating).json".count))
        let usage = try SmogonUsage.reduce(chaos: data, format: format, month: month,
                                           rating: configuration.rating,
                                           teammateLimit: configuration.teammateLimit)
        write(usage, to: usageURL(month: month, file: file))
        return usage
    }

    // MARK: Disk

    private func choiceURL(for regulation: ChampionsRegulation) -> URL {
        directory.appending(path: "choice-\(regulation.rawValue).json")
    }

    private func usageURL(month: String, file: String) -> URL {
        directory.appending(path: "usage").appending(path: "\(month)-\(file)")
    }

    private func readChoice(for regulation: ChampionsRegulation) -> Choice? {
        read(Choice.self, from: choiceURL(for: regulation))
    }

    private func readUsage(month: String, file: String) -> SmogonUsage? {
        read(SmogonUsage.self, from: usageURL(month: month, file: file))
    }

    private func read<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    /// Best effort: a failed write only costs a refetch later.
    private func write(_ value: some Encodable, to url: URL) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}
