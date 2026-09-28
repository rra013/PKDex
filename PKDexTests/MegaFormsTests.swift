//
//  MegaFormsTests.swift
//  PKDexTests
//
//  Covers `mega_forms.json` and its loader: the bundled file loads in
//  full, each stone belongs to one form, a move-triggered form needs its
//  move rather than a stone, and a bad entry (a stone with no `HeldItem`
//  case, or no trigger at all) fails the file instead of being dropped.
//  When the table moved from Swift to JSON (2026-09-28), the loaded forms
//  and every lookup were checked identical to the Swift table.
//

import Testing
import Foundation
@testable import PKDex

@Suite("Mega Forms")
struct MegaFormsTests {

    @Test("The bundled file loads every form")
    func bundledFileLoads() throws {
        let url = try #require(Bundle.main.url(forResource: "mega_forms", withExtension: "json"))
        let forms = try MegaForms.decode(Data(contentsOf: url))
        #expect(forms.count == 87)
        #expect(MegaForms.all.count == 86)
        #expect(MegaForms.moveTriggered.map(\.displayName) == ["Mega Rayquaza"])
    }

    @Test("Each stone and each name belongs to one form")
    func noDuplicates() {
        let stones = MegaForms.all.compactMap(\.stone)
        #expect(stones.count == MegaForms.all.count)
        #expect(Set(stones).count == stones.count)
        let names = (MegaForms.all + MegaForms.moveTriggered).map(\.displayName)
        #expect(Set(names).count == names.count)
    }

    @Test("A stone triggers its own species' Mega only")
    func stoneLookup() throws {
        let y = try #require(MegaForms.form(forSpecies: "Charizard", heldItem: .charizarditeY, moveNames: []))
        #expect(y.displayName == "Mega Charizard Y")
        #expect(y.baseSpAtk == 159)
        #expect(y.ability == "drought")
        #expect(MegaForms.form(forSpecies: "Charizard", heldItem: .none, moveNames: []) == nil)
        #expect(MegaForms.form(forSpecies: "Blastoise", heldItem: .charizarditeY, moveNames: []) == nil)
    }

    @Test("Mega Rayquaza needs Dragon Ascent, not a stone")
    func moveTrigger() {
        let withMove = MegaForms.form(forSpecies: "Rayquaza", heldItem: .none, moveNames: ["Dragon Ascent"])
        #expect(withMove?.displayName == "Mega Rayquaza")
        #expect(MegaForms.form(forSpecies: "Rayquaza", heldItem: .none, moveNames: ["Outrage"]) == nil)
    }

    @Test("Every Mega stone the item list has is a Mega stone")
    func stonesAreHeldItems() {
        for form in MegaForms.all {
            #expect(form.stone?.isMegaStone == true, "\(form.displayName)")
        }
    }

    // MARK: Bad files

    private func file(_ form: String) -> Data {
        Data(#"{"forms": [\#(form)]}"#.utf8)
    }

    @Test("A stone with no HeldItem case fails the file")
    func unknownStone() {
        let data = file(#"{"species_key": "pikachu", "display_name": "Mega Pikachu", "stone": "Pikachunite", "requires_move": null, "type1": "Electric", "type2": null, "base_stats": {"atk": 1, "def": 1, "spa": 1, "spd": 1, "spe": 1}, "ability": "static"}"#)
        #expect(throws: MegaForms.LoadError.unknownStone(form: "Mega Pikachu", stone: "Pikachunite")) {
            try MegaForms.decode(data)
        }
    }

    @Test("A form with neither a stone nor a move fails the file")
    func noTrigger() {
        let data = file(#"{"species_key": "pikachu", "display_name": "Mega Pikachu", "stone": null, "requires_move": null, "type1": "Electric", "type2": null, "base_stats": {"atk": 1, "def": 1, "spa": 1, "spd": 1, "spe": 1}, "ability": "static"}"#)
        #expect(throws: MegaForms.LoadError.noTrigger(form: "Mega Pikachu")) {
            try MegaForms.decode(data)
        }
    }
}
