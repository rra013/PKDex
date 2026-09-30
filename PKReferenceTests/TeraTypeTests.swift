//
//  TeraTypeTests.swift
//  PKReferenceTests
//
//  Covers a set's Tera type: it survives a paste import into a set or a
//  team, the calc and Set Builder's load and save, a SwiftData save, and
//  the paste export; and team data saved before the field existed still
//  decodes. No regulation allows Tera yet, so nothing Terastallizes; these
//  only check the type isn't lost.
//
//  The store migration (an optional attribute, so automatic) was checked
//  on the simulator against an existing store when the field was added.
//

import Testing
import Foundation
import SwiftData
@testable import PKReference

@MainActor
@Suite("Tera Type")
struct TeraTypeTests {

    private func clefable() -> PKMNStats {
        PKMNStats(id: 36, speciesID: 36, name: "Clefable",
                  type1: "Fairy", type2: nil,
                  baseHP: 95, baseAtk: 70, baseDef: 73,
                  baseSpAtk: 95, baseSpDef: 90, baseSpeed: 60,
                  ability1: "cute-charm", ability2: "magic-guard", hiddenAbility: "unaware")
    }

    private let paste = """
        Clefable @ Leftovers
        Ability: Magic Guard
        Tera Type: Fairy
        EVs: 252 HP / 252 SpA / 4 SpD
        Modest Nature
        """

    @Test("A pasted Tera type reaches the saved set and the team slot")
    func pasteImport() throws {
        let importer = PasteImporter(allPokemon: [clefable()], allMoves: [], validator: nil)
        let slot = try #require(importer.preview(ShowdownPaste.parse(paste)).slots.first)
        #expect(importer.savedSpread(for: slot, name: "x")?.teraType == "Fairy")
        #expect(importer.teamSlot(for: slot, spreadName: "x")?.teraType == "Fairy")
    }

    @Test("The calc and Set Builder keep it through load, save and export")
    func calcSideRoundTrip() throws {
        let side = CalcSide()
        side.pokemon = clefable()
        side.teraType = "Stellar"

        let spread = side.toSavedSpread(name: "Round trip")
        #expect(spread.teraType == "Stellar")

        let reloaded = CalcSide()
        reloaded.loadSpread(spread, allPokemon: [clefable()], allMoves: [])
        #expect(reloaded.teraType == "Stellar")

        let text = try #require(reloaded.showdownPasteSet()).showdownText()
        #expect(text.contains("Tera Type: Stellar"))
    }

    @Test("A set without one exports no Tera line")
    func noTeraLine() throws {
        let side = CalcSide()
        side.pokemon = clefable()
        let text = try #require(side.showdownPasteSet()).showdownText()
        #expect(!text.contains("Tera Type"))
    }

    @Test("A team slot made from a set takes its Tera type")
    func teamSlotFromSpread() throws {
        let spread = SavedSpread(name: "Clefable", pokemonID: 36, pokemonName: "Clefable",
                                 teraType: "Water")
        let slot = try #require(TeamSlotInfo.from(spread: spread, pokemon: clefable(), moves: []))
        #expect(slot.teraType == "Water")
    }

    @Test("Team slots saved before Tera types decode with none")
    func oldTeamSlotsDecode() throws {
        var slot = try #require(TeamSlotInfo.from(
            spread: SavedSpread(name: "Clefable", pokemonID: 36, pokemonName: "Clefable"),
            pokemon: clefable(), moves: []))
        slot.teraType = "Water"
        var json = try #require(try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(slot)) as? [String: Any])
        json.removeValue(forKey: "teraType")
        let old = try JSONSerialization.data(withJSONObject: json)
        let decoded = try JSONDecoder().decode(TeamSlotInfo.self, from: old)
        #expect(decoded.teraType == nil)
        #expect(decoded.pokemonName == "Clefable")
    }

    @Test("A saved set's Tera type is stored")
    func storedInSwiftData() throws {
        let container = try ModelContainer(
            for: SavedSpread.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        context.insert(SavedSpread(name: "With Tera", teraType: "Fairy"))
        context.insert(SavedSpread(name: "Without"))
        try context.save()

        let stored = try context.fetch(FetchDescriptor<SavedSpread>(sortBy: [SortDescriptor(\.name)]))
        #expect(stored.map(\.name) == ["With Tera", "Without"])
        #expect(stored.map(\.teraType) == ["Fairy", nil])
    }
}
