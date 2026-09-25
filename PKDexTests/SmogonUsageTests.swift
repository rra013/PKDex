//
//  SmogonUsageTests.swift
//  PKDexTests
//
//  Covers `SmogonUsage` and `SmogonUsageStore`: reducing a chaos file to
//  usage and teammate shares, reading format and file names, and choosing
//  which month's stats to use (the regulation's own, or the latest earlier
//  one while it has none), with caching and offline fallback. A fake
//  directory listing stands in for smogon.com.
//

import Testing
import Foundation
@testable import PKDex

/// A canned smogon.com stats directory, recording requests.
private actor FakeSmogon: SmogonFetching {
    let monthFiles: [String: [String]]
    var offline = false
    private(set) var monthRequests = 0
    private(set) var chaosRequested: [String] = []

    init(_ monthFiles: [String: [String]]) { self.monthFiles = monthFiles }

    func months() async throws -> [String] {
        monthRequests += 1
        if offline { throw URLError(.notConnectedToInternet) }
        return Array(monthFiles.keys)
    }

    func chaosFiles(month: String) async throws -> [String] {
        if offline { throw URLError(.notConnectedToInternet) }
        return monthFiles[month] ?? []
    }

    func chaos(month: String, file: String) async throws -> Data {
        if offline { throw URLError(.notConnectedToInternet) }
        chaosRequested.append("\(month)/\(file)")
        return Data(TeamSearchFixtures.smogonChaosJSON.utf8)
    }

    func setOffline(_ value: Bool) { offline = value }
}

private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date
    init(_ date: Date) { current = date }
    var now: Date { lock.withLock { current } }
    func advance(hours: Double) { lock.withLock { current += hours * 3600 } }
}

@Suite("Smogon Usage")
struct SmogonUsageTests {

    private static let mb = "gen9championsvgc2026regmb-1760.json"
    private static let maFile = "gen9championsvgc2026regma-1760.json"

    private static func tempDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "SmogonUsageTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    private static func store(_ fetcher: FakeSmogon, clock: TestClock, directory: URL,
                              lookback: Int = 4) -> SmogonUsageStore {
        var configuration = SmogonUsageConfiguration()
        configuration.lookbackMonths = lookback
        return SmogonUsageStore(fetcher: fetcher, directory: directory,
                                configuration: configuration, now: { clock.now })
    }

    // MARK: Reducing

    @Test("A chaos file reduces to usage and teammate shares, most used first")
    func reduce() throws {
        let usage = try SmogonUsage.reduce(chaos: Data(TeamSearchFixtures.smogonChaosJSON.utf8),
                                           format: "gen9championsvgc2026regmb", month: "2026-08",
                                           rating: 1760)
        #expect(usage.battles == 1000)
        #expect(usage.regulation == .mB)
        #expect(usage.species.map(\.name) == ["Incineroar", "Garchomp", "Charizard-Mega-Y"])
        let incineroar = usage.species[0]
        #expect(incineroar.usage == 0.4)
        #expect(incineroar.teammates == [.init(name: "Garchomp", share: 0.5),
                                         .init(name: "Charizard-Mega-Y", share: 0.3)])
        #expect(usage.species[1].teammates.map(\.share) == [0.75, 0.7])

        let trimmed = try SmogonUsage.reduce(chaos: Data(TeamSearchFixtures.smogonChaosJSON.utf8),
                                             format: "f", month: "m", rating: 1760, teammateLimit: 1)
        #expect(trimmed.species[0].teammates.map(\.name) == ["Garchomp"])
    }

    @Test("Unreadable data throws")
    func unreadable() {
        #expect(throws: SmogonUsageError.unreadableStats) {
            try SmogonUsage.reduce(chaos: Data("[]".utf8), format: "f", month: "m", rating: 1760)
        }
    }

    @Test("Format and file names map to regulations")
    func names() {
        #expect(SmogonUsage.regulation(inFormat: "gen9championsvgc2026regmb") == .mB)
        #expect(SmogonUsage.regulation(inFormat: "gen9championsou") == nil)
        #expect(SmogonUsage.regulation(inFileName: Self.mb, rating: 1760)?.regulation == .mB)
        #expect(SmogonUsage.regulation(inFileName: "gen9championsvgc2026regmbbo3-1760.json", rating: 1760) == nil)
        #expect(SmogonUsage.regulation(inFileName: "gen9championsbssregmb-1760.json", rating: 1760) == nil)
        #expect(SmogonUsage.regulation(inFileName: "gen9championsvgc2026regmb-1500.json", rating: 1760) == nil)
    }

    // MARK: Choosing a month

    @Test("A regulation's own newest month is used")
    func ownNewestMonth() async throws {
        let dir = Self.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let fake = FakeSmogon(["2026-08": [Self.mb, "gen9championsvgc2026regmbbo3-1760.json",
                                           "gen9championsbssregmb-1760.json"],
                               "2026-07": [Self.mb]])
        let usage = try #require(try await Self.store(fake, clock: TestClock(TeamSearchFixtures.now),
                                                      directory: dir).usage(for: .mB))
        #expect(usage.month == "2026-08")
        #expect(usage.format == "gen9championsvgc2026regmb")
        #expect(await fake.chaosRequested == ["2026-08/\(Self.mb)"])
    }

    @Test("Without its own stats, a regulation uses the latest earlier one")
    func fallsBackToEarlierRegulation() async throws {
        let dir = Self.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let fake = FakeSmogon(["2026-08": [Self.mb], "2026-07": [Self.mb]])
        let usage = try #require(try await Self.store(fake, clock: TestClock(TeamSearchFixtures.now),
                                                      directory: dir).usage(for: .mC))
        #expect(usage.regulation == .mB)
        #expect(usage.month == "2026-08")
    }

    @Test("A regulation's own older month beats a newer month of another")
    func ownOlderMonthWins() async throws {
        let dir = Self.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let fake = FakeSmogon(["2026-08": [Self.mb], "2026-07": [Self.mb],
                               "2026-06": [Self.maFile, Self.mb]])
        let usage = try #require(try await Self.store(fake, clock: TestClock(TeamSearchFixtures.now),
                                                      directory: dir).usage(for: .mA))
        #expect(usage.month == "2026-06")
        #expect(usage.regulation == .mA)
    }

    @Test("Nothing usable within the lookback is nil")
    func nothingUsable() async throws {
        let dir = Self.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let fake = FakeSmogon(["2026-08": [Self.mb], "2026-07": [Self.mb], "2026-06": [Self.maFile]])
        let store = Self.store(fake, clock: TestClock(TeamSearchFixtures.now), directory: dir, lookback: 2)
        // M-A's own month is outside the lookback, and M-B is later than M-A.
        #expect(try await store.usage(for: .mA) == nil)

        let other = Self.tempDirectory()
        defer { try? FileManager.default.removeItem(at: other) }
        #expect(try await Self.store(FakeSmogon(["2026-08": ["gen9championsou-1760.json"]]),
                                     clock: TestClock(TeamSearchFixtures.now),
                                     directory: other).usage(for: .mB) == nil)
    }

    // MARK: Caching

    @Test("The choice and the stats are cached; a stale choice is checked again")
    func caching() async throws {
        let dir = Self.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let fake = FakeSmogon(["2026-08": [Self.mb]])
        let clock = TestClock(TeamSearchFixtures.now)
        let store = Self.store(fake, clock: clock, directory: dir)
        let first = try await store.usage(for: .mB)

        #expect(try await store.usage(for: .mB) == first)
        #expect(await store.cachedUsage(for: .mB) == first)
        #expect(await fake.monthRequests == 1)

        clock.advance(hours: 13)                     // past the 12 h choice TTL
        #expect(try await store.usage(for: .mB) == first)
        #expect(await fake.monthRequests == 2)
        #expect(await fake.chaosRequested.count == 1)   // the month itself isn't refetched
    }

    @Test("Offline, the last choice is used; with none cached it throws")
    func offline() async throws {
        let dir = Self.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let fake = FakeSmogon(["2026-08": [Self.mb]])
        let clock = TestClock(TeamSearchFixtures.now)
        let store = Self.store(fake, clock: clock, directory: dir)
        let first = try await store.usage(for: .mB)

        await fake.setOffline(true)
        clock.advance(hours: 13)
        #expect(try await store.usage(for: .mB) == first)

        let emptyDir = Self.tempDirectory()
        defer { try? FileManager.default.removeItem(at: emptyDir) }
        let empty = Self.store(fake, clock: clock, directory: emptyDir)
        await #expect(throws: URLError.self) { try await empty.usage(for: .mB) }
    }

    @Test("Clearing the cache removes choices and stats")
    func clearCache() async throws {
        let dir = Self.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = Self.store(FakeSmogon(["2026-08": [Self.mb]]),
                               clock: TestClock(TeamSearchFixtures.now), directory: dir)
        _ = try await store.usage(for: .mB)
        #expect(await store.cacheSize() > 0)
        try await store.clearCache()
        #expect(await store.cachedUsage(for: .mB) == nil)
        #expect(await store.cacheSize() == 0)
    }
}
