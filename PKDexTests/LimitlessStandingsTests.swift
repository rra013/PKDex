//
//  LimitlessStandingsTests.swift
//  PKDexTests
//
//  Covers standings from the Limitless API when some players have no
//  placing. The API sends `"placing": null` for players it didn't rank
//  (players who dropped) and lists them before first place. A non-optional
//  `placing` made the whole standings array fail to decode, so the
//  Tournaments tab showed an error for those events. Hermetic: the fixture
//  copies the API's shape, with made-up players.
//

import Testing
import Foundation
@testable import PKDex

@MainActor
@Suite("Limitless Standings")
struct LimitlessStandingsTests {

    // MARK: - Fixtures

    /// Two unranked players first, then placings 1–3, the way the API
    /// orders them. Includes keys the model doesn't read (`id`, `nature`)
    /// and an empty `deck` object, which the API also sends.
    private static let json = """
    [
      {"name": "Dropped Early", "country": "ES", "placing": null, "player": "dropped-early",
       "record": {"wins": 4, "losses": 2, "ties": 0}, "deck": {}, "drop": 6,
       "decklist": [{"id": "salamence", "name": "Salamence", "item": "Salamencite",
                     "ability": "Intimidate", "nature": "Timid", "tera": null,
                     "attacks": ["Protect", "Tailwind", "Draco Meteor", "Hyper Voice"]}]},
      {"name": "Dropped Late", "country": null, "placing": null, "player": "dropped-late",
       "record": {"wins": 4, "losses": 1, "ties": 0}, "deck": {}, "drop": 6, "decklist": null},
      {"name": "Winner", "country": "US", "placing": 1, "player": "winner",
       "record": {"wins": 9, "losses": 1, "ties": 0}, "deck": {}, "drop": null, "decklist": null},
      {"name": "Runner Up", "country": "JP", "placing": 2, "player": "runner-up",
       "record": {"wins": 8, "losses": 2, "ties": 0}, "deck": {}, "drop": null, "decklist": null},
      {"name": "Third", "country": "GB", "placing": 3, "player": "third",
       "record": {"wins": 7, "losses": 2, "ties": 0}, "deck": {}, "drop": null, "decklist": null}
    ]
    """

    private static func decode() throws -> [LimitlessStanding] {
        try JSONDecoder().decode([LimitlessStanding].self, from: Data(json.utf8))
    }

    // MARK: - Decoding

    @Test("Standings with null placings decode")
    func nullPlacingsDecode() throws {
        let standings = try Self.decode()
        #expect(standings.count == 5)
        #expect(standings.map(\.placing) == [nil, nil, 1, 2, 3])
        #expect(standings[0].drop == 6)
        #expect(standings[0].decklist?.first?.attacks?.count == 4)
    }

    // MARK: - Ordering

    @Test("Ranked players come first; unranked keep the API's order")
    func sortedByPlacing() throws {
        let standings = try Self.decode()
        let sorted = LimitlessStanding.sortedByPlacing(standings)
        #expect(sorted.map(\.player) ==
                ["winner", "runner-up", "third", "dropped-early", "dropped-late"])
    }

    @Test("Sorting fixes ranked players that arrive out of order")
    func sortedByPlacingReordersRanked() throws {
        let standings = Array(try Self.decode().reversed())
        let sorted = LimitlessStanding.sortedByPlacing(standings)
        #expect(sorted.map(\.placing) == [1, 2, 3, nil, nil])
        #expect(sorted.suffix(2).map(\.player) == ["dropped-late", "dropped-early"])
    }

    // MARK: - Placing filter

    @Test("Unranked players only show under All")
    func placingFilter() {
        typealias Filter = TournamentDetailView.PlacingFilter
        #expect(Filter.all.includes(placing: nil))
        #expect(Filter.all.includes(placing: 300))
        #expect(!Filter.top8.includes(placing: nil))
        #expect(Filter.top8.includes(placing: 8))
        #expect(!Filter.top8.includes(placing: 9))
    }
}
