//
//  TeamCorpusStoreTests.swift
//  PKDexTests
//
//  Covers `TeamCorpusStore`: which events and teams make up a corpus, what
//  is cached and when it's fetched again, how failures degrade, and retries
//  after rate limits. A fake Limitless records every request and can fail on
//  cue, a settable clock drives the TTL and "final" rules, a recorded sleep
//  stands in for waiting, and each test gets its own temporary cache
//  directory.
//

import Testing
import Foundation
@testable import PKDex

/// Canned Limitless responses, recording every request.
private actor FakeLimitless: TeamCorpusFetching {
    var pages: [[LimitlessTournament]]
    var standingsByID: [String: [LimitlessStanding]]
    var failingStandings: Set<String> = []
    var listFails = false
    /// Errors to throw, in order, before a request succeeds.
    var scriptedStandingsErrors: [String: [LimitlessAPIError]] = [:]
    var scriptedListErrors: [LimitlessAPIError] = []
    private(set) var pagesRequested: [Int] = []
    private(set) var standingsRequested: [String] = []

    init(pages: [[LimitlessTournament]], standings: [String: [LimitlessStanding]]) {
        self.pages = pages
        self.standingsByID = standings
    }

    func tournaments(format: String, page: Int, limit: Int) async throws -> [LimitlessTournament] {
        pagesRequested.append(page)
        if listFails { throw URLError(.notConnectedToInternet) }
        if !scriptedListErrors.isEmpty { throw scriptedListErrors.removeFirst() }
        return page <= pages.count ? pages[page - 1] : []
    }

    func standings(tournamentID: String) async throws -> [LimitlessStanding] {
        standingsRequested.append(tournamentID)
        if failingStandings.contains(tournamentID) { throw URLError(.badServerResponse) }
        if let error = scriptedStandingsErrors[tournamentID]?.first {
            scriptedStandingsErrors[tournamentID]?.removeFirst()
            throw error
        }
        return standingsByID[tournamentID] ?? []
    }

    func setFailingStandings(_ ids: Set<String>) { failingStandings = ids }
    func script(standings id: String, _ errors: [LimitlessAPIError]) {
        scriptedStandingsErrors[id] = errors
    }
    func script(list errors: [LimitlessAPIError]) { scriptedListErrors = errors }
    func setListFails(_ fails: Bool) { listFails = fails }
    func resetRequests() { pagesRequested = []; standingsRequested = [] }
}

private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date
    init(_ date: Date) { current = date }
    var now: Date { lock.withLock { current } }
    func advance(hours: Double) { lock.withLock { current += hours * 3600 } }
}

/// Records the waits the store asks for, without waiting.
private final class SleepLog: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [TimeInterval] = []
    func append(_ value: TimeInterval) { lock.withLock { values.append(value) } }
    var all: [TimeInterval] { lock.withLock { values } }
}

/// Collects progress callbacks, which arrive from the store's actor.
private final class ProgressLog: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [TeamCorpusStore.FetchProgress] = []
    func append(_ value: TeamCorpusStore.FetchProgress) { lock.withLock { values.append(value) } }
    var all: [TeamCorpusStore.FetchProgress] { lock.withLock { values } }
}

@Suite("Team Corpus Store")
struct TeamCorpusStoreTests {

    // MARK: - Fixtures

    /// Noon UTC, 2026-09-24.
    private static let t0 = Date(timeIntervalSince1970: 1_790_251_200)

    private static func tournament(_ id: String, date: String, players: Int) -> LimitlessTournament {
        LimitlessTournament(id: id, name: "Event \(id)", game: "VGC", format: "M-C",
                            date: date, players: players)
    }

    private static func standing(_ player: String, placing: Int?,
                                 team: [String]?) -> LimitlessStanding {
        LimitlessStanding(
            player: player, name: player.capitalized, country: nil, placing: placing,
            record: nil, deck: nil,
            decklist: team?.map {
                .init(name: $0, limitlessID: nil, item: nil, ability: nil,
                      attacks: ["Protect"], nature: nil, tera: nil)
            },
            drop: placing == nil ? 3 : nil)
    }

    /// Four days old, so its standings are final as soon as they're fetched.
    private static let settled = tournament("settled", date: "2026-09-20T12:00:00.000Z", players: 64)
    /// Started two hours before `t0`: not final yet.
    private static let running = tournament("running", date: "2026-09-24T10:00:00.000Z", players: 32)
    /// Under `minPlayers`.
    private static let small = tournament("small", date: "2026-09-22T12:00:00.000Z", players: 8)

    private static func fake() -> FakeLimitless {
        FakeLimitless(
            pages: [[running, small, settled]],   // newest first, like the API
            standings: [
                "settled": [
                    // The API lists unranked players first.
                    standing("dropped", placing: nil, team: ["Kingambit", "Sneasler"]),
                    standing("winner", placing: 1, team: ["Incineroar", "Garchomp"]),
                    standing("nolist", placing: 2, team: nil),
                ],
                "running": [standing("leader", placing: 1, team: ["Rillaboom", "Gholdengo"])],
                "small": [standing("tiny", placing: 1, team: ["Pikachu"])],
            ])
    }

    private static func tempDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "TeamCorpusStoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    private static func store(_ fetcher: FakeLimitless, clock: TestClock, directory: URL,
                              configuration: TeamCorpusConfiguration = TeamCorpusConfiguration(),
                              sleeps: SleepLog = SleepLog()) -> TeamCorpusStore {
        TeamCorpusStore(fetcher: fetcher, directory: directory,
                        configuration: configuration, now: { clock.now },
                        sleep: { sleeps.append($0) })
    }

    // MARK: - Building

    @Test("A corpus holds every published team from events big enough to count")
    func buildsCorpus() async throws {
        let dir = Self.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let fake = Self.fake()
        let store = Self.store(fake, clock: TestClock(Self.t0), directory: dir)

        let corpus = try await store.corpus(format: "M-C")

        #expect(corpus.events.map(\.tournament.id) == ["running", "settled"])
        // Newest event first; within an event by placing, unranked last;
        // players without a decklist left out.
        #expect(corpus.teams.map(\.id) == ["running/leader", "settled/winner", "settled/dropped"])
        #expect(corpus.teams[1].members.map(\.name) == ["Incineroar", "Garchomp"])
        #expect(corpus.missingEvents.isEmpty)
        #expect(await fake.standingsRequested.sorted() == ["running", "settled"])
    }

    @Test("The cached corpus loads from disk without the network")
    func loadsFromDisk() async throws {
        let dir = Self.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let clock = TestClock(Self.t0)
        _ = try await Self.store(Self.fake(), clock: clock, directory: dir).corpus(format: "M-C")

        let offline = Self.fake()
        await offline.setListFails(true)
        let reopened = Self.store(offline, clock: clock, directory: dir)
        let corpus = try #require(await reopened.cachedCorpus(format: "M-C"))

        #expect(corpus.teams.map(\.id) == ["running/leader", "settled/winner", "settled/dropped"])
        #expect(corpus.listFetchedAt == Self.t0)
        #expect(await offline.pagesRequested.isEmpty)
        #expect(await reopened.cachedCorpus(format: "M-B") == nil)
    }

    // MARK: - Refreshing

    @Test("Within the list TTL, nothing is fetched again")
    func freshCacheIsReused() async throws {
        let dir = Self.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let fake = Self.fake(), clock = TestClock(Self.t0)
        let store = Self.store(fake, clock: clock, directory: dir)
        _ = try await store.corpus(format: "M-C")
        await fake.resetRequests()

        clock.advance(hours: 1)
        let corpus = try await store.corpus(format: "M-C")

        #expect(corpus.teams.count == 3)
        #expect(await fake.pagesRequested.isEmpty)
        #expect(await fake.standingsRequested.isEmpty)
    }

    @Test("Past the TTL, the list and running events are fetched again, final ones never")
    func staleCacheRefreshesRunningEvents() async throws {
        let dir = Self.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let fake = Self.fake(), clock = TestClock(Self.t0)
        let store = Self.store(fake, clock: clock, directory: dir)
        _ = try await store.corpus(format: "M-C")
        await fake.resetRequests()

        clock.advance(hours: 7)
        _ = try await store.corpus(format: "M-C")

        #expect(await fake.pagesRequested == [1])
        #expect(await fake.standingsRequested == ["running"])
    }

    @Test("A forced refresh skips the TTL but still never refetches final events")
    func forcedRefresh() async throws {
        let dir = Self.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let fake = Self.fake(), clock = TestClock(Self.t0)
        let store = Self.store(fake, clock: clock, directory: dir)
        _ = try await store.corpus(format: "M-C")
        await fake.resetRequests()

        clock.advance(hours: 1)
        _ = try await store.corpus(format: "M-C", forceRefresh: true)

        #expect(await fake.pagesRequested == [1])
        #expect(await fake.standingsRequested == ["running"])
    }

    // MARK: - Failures

    @Test("An event that fails with nothing cached is reported missing")
    func failedEventWithoutCache() async throws {
        let dir = Self.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let fake = Self.fake()
        await fake.setFailingStandings(["running"])
        let corpus = try await Self.store(fake, clock: TestClock(Self.t0), directory: dir)
            .corpus(format: "M-C")

        #expect(corpus.events.map(\.tournament.id) == ["settled"])
        #expect(corpus.missingEvents.map(\.id) == ["running"])
    }

    @Test("An event that fails keeps its cached standings")
    func failedEventKeepsCache() async throws {
        let dir = Self.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let fake = Self.fake(), clock = TestClock(Self.t0)
        let store = Self.store(fake, clock: clock, directory: dir)
        _ = try await store.corpus(format: "M-C")

        await fake.setFailingStandings(["running"])
        clock.advance(hours: 7)
        let corpus = try await store.corpus(format: "M-C")

        #expect(corpus.teams.map(\.id).contains("running/leader"))
        #expect(corpus.missingEvents.isEmpty)
    }

    @Test("A failed list crawl uses the cached list; with no cache it throws")
    func failedListCrawl() async throws {
        let dir = Self.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let fake = Self.fake(), clock = TestClock(Self.t0)
        let store = Self.store(fake, clock: clock, directory: dir)

        await fake.setListFails(true)
        await #expect(throws: URLError.self) { try await store.corpus(format: "M-C") }

        await fake.setListFails(false)
        _ = try await store.corpus(format: "M-C")
        await fake.setListFails(true)
        clock.advance(hours: 7)
        let corpus = try await store.corpus(format: "M-C")
        #expect(corpus.listFetchedAt == Self.t0)
        #expect(corpus.teams.count == 3)
        #expect(corpus.listRefreshError != nil)
    }

    // MARK: - Retries

    @Test("A rate-limited event waits out Retry-After, then loads")
    func retryAfterRateLimit() async throws {
        let dir = Self.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let fake = Self.fake(), sleeps = SleepLog()
        await fake.script(standings: "running", [.rateLimited(retryAfter: 5), .rateLimited(retryAfter: 5)])
        let corpus = try await Self.store(fake, clock: TestClock(Self.t0), directory: dir,
                                          sleeps: sleeps).corpus(format: "M-C")

        #expect(corpus.teams.map(\.id).contains("running/leader"))
        #expect(corpus.missingEvents.isEmpty)
        #expect(sleeps.all == [5, 5])
        #expect(await fake.standingsRequested.filter { $0 == "running" }.count == 3)
    }

    @Test("Without Retry-After the wait doubles, is capped, and gives up after maxRetries")
    func backoffGivesUp() async throws {
        let dir = Self.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let fake = Self.fake(), sleeps = SleepLog()
        await fake.script(standings: "running", Array(repeating: .rateLimited(retryAfter: nil), count: 10))
        var configuration = TeamCorpusConfiguration()
        configuration.initialBackoff = 2
        configuration.maxBackoff = 5
        configuration.maxRetries = 3
        let corpus = try await Self.store(fake, clock: TestClock(Self.t0), directory: dir,
                                          configuration: configuration, sleeps: sleeps)
            .corpus(format: "M-C")

        #expect(sleeps.all == [2, 4, 5])
        #expect(corpus.missingEvents.map(\.id) == ["running"])
        #expect(await fake.standingsRequested.filter { $0 == "running" }.count == 4)
    }

    @Test("A long Retry-After is capped at maxBackoff")
    func retryAfterCapped() async throws {
        let dir = Self.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let fake = Self.fake(), sleeps = SleepLog()
        await fake.script(standings: "running", [.rateLimited(retryAfter: 600)])
        _ = try await Self.store(fake, clock: TestClock(Self.t0), directory: dir, sleeps: sleeps)
            .corpus(format: "M-C")
        #expect(sleeps.all == [60])
    }

    @Test("Server errors are retried; other errors aren't")
    func whatIsRetried() async throws {
        let dir = Self.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let fake = Self.fake(), sleeps = SleepLog()
        await fake.script(standings: "running", [.http(status: 503)])
        await fake.script(standings: "settled", [.http(status: 404)])
        let corpus = try await Self.store(fake, clock: TestClock(Self.t0), directory: dir,
                                          sleeps: sleeps).corpus(format: "M-C")

        #expect(sleeps.all == [2])
        #expect(corpus.events.map(\.tournament.id) == ["running"])
        #expect(corpus.missingEvents.map(\.id) == ["settled"])
    }

    @Test("The tournament list is retried too")
    func listRetried() async throws {
        let dir = Self.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let fake = Self.fake(), sleeps = SleepLog()
        await fake.script(list: [.rateLimited(retryAfter: 1)])
        let corpus = try await Self.store(fake, clock: TestClock(Self.t0), directory: dir,
                                          sleeps: sleeps).corpus(format: "M-C")

        #expect(sleeps.all == [1])
        #expect(await fake.pagesRequested == [1, 1])
        #expect(corpus.teams.count == 3)
    }

    // MARK: - Crawl limits

    @Test("The crawl stops at a short page")
    func stopsAtShortPage() async throws {
        let dir = Self.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let fake = FakeLimitless(pages: [[Self.running, Self.settled], [Self.small]],
                                 standings: [:])
        var configuration = TeamCorpusConfiguration()
        configuration.pageSize = 2
        _ = try await Self.store(fake, clock: TestClock(Self.t0), directory: dir,
                                 configuration: configuration).corpus(format: "M-C")
        #expect(await fake.pagesRequested == [1, 2])
    }

    @Test("The crawl stops once it has maxEvents events")
    func stopsAtMaxEvents() async throws {
        let dir = Self.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let fake = FakeLimitless(pages: [[Self.running, Self.settled], [Self.small]],
                                 standings: [:])
        var configuration = TeamCorpusConfiguration()
        configuration.pageSize = 2
        configuration.maxEvents = 1
        let corpus = try await Self.store(fake, clock: TestClock(Self.t0), directory: dir,
                                          configuration: configuration).corpus(format: "M-C")
        #expect(await fake.pagesRequested == [1])
        #expect(corpus.events.map(\.tournament.id) == ["running"])
    }

    // MARK: - Progress and cache management

    @Test("Progress counts cached events as done and ends at the total")
    func progress() async throws {
        let dir = Self.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let fake = Self.fake(), clock = TestClock(Self.t0)
        let store = Self.store(fake, clock: clock, directory: dir)

        let first = ProgressLog()
        _ = try await store.corpus(format: "M-C") { first.append($0) }
        #expect(first.all.first == .init(completed: 0, total: 2))
        #expect(first.all.last == .init(completed: 2, total: 2))

        clock.advance(hours: 7)
        let second = ProgressLog()
        _ = try await store.corpus(format: "M-C") { second.append($0) }
        #expect(second.all.first == .init(completed: 1, total: 2))   // "settled" is final
        #expect(second.all.last == .init(completed: 2, total: 2))
    }

    @Test("Clearing the cache removes lists, events and the in-memory corpus")
    func clearCache() async throws {
        let dir = Self.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = Self.store(Self.fake(), clock: TestClock(Self.t0), directory: dir)
        _ = try await store.corpus(format: "M-C")
        #expect(await store.cacheSize() > 0)

        try await store.clearCache()

        #expect(await store.cachedCorpus(format: "M-C") == nil)
        #expect(await store.cacheSize() == 0)
    }
}
