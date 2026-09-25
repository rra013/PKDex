//
//  TeamSearchModelTests.swift
//  PKDexTests
//
//  Covers `TeamSearchModel`, the state behind the Team Search tab: loading
//  and indexing a corpus, typing into chips and results, chip edits, how
//  load failures show, not refetching on every visit, and switching
//  regulation. A canned Limitless serves the teams, and the fixture
//  vocabulary stands in for the bundled one.
//

import Testing
import Foundation
@testable import PKDex

/// Serves the same events for any format, recording what was asked for.
private actor CannedLimitless: TeamCorpusFetching {
    let events: [CorpusEvent]
    var listError: Error?
    private(set) var formatsRequested: [String] = []

    init(_ events: [CorpusEvent]) { self.events = events }

    func tournaments(format: String, page: Int, limit: Int) async throws -> [LimitlessTournament] {
        formatsRequested.append(format)
        if let listError { throw listError }
        return page == 1 ? events.map(\.tournament) : []
    }

    func standings(tournamentID: String) async throws -> [LimitlessStanding] {
        events.first { $0.tournament.id == tournamentID }?.standings ?? []
    }

    func failList(with error: Error?) { listError = error }
}

@MainActor
@Suite("Team Search Model")
struct TeamSearchModelTests {

    private typealias F = TeamSearchFixtures

    private static let trickRoomTeam: [LimitlessStanding.TeamMember] = [
        F.member("Incineroar", moves: ["Fake Out"]), F.member("Garchomp"),
        F.member("Gardevoir", item: "Gardevoirite"), F.member("Rillaboom"),
        F.member("Farigiraf", moves: ["Trick Room"]), F.member("Kingambit"),
    ]
    private static let rainTeam: [LimitlessStanding.TeamMember] = F.six(
        ["Pelipper", "Charizard", "Dragonite", "Sneasler", "Torkoal", "Whimsicott"])

    private static func events() -> [CorpusEvent] {
        [F.event("e1", players: 32, [F.standing("alex", placing: 1, trickRoomTeam),
                                     F.standing("sam", placing: 2, rainTeam)])]
    }

    private static func model(_ fetcher: CannedLimitless, directory: URL,
                              regulation: ChampionsRegulation = .mC) -> TeamSearchModel {
        TeamSearchModel(
            regulation: regulation,
            store: TeamCorpusStore(fetcher: fetcher, directory: directory,
                                   now: { F.now }, sleep: { _ in }),
            loadVocabulary: { _ in F.vocabulary },
            now: { F.now })
    }

    private static func tempDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "TeamSearchModelTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    @Test("Loading shows popular compositions and where they came from")
    func loads() async {
        let dir = Self.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let model = Self.model(CannedLimitless(Self.events()), directory: dir)

        await model.load()

        #expect(model.status == .ready)
        #expect(model.results.count == 2)
        #expect(model.teamCount == 2)
        #expect(model.eventCount == 1)
        #expect(model.missingEventCount == 0)
        #expect(model.updatedAt == F.now)
        #expect(model.chips.isEmpty)
    }

    @Test("Typing becomes chips and filters the results")
    func typing() async {
        let dir = Self.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let model = Self.model(CannedLimitless(Self.events()), directory: dir)
        await model.load()

        model.setText("mega gardevoir, no pelipper, bulky")

        #expect(model.chips.map(\.label) == ["Mega Gardevoir", "No Pelipper", "bulky"])
        #expect(model.results.map { $0.teams[0].team.team.standing.player } == ["alex"])
    }

    @Test("Chips can flip between include and exclude, or be removed")
    func chipEdits() async throws {
        let dir = Self.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let model = Self.model(CannedLimitless(Self.events()), directory: dir)
        await model.load()
        model.setText("trick room")
        #expect(model.results.map { $0.teams[0].team.team.standing.player } == ["alex"])

        let style = try #require(model.chips.first)
        model.invert(style)
        #expect(model.chips.map(\.label) == ["No Trick Room"])
        #expect(model.results.map { $0.teams[0].team.team.standing.player } == ["sam"])

        model.remove(try #require(model.chips.first))
        #expect(model.chips.isEmpty)
        #expect(model.results.count == 2)

        // Typing again starts over from the text.
        model.setText("trick room")
        #expect(model.chips.map(\.label) == ["Trick Room"])
    }

    @Test("A failed first load shows the error; a failed refresh keeps the results")
    func failures() async {
        let dir = Self.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let fetcher = CannedLimitless(Self.events())
        await fetcher.failList(with: LimitlessAPIError.http(status: 500))
        let model = Self.model(fetcher, directory: dir)

        await model.load()
        #expect(model.status == .failed("Limitless returned an error (HTTP 500)."))

        await fetcher.failList(with: nil)
        await model.load(forceRefresh: true)
        #expect(model.status == .ready)

        await fetcher.failList(with: LimitlessAPIError.http(status: 404))
        await model.load(forceRefresh: true)
        #expect(model.status == .ready)
        #expect(model.results.count == 2)
        #expect(model.refreshError == "Limitless returned an error (HTTP 404).")
    }

    @Test("Coming back to the tab doesn't refetch while the data is fresh")
    func noRefetchWhileFresh() async {
        let dir = Self.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let fetcher = CannedLimitless(Self.events())
        let model = Self.model(fetcher, directory: dir)

        await model.load()
        await model.load()
        #expect(await fetcher.formatsRequested == ["M-C"])

        await model.load(forceRefresh: true)
        #expect(await fetcher.formatsRequested == ["M-C", "M-C"])
    }

    @Test("Switching regulation loads that regulation's teams")
    func switchingRegulation() async {
        let dir = Self.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let fetcher = CannedLimitless(Self.events())
        let model = Self.model(fetcher, directory: dir)
        await model.load()
        model.setText("trick room")

        model.regulation = .mB
        await model.load()

        #expect(await fetcher.formatsRequested == ["M-C", "M-B"])
        #expect(model.status == .ready)
        // The text is parsed again with the new regulation's vocabulary.
        #expect(model.chips.map(\.label) == ["Trick Room"])
    }
}
