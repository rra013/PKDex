//
//  TeamPasteImportTests.swift
//  PKDexTests
//
//  Covers `TeamPasteImport`'s planning: unique spread names (including
//  against names that exist only as team-slot references), blocked sets,
//  the six-slot cap, and that every team slot points at a spread the plan
//  creates. Hermetic: synthetic fixtures, `validator: nil`, and nothing is
//  inserted into SwiftData.
//

import Testing
import Foundation
@testable import PKDex

@MainActor
@Suite("Team Paste Import")
struct TeamPasteImportTests {

    // MARK: - Fixtures

    private static func pokemon(_ id: Int, _ name: String) -> PKMNStats {
        PKMNStats(id: id, speciesID: id, name: name, formName: nil,
                  type1: "Normal", type2: nil,
                  baseHP: 80, baseAtk: 80, baseDef: 80,
                  baseSpAtk: 80, baseSpDef: 80, baseSpeed: 80,
                  ability1: "blaze", ability2: nil, hiddenAbility: nil)
    }

    private static let names = ["Garchomp", "Incineroar", "Rillaboom", "Amoonguss",
                                "Kingambit", "Dragonite", "Gholdengo"]
    private static let pokedex = names.enumerated().map { pokemon($0.offset + 1, $0.element) }
    private static let tackle = MoveData(
        id: 33, name: "Tackle", type: "Normal", damageClass: "physical",
        power: 40, accuracy: 100, pp: 35, priority: 0,
        minHits: nil, maxHits: nil, drain: 0, healing: 0, critRate: 0,
        makesContact: true, generationId: 1)

    private static func paste(_ species: [String]) -> String {
        species.map { "\($0)\nLevel: 50\nEVs: 32 HP / 2 Atk\nSerious Nature\n- Tackle" }
            .joined(separator: "\n\n")
    }

    private static func plan(_ species: [String], teamName: String = "Rain",
                             taken: Set<String> = []) -> TeamImportPlan? {
        let importer = PasteImporter(allPokemon: pokedex, allMoves: [tackle],
                                     validator: nil, targetScale: .champions)
        let preview = importer.preview(ShowdownPaste.parse(paste(species),
                                                           ambiguousDefault: .champions))
        return TeamPasteImport.plan(preview: preview, importer: importer,
                                    teamName: teamName, taken: taken)
    }

    // MARK: - Names

    @Test("uniqueName counts up past taken names")
    func uniqueName() {
        #expect(TeamPasteImport.uniqueName("A", taken: []) == "A")
        #expect(TeamPasteImport.uniqueName("A", taken: ["A"]) == "A 2")
        #expect(TeamPasteImport.uniqueName("A", taken: ["A", "A 2", "A 3"]) == "A 4")
    }

    @Test("Taken names include spreads and team-slot references")
    func takenNames() {
        let spread = SavedSpread(name: "Saved one")
        var aiSlot = TeamSlotInfo(spreadName: "Garchomp (AI)", pokemonID: 1,
                                  pokemonName: "Garchomp", type1: "Dragon",
                                  moveSlots: [])
        aiSlot.championsMode = true
        let team = SavedTeam(name: "AI team", slots: [aiSlot])
        let taken = TeamPasteImport.takenNames(spreads: [spread], teams: [team])
        #expect(taken == ["Saved one", "Garchomp (AI)"])
    }

    // MARK: - Plans

    @Test("Every slot points at a spread the plan creates, in order")
    func slotsMatchSpreads() throws {
        let plan = try #require(Self.plan(["Garchomp", "Incineroar"]))
        #expect(plan.team.name == "Rain")
        #expect(plan.spreads.map(\.name) == ["Rain · Garchomp", "Rain · Incineroar"])
        #expect(plan.team.slots.map(\.spreadName) == plan.spreads.map(\.name))
        #expect(plan.team.slots.map(\.pokemonName) == ["Garchomp", "Incineroar"])
        #expect(plan.spreads.allSatisfy { $0.championsMode && $0.evHP == 32 })
        #expect(plan.skippedBlocked.isEmpty && plan.droppedOverLimit.isEmpty)
    }

    @Test("Spread names avoid existing spreads and slot references")
    func namesAvoidCollisions() throws {
        let plan = try #require(Self.plan(["Garchomp", "Garchomp"],
                                          taken: ["Rain · Garchomp"]))
        #expect(plan.spreads.map(\.name) == ["Rain · Garchomp 2", "Rain · Garchomp 3"])
        #expect(Set(plan.spreads.map(\.name)).count == plan.spreads.count)
    }

    @Test("Unresolved species are skipped and reported")
    func blockedSetsAreSkipped() throws {
        let plan = try #require(Self.plan(["Garchomp", "Missingno", "Incineroar"]))
        #expect(plan.team.slots.map(\.pokemonName) == ["Garchomp", "Incineroar"])
        #expect(plan.skippedBlocked == ["Missingno"])
    }

    @Test("Only the first six sets are imported")
    func sixSlotCap() throws {
        let plan = try #require(Self.plan(Self.names))   // seven sets
        #expect(plan.team.slots.count == 6)
        #expect(plan.spreads.count == 6)
        #expect(plan.droppedOverLimit == ["Gholdengo"])
    }

    @Test("Nothing importable means no plan")
    func nothingImportable() {
        #expect(Self.plan(["Missingno"]) == nil)
    }

    @Test("A blank team name falls back to a default")
    func defaultTeamName() throws {
        let plan = try #require(Self.plan(["Garchomp"], teamName: "   "))
        #expect(plan.team.name == "Imported Team")
        #expect(plan.spreads.first?.name == "Imported Team · Garchomp")
    }
}
