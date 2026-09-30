//
//  SavedIntentsTests.swift
//  PKReferenceTests
//
//  Covers the Siri, Spotlight and Shortcuts actions for saved sets and
//  teams: how a set and a team are described, how they're found by name,
//  that an entity keeps the id it was asked for by, a team's legality from
//  the Battle Sim's check, and which saves refresh Spotlight's index. The
//  cases use a store in memory.
//

import Testing
import Foundation
import SwiftData
@testable import PKReference

@MainActor
@Suite("Saved sets and teams in App Intents")
struct SavedIntentsTests {

    /// Garchomp and Tyranitar, four moves, two sets and a team. Keep the
    /// container while using its context: the context doesn't keep it.
    private func store() throws -> (ModelContainer, sweeper: SavedSpread, team: SavedTeam) {
        let container = try ModelContainer(
            for: PKMNStats.self, MoveData.self, SavedSpread.self, SavedTeam.self, PKMN.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let garchomp = PKMNStats(id: 445, speciesID: 445, name: "Garchomp", type1: "Dragon", type2: "Ground",
                                 baseHP: 108, baseAtk: 130, baseDef: 95, baseSpAtk: 80, baseSpDef: 85, baseSpeed: 102,
                                 ability1: "sand-veil", hiddenAbility: "rough-skin")
        let tyranitar = PKMNStats(id: 248, speciesID: 248, name: "Tyranitar", type1: "Rock", type2: "Dark",
                                  baseHP: 100, baseAtk: 134, baseDef: 110, baseSpAtk: 95, baseSpDef: 100, baseSpeed: 61,
                                  ability1: "sand-stream")
        context.insert(garchomp)
        context.insert(tyranitar)
        let moves = [
            MoveData(id: 89, name: "Earthquake", type: "Ground", damageClass: "physical",
                     power: 100, accuracy: 100, pp: 10, generationId: 1),
            MoveData(id: 337, name: "Dragon Claw", type: "Dragon", damageClass: "physical",
                     power: 80, accuracy: 100, pp: 15, generationId: 3),
            MoveData(id: 157, name: "Rock Slide", type: "Rock", damageClass: "physical",
                     power: 75, accuracy: 90, pp: 10, generationId: 1),
            MoveData(id: 182, name: "Protect", type: "Normal", damageClass: "status",
                     power: nil, accuracy: nil, pp: 10, generationId: 2),
        ]
        for move in moves { context.insert(move) }
        let sweeper = SavedSpread(name: "Physical Sweeper", pokemonID: 445, pokemonName: "Garchomp",
                                  abilityName: "rough-skin", itemRawValue: "Choice Scarf", championsMode: true,
                                  natureID: "jolly", evHP: 2, evAtk: 32, evSpeed: 32,
                                  moveID1: 89, moveID2: 337, moveID3: 157, moveID4: 182)
        let wall = SavedSpread(name: "Sand Wall", pokemonID: 248, pokemonName: "Tyranitar",
                               abilityName: "sand-stream", championsMode: true, natureID: "careful",
                               evHP: 32, evSpDef: 32, moveID1: 157)
        context.insert(sweeper)
        context.insert(wall)
        let slots = [wall, sweeper].compactMap { spread in
            TeamSlotInfo.from(spread: spread, pokemon: spread.pokemonID == 445 ? garchomp : tyranitar, moves: moves)
        }
        let team = SavedTeam(name: "Sand Offense", slots: slots)
        context.insert(team)
        try context.save()
        return (container, sweeper, team)
    }

    // MARK: Sets

    @Test("A set is described the way a player would say it")
    func setAnswer() throws {
        let (container, sweeper, _) = try store()
        let id = try #require(StoredID.text(sweeper.persistentModelID))
        let answer = try IntentData.setAnswer(id, in: container.mainContext)
        #expect(answer.spoken == "Physical Sweeper is Garchomp with Rough Skin and Choice Scarf, and a Jolly nature. "
                + "Its moves are Earthquake, Dragon Claw, Rock Slide, and Protect.")
        #expect(answer.details == "Level 50 · Champions · 32 Atk / 32 Spe / 2 HP")
        #expect(answer.types == ["Dragon", "Ground"])
    }

    @Test("A bare set says what it doesn't have")
    func bareSet() {
        let answer = SetAnswer(name: "New Set", pokemon: "Garchomp", types: [], ability: nil, item: nil,
                               nature: "Serious", level: 50, championsMode: false, investment: [], moves: [])
        #expect(answer.spoken == "New Set is Garchomp with a Serious nature. It has no moves yet.")
        #expect(answer.details == "Level 50 · Mainline · No EVs")
    }

    @Test("Sets are found by their name or their Pokémon's")
    func findSets() throws {
        let (container, sweeper, _) = try store()
        let context = container.mainContext
        #expect(Set(IntentData.savedSetEntities(in: context).map(\.name)) == ["Sand Wall", "Physical Sweeper"])
        #expect(IntentData.savedSetEntities(matching: "garchomp", in: context).map(\.name) == ["Physical Sweeper"])
        #expect(IntentData.savedSetEntities(matching: "sand", in: context).map(\.name) == ["Sand Wall"])

        let id = try #require(StoredID.text(sweeper.persistentModelID))
        let found = IntentData.savedSetEntities(ids: [id, "not an id"], in: context)
        #expect(found.map(\.id) == [id] && found.first?.pokemon == "Garchomp")
    }

    @Test("An id is the same text every time, and reads back")
    func storedIDs() throws {
        let (_, sweeper, _) = try store()
        let text = try #require(StoredID.text(sweeper.persistentModelID))
        #expect(StoredID.text(sweeper.persistentModelID) == text)
        #expect(StoredID.identifier(text) == sweeper.persistentModelID)
        #expect(StoredID.set(from: "set:" + text) == sweeper.persistentModelID)
        #expect(StoredID.set(from: "none") == nil)
    }

    // MARK: Teams

    /// Two Pokémon aren't a legal Champions team: it needs six.
    @Test("A Champions team is checked against the regulation in Settings")
    func teamAnswer() throws {
        let (container, _, team) = try store()
        let context = container.mainContext
        let id = try #require(StoredID.text(team.persistentModelID))
        let answer = try IntentData.teamAnswer(id, in: context)
        #expect(answer.members.map(\.name) == ["Tyranitar", "Garchomp"])
        #expect(answer.members.last?.item == "Choice Scarf")
        #expect(answer.regulation == ChampionsRegulation.current.displayName)
        #expect(answer.problems.contains("Team has 2 members, expected 6"))
        #expect(answer.spoken.hasPrefix("Sand Offense: Tyranitar and Garchomp. It isn't legal in "))

        let entity = try #require(IntentData.savedTeamEntities(ids: [id], in: context).first)
        #expect(entity.members == ["Tyranitar", "Garchomp"])
        #expect(IntentData.savedTeamEntities(matching: "Tyranitar", in: context).map(\.name) == ["Sand Offense"])
    }

    @Test("Team answers")
    func teamSpoken() {
        let members = [TeamAnswer.Member(name: "Tyranitar", types: [], item: nil),
                       TeamAnswer.Member(name: "Excadrill", types: [], item: nil)]
        #expect(TeamAnswer(name: "Sand", members: members, regulation: "Regulation M-C", problems: [], warnings: []).spoken
                == "Sand: Tyranitar and Excadrill. It's legal in Regulation M-C.")
        #expect(TeamAnswer(name: "Sand", members: members, regulation: "Regulation M-C",
                           problems: ["Team has 2 members, expected 6", "Duplicate item in team: Leftovers"],
                           warnings: []).spoken
                == "Sand: Tyranitar and Excadrill. It isn't legal in Regulation M-C: Team has 2 members, expected 6, and 1 more problem.")
        #expect(TeamAnswer(name: "Sand", members: members, regulation: nil, problems: [], warnings: []).spoken
                == "Sand: Tyranitar and Excadrill.")
        #expect(TeamAnswer(name: "Empty", members: [], regulation: nil, problems: [], warnings: []).spoken
                == "Empty has no Pokémon yet.")
    }

    // MARK: Spotlight

    @Test("Only saves that touch a set or team refresh the index")
    func savesThatRefresh() throws {
        let (container, sweeper, _) = try store()
        let context = container.mainContext
        let key = ModelContext.NotificationKey.self
        #expect(IntentIndex.changesSavedItems([key.updatedIdentifiers.rawValue: [sweeper.persistentModelID]]))
        let pokemon = try #require(try context.fetch(FetchDescriptor<PKMNStats>()).first)
        #expect(!IntentIndex.changesSavedItems([key.insertedIdentifiers.rawValue: [pokemon.persistentModelID]]))
        #expect(IntentIndex.changesSavedItems(nil))
    }

    /// The details the check reads are in a real save's notification.
    @Test("A save's notification says what it changed")
    func saveNotification() throws {
        let (container, _, _) = try store()
        let context = container.mainContext
        // Written by the observer, which runs during `save()` on this thread.
        final class Box: @unchecked Sendable { var userInfo: [AnyHashable: Any]? }
        let box = Box()
        let observer = NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: context,
                                                              queue: nil) { box.userInfo = $0.userInfo }
        defer { NotificationCenter.default.removeObserver(observer) }
        context.insert(SavedSpread(name: "Another", pokemonID: 445))
        try context.save()
        let inserted = box.userInfo?[ModelContext.NotificationKey.insertedIdentifiers.rawValue] as? [PersistentIdentifier]
        #expect(inserted?.contains { $0.entityName == "SavedSpread" } == true)
        #expect(IntentIndex.changesSavedItems(box.userInfo))
    }
}
