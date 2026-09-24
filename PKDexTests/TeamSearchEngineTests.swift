//
//  TeamSearchEngineTests.swift
//  PKDexTests
//
//  Covers `TeamSearchIndex` and `TeamSearchEngine`: style tagging from
//  moves, abilities and Mega Stones; the filters; partial matches; folding
//  near-identical teams; and ranking by placement and recency, with a fixed
//  clock. Uses the fixture vocabulary and synthetic events.
//

import Testing
import Foundation
@testable import PKDex

@Suite("Team Search Engine")
struct TeamSearchEngineTests {

    private typealias F = TeamSearchFixtures

    private func search(_ text: String, _ events: [CorpusEvent],
                        minFullMatches: Int = 10) -> [TeamComposition] {
        var configuration = TeamSearchEngine.Configuration()
        configuration.minFullMatches = minFullMatches
        return TeamSearchEngine.search(F.parser.parse(text), in: F.index(events), now: F.now,
                                       configuration: configuration)
    }

    private func tags(_ members: [LimitlessStanding.TeamMember]) -> Set<String> {
        let index = F.index([F.event("e", [F.standing("p", placing: 1, members)])])
        return Set(index.teams[0].tags.map(\.id))
    }

    /// Teams that differ only in which player brought them.
    private let core = ["Incineroar", "Garchomp", "Gardevoir", "Rillaboom", "Farigiraf", "Kingambit"]

    // MARK: Tagging

    @Test("Styles come from moves")
    func tagsFromMoves() {
        #expect(tags([F.member("Farigiraf", moves: ["Trick Room"])]) == ["trick-room"])
        #expect(tags([F.member("Whimsicott", moves: ["Tailwind", "Encore"])]) == ["tailwind"])
        #expect(tags([F.member("Sinistcha", moves: ["Rage Powder"])]) == ["redirection"])
    }

    @Test("A Mega Stone brings its Mega's ability: Charizardite Y means sun")
    func tagsFromMegaAbility() {
        #expect(tags([F.member("Charizard", item: "Charizardite Y", moves: ["Heat Wave"])]) == ["sun"])
        #expect(tags([F.member("Charizard", item: "Charizardite X", moves: ["Heat Wave"])]).isEmpty)
    }

    @Test("Styles come from abilities")
    func tagsFromAbility() {
        #expect(tags([F.member("Indeedee ♀", "indeedee-f", ability: "Psychic Surge")])
                == ["psychic-terrain"])
    }

    @Test("Perish Trap needs Perish Song and a trapper")
    func perishTrapNeedsBoth() {
        #expect(tags([F.member("Gengar", item: "Gengarite", moves: ["Perish Song"])]) == ["perish-trap"])
        #expect(tags([F.member("Gengar", item: "Life Orb", moves: ["Perish Song"])]).isEmpty)
    }

    // MARK: Filters

    @Test("A species without a form matches every form; a form matches only that form")
    func speciesForms() {
        let events = [F.event("e", [
            F.standing("kanto", placing: 1, [F.member("Arcanine", "arcanine")]),
            F.standing("hisui", placing: 2, [F.member("Hisuian Arcanine", "arcanine-hisui")]),
        ])]
        #expect(search("arcanine", events).flatMap(\.teams).count == 2)
        #expect(search("hisuian arcanine", events).flatMap(\.teams).map(\.team.team.standing.player) == ["hisui"])
    }

    @Test("Male means the form that isn't female")
    func maleForm() {
        let events = [F.event("e", [
            F.standing("m", placing: 1, [F.member("Indeedee", "indeedee")]),
            F.standing("f", placing: 2, [F.member("Indeedee ♀", "indeedee-f")]),
        ])]
        #expect(search("indeedee male", events).flatMap(\.teams).map(\.team.team.standing.player) == ["m"])
        #expect(search("indeedee female", events).flatMap(\.teams).map(\.team.team.standing.player) == ["f"])
    }

    @Test("Mega requests need the stone, and a variant needs that stone")
    func megaFilters() {
        let events = [F.event("e", [
            F.standing("y", placing: 1, [F.member("Charizard", item: "Charizardite Y")]),
            F.standing("x", placing: 2, [F.member("Charizard", item: "Charizardite X")]),
            F.standing("none", placing: 3, [F.member("Charizard", item: "Life Orb")]),
        ])]
        func players(_ text: String) -> Set<String> {
            Set(search(text, events).flatMap(\.teams).map(\.team.team.standing.player))
        }
        #expect(players("charizard") == ["y", "x", "none"])
        #expect(players("mega charizard") == ["y", "x"])
        #expect(players("charizard y") == ["y"])
        #expect(players("no mega charizard") == ["none"])
    }

    @Test("Excluded species, moves and styles are left out; requested ones are required")
    func otherFilters() {
        let events = [F.event("e", [
            F.standing("tr", placing: 1, [F.member("Farigiraf", moves: ["Trick Room"]),
                                          F.member("Incineroar", moves: ["Fake Out"])]),
            F.standing("tw", placing: 2, [F.member("Whimsicott", moves: ["Tailwind"]),
                                          F.member("Garchomp", moves: ["Rock Slide"])]),
        ])]
        func players(_ text: String) -> [String] {
            search(text, events).flatMap(\.teams).map(\.team.team.standing.player).sorted()
        }
        #expect(players("no incineroar") == ["tw"])
        #expect(players("fake out") == ["tr"])
        #expect(players("without rock slide") == ["tr"])
        #expect(players("tailwind") == ["tw"])
        #expect(players("no trick room") == ["tw"])
        #expect(players("") == ["tr", "tw"])
    }

    // MARK: Partial matches

    @Test("With few full matches, teams missing one requested species are added as partial")
    func partialMatches() throws {
        let events = [F.event("e", [
            F.standing("both", placing: 2, F.six(core)),
            F.standing("one", placing: 2, F.six(["Garchomp", "Charizard", "Pelipper",
                                                "Dragonite", "Sneasler", "Torkoal"])),
            F.standing("neither", placing: 2, F.six(["Pelipper", "Charizard", "Dragonite",
                                                    "Sneasler", "Torkoal", "Whimsicott"])),
        ])]
        let results = search("incineroar and garchomp", events)
        #expect(results.map(\.isPartial) == [false, true])
        let partial = try #require(results.last)
        #expect(partial.missing.map(\.name) == ["Incineroar"])
        #expect(partial.reasons == ["Garchomp", "Missing Incineroar"])
        // Same placement and date, so the partial weighs exactly half.
        #expect(abs(partial.score * 2 - results[0].score) < 1e-9)

        // Enough full matches: no partials.
        #expect(search("incineroar and garchomp", events, minFullMatches: 1).count == 1)
        // A single requested species never produces partials.
        #expect(search("incineroar", events).count == 1)
    }

    // MARK: Grouping

    @Test("Teams sharing five of six Pokémon fold into one composition; four of six don't")
    func folding() throws {
        let fiveOfSix = ["Incineroar", "Garchomp", "Gardevoir", "Rillaboom", "Farigiraf", "Dragonite"]
        let fourOfSix = ["Incineroar", "Garchomp", "Gardevoir", "Rillaboom", "Torkoal", "Pelipper"]
        let events = [F.event("e", [
            F.standing("a", placing: 1, F.six(core)),
            F.standing("b", placing: 2, F.six(core.reversed())),   // same six, other order
            F.standing("c", placing: 3, F.six(fiveOfSix)),
            F.standing("d", placing: 4, F.six(fourOfSix)),
        ])]
        let results = search("", events)
        #expect(results.count == 2)
        let top = try #require(results.first)
        #expect(top.teams.map(\.team.team.standing.player) == ["a", "b", "c"])
        #expect(top.species == core)                      // the best team's order
        #expect(top.variants.count == 1)
        #expect(top.variants[0].added == ["Dragonite"])
        #expect(top.variants[0].removed == ["Kingambit"])
        #expect(results[1].teams.map(\.team.team.standing.player) == ["d"])
    }

    @Test("A composition reports its events, best placing, shared styles and reasons")
    func compositionDetails() throws {
        var trickRoom = F.six(core)
        trickRoom[4] = F.member("Farigiraf", moves: ["Trick Room"])
        let events = [
            F.event("big", players: 128, [F.standing("a", placing: 3, trickRoom)]),
            F.event("small", players: 16, [F.standing("b", placing: 1, trickRoom),
                                           F.standing("c", placing: 2, F.six(core))]),
        ]
        let results = search("gardevoir, no pelipper", events)
        let composition = try #require(results.first)
        #expect(results.count == 1)
        #expect(composition.eventCount == 2)
        #expect(composition.bestTeam?.team.team.standing.player == "b")
        #expect(composition.tags.map(\.id) == ["trick-room"])     // on 2 of 3 teams
        #expect(composition.reasons == ["Gardevoir", "No Pelipper"])
    }

    // MARK: Ranking

    @Test("Placement and recency weights")
    func weights() {
        #expect(TeamSearchEngine.placementWeight(placing: 1, players: 64) == 7)
        #expect(TeamSearchEngine.placementWeight(placing: 64, players: 64) == 1)
        #expect(TeamSearchEngine.placementWeight(placing: 100, players: 64) == 1)
        #expect(TeamSearchEngine.placementWeight(placing: nil, players: 64) == 1)
        let twoWeeksAgo = F.now.addingTimeInterval(-14 * 86_400)
        #expect(TeamSearchEngine.recencyWeight(eventDate: twoWeeksAgo, now: F.now, halfLifeDays: 14) == 0.5)
        #expect(TeamSearchEngine.recencyWeight(eventDate: F.now, now: F.now, halfLifeDays: 14) == 1)
        #expect(TeamSearchEngine.recencyWeight(eventDate: nil, now: F.now, halfLifeDays: 14) == 1)
    }

    @Test("Better placings and newer events rank higher")
    func ranking() {
        let other = ["Pelipper", "Charizard", "Dragonite", "Sneasler", "Torkoal", "Whimsicott"]
        let placing = [F.event("e", [F.standing("winner", placing: 1, F.six(core)),
                                     F.standing("eighth", placing: 8, F.six(other))])]
        #expect(search("", placing).map { $0.teams[0].team.team.standing.player } == ["winner", "eighth"])

        let recency = [F.event("old", daysAgo: 28, [F.standing("old", placing: 1, F.six(core))]),
                       F.event("new", daysAgo: 0, [F.standing("new", placing: 1, F.six(other))])]
        #expect(search("", recency).map { $0.teams[0].team.team.standing.player } == ["new", "old"])
    }
}
