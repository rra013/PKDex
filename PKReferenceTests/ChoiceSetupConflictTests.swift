//
//  ChoiceSetupConflictTests.swift
//  PKReferenceTests
//
//  Covers the Champions validator's Choice-item check: a set holding a
//  Choice item the regulation allows, with a setup move, is flagged
//  (coherence, not legality). Choice items come from each regulation's
//  `items_whitelist`, and setup moves from `battle_moves.json`, so a
//  regulation that legalizes Choice Band gets the same check. Before both
//  moved out of the validator (2026-09-28), they were checked identical to
//  its hard-coded lists.
//

import Testing
import Foundation
@testable import PKReference

@MainActor
@Suite("Validator — Choice Item and Setup Move")
struct ChoiceSetupConflictTests {

    private func garchomp(item: String?, moves: [String]) -> PokemonSet {
        PokemonSet(species: "Garchomp", ability: "Rough Skin", item: item, nature: "Jolly",
                   teraType: nil, moves: moves,
                   statPoints: .init(hp: 2, atk: 32, def: 0, spa: 0, spd: 0, spe: 32), role: nil)
    }

    private func conflicts(_ v: ChampionsValidator, _ set: PokemonSet) -> [Violation] {
        v.validate(set: set).filter { $0.category == .choiceSetupConflict }
    }

    @Test("Every regulation so far allows one Choice item, Choice Scarf",
          arguments: ChampionsRegulation.allCases)
    func choiceItems(regulation: ChampionsRegulation) throws {
        let v = try #require(ChampionsValidator(regulation: regulation))
        #expect(v.choiceItems == ["Choice Scarf"])
    }

    @Test("The setup-move list has the validator's 35 moves")
    func setupMoves() {
        #expect(BattleMoveEffects.setupMoves.count == 35)
        for move in ["Swords Dance", "Dragon Dance", "Power-Up Punch", "Magnet Rise", "Geomancy"] {
            #expect(BattleMoveEffects.setupMoves.contains(BattleSimSeed.normalize(move)), "\(move)")
        }
    }

    @Test("A Choice Scarf set with a setup move is flagged, and nothing else is")
    func flagged() throws {
        let v = try #require(ChampionsValidator(regulation: .mC))
        let scarfDance = conflicts(v, garchomp(item: "Choice Scarf",
                                               moves: ["Earthquake", "Swords Dance", "Protect", "Rock Slide"]))
        #expect(scarfDance.count == 1)
        #expect(scarfDance.first?.message.hasSuffix("Swords Dance") == true)
        #expect(!(scarfDance.first?.category.isLegality ?? true))

        #expect(conflicts(v, garchomp(item: "Choice Scarf",
                                      moves: ["Earthquake", "Dragon Claw", "Protect", "Rock Slide"])).isEmpty)
        #expect(conflicts(v, garchomp(item: "Leftovers",
                                      moves: ["Earthquake", "Swords Dance", "Protect", "Rock Slide"])).isEmpty)
    }

    @Test("A regulation that allows Choice Band gets the same check")
    func choiceBandRegulation() throws {
        let reg = ChampionsRegulation.mC
        let legalityURL = try #require(Bundle.main.url(forResource: reg.bundleResourceName,
                                                       withExtension: "json"))
        let learnsetsURL = try #require(Bundle.main.url(forResource: reg.learnsetBundleResourceName,
                                                        withExtension: "json"))
        var json = try #require(try JSONSerialization.jsonObject(
            with: Data(contentsOf: legalityURL)) as? [String: Any])
        let items = try #require(json["items_whitelist"] as? [String])
        json["items_whitelist"] = items + ["Choice Band"]
        let edited = FileManager.default.temporaryDirectory
            .appendingPathComponent("ChoiceSetupConflictTests-\(UUID().uuidString).json")
        try JSONSerialization.data(withJSONObject: json).write(to: edited)
        defer { try? FileManager.default.removeItem(at: edited) }

        let v = try #require(ChampionsValidator(legalityURL: edited, learnsetsURL: learnsetsURL))
        #expect(v.choiceItems == ["Choice Scarf", "Choice Band"])
        #expect(conflicts(v, garchomp(item: "Choice Band",
                                      moves: ["Earthquake", "Dragon Dance", "Protect", "Rock Slide"])).count == 1)
    }
}
