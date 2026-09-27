//
//  DexLabelTests.swift
//  PKDexTests
//
//  Covers the Dex numbers shown next to Pokémon: forms show their species'
//  number rather than PokeAPI's form ID, and numbers of 1000 and up have no
//  thousands separator.
//

import Testing
@testable import PKDex

@Suite("Dex Labels")
struct DexLabelTests {

    @Test("A form shows its species' number, not its form ID")
    func formsUseSpecies() {
        let megaZ = PKMNStats(id: 10309, speciesID: 445, name: "Garchomp-Mega-Z", formName: "mega-z",
                              type1: "Dragon", type2: "Ground",
                              baseHP: 108, baseAtk: 130, baseDef: 85,
                              baseSpAtk: 141, baseSpDef: 85, baseSpeed: 151)
        #expect(megaZ.dexLabel == "#445")
    }

    @Test("Numbers of 1000 and up have no thousands separator")
    func noGrouping() {
        #expect(dexLabel(for: 1000) == "#1000")
        #expect(dexLabel(for: 1025) == "#1025")
        #expect(dexLabel(for: 3) == "#3")
    }
}
