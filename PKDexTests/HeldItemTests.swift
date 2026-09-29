//
//  HeldItemTests.swift
//  PKDexTests
//
//  Covers `HeldItem`: the built-in items plus a Mega stone for every
//  stone-triggered form in `mega_forms.json` make up every item; names are
//  unique; an unknown name isn't an item; the item tables only use
//  built-in items; and the picker puts a species' own stones first and
//  hides the rest. When the item enum became data-backed (2026-09-28), the
//  items, the type tables and every Mega species' picker list were checked
//  identical to the enum's.
//

import Testing
@testable import PKDex

@Suite("Held Items")
struct HeldItemTests {

    @Test("Every item is a built-in one or a stone from mega_forms.json")
    func allCases() {
        let stones = MegaForms.all.compactMap(\.stone)
        #expect(HeldItem.allCases == HeldItem.builtIns + stones)
        #expect(HeldItem.builtIns.count == 70)
        #expect(stones.count == 86)
        #expect(HeldItem.builtIns.allSatisfy { !$0.isMegaStone })
        #expect(stones.allSatisfy { $0.isMegaStone })
    }

    @Test("Names are unique, and look up the same item")
    func names() {
        let names = HeldItem.allCases.map(\.rawValue)
        #expect(Set(names).count == names.count)
        for item in HeldItem.allCases {
            #expect(HeldItem(rawValue: item.rawValue) == item)
            #expect(item.description == item.rawValue)
        }
        #expect(HeldItem(rawValue: "Pikachunite") == nil)
        #expect(HeldItem(rawValue: "leftovers") == nil)
    }

    @Test("The item tables only use built-in items")
    func tablesUseBuiltIns() {
        let builtIns = Set(HeldItem.builtIns)
        #expect(Set(typeBoostingItemMap.keys).isSubset(of: builtIns))
        #expect(Set(typeResistBerryMap.keys).isSubset(of: builtIns))
        #expect(HeldItem.nonChampionsItems.isSubset(of: builtIns))
        #expect(typeBoostingItemMap.count == 18)
        #expect(typeResistBerryMap.count == 17)
    }

    @Test("A species' picker lists its own stones first and no others")
    func pickerStones() {
        let options = HeldItem.pickerOptions(forSpeciesNamed: "Charizard")
        #expect(options.prefix(2).map(\.rawValue) == ["Charizardite X", "Charizardite Y"])
        #expect(options.filter(\.isMegaStone).count == 2)
        #expect(HeldItem.pickerOptions(forSpeciesNamed: "Pikachu").allSatisfy { !$0.isMegaStone })
        #expect(!options.contains(.choiceBand))
    }
}
