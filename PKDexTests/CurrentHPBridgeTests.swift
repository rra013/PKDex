//
//  CurrentHPBridgeTests.swift
//  PKDexTests
//
//  The calc stores current HP as a percentage; the Champions port wants an
//  absolute HP. It has to be a percentage of the port's own max HP, which
//  includes HP stat points. It used to be taken from a 0-point max HP, so any
//  HP investment below 100% handed the port too little HP. That skewed
//  Eruption / Water Spout, Flail / Reversal, Wring Out / Crush Grip, the
//  ⅓-HP pinch abilities, and Pain Split / Endeavor / Final Gambit.
//

import Testing
import Foundation
@testable import PKDex

@Suite("Champions Bridge — Current HP")
struct CurrentHPBridgeTests {

    private static let typhlosion = SpeciesSnapshot(
        name: "Typhlosion", type1: "Fire", type2: nil,
        baseHP: 78, baseAtk: 84, baseDef: 78,
        baseSpAtk: 109, baseSpDef: 85, baseSpeed: 100)
    private static let garchomp = SpeciesSnapshot(
        name: "Garchomp", type1: "Dragon", type2: "Ground",
        baseHP: 108, baseAtk: 130, baseDef: 95,
        baseSpAtk: 80, baseSpDef: 85, baseSpeed: 102)

    private static func side(_ species: SpeciesSnapshot, hpPoints: Int = 0,
                             percent: Int = 100) -> CalcSnapshot {
        var s = CalcSnapshot(species: species, megaForm: nil,
                             nature: allNatures.first { $0.id == "modest" }!,
                             level: 50, selectedAbility: nil, heldItem: .none,
                             moves: [], championsMode: true)
        s.evHP = hpPoints
        s.evSpAtk = 32
        s.currentHPPercent = percent
        return s
    }

    @Test("Current HP is a percentage of the port's own max HP", arguments: [0, 16, 32])
    func currentHPUsesRealMax(hpPoints: Int) throws {
        let gen = ShowdownGen0.shared
        let snap = Self.side(Self.typhlosion, hpPoints: hpPoints, percent: 50)
        let species = try #require(CalcEngine.showdownSpecies(gen, for: snap))
        let pokemon = CalcEngine.makeShowdownPokemon(gen, side: snap, species: species,
                                                    moveType: "Fire", isAttacker: true,
                                                    field: FieldSnapshot())
        #expect(pokemon.curHP() == pokemon.maxHP() * 50 / 100,
                "\(hpPoints) HP points: \(pokemon.curHP()) of \(pokemon.maxHP())")
    }

    @Test("Eruption at half HP doesn't depend on HP investment")
    func eruptionIgnoresHPInvestment() throws {
        let eruption = MoveSnapshot(id: 284, name: "Eruption", type: "Fire",
                                    damageClass: "special", power: 150, makesContact: false)
        let defender = Self.side(Self.garchomp)
        func damage(hpPoints: Int) throws -> CalcOutcome {
            try #require(CalcEngine.evaluateChampions(
                move: eruption, attacker: Self.side(Self.typhlosion, hpPoints: hpPoints, percent: 50),
                defender: defender, field: FieldSnapshot()))
        }
        let none = try damage(hpPoints: 0)
        let full = try damage(hpPoints: 32)
        #expect(none.damageMin == full.damageMin && none.damageMax == full.damageMax,
                "0 HP points: \(none.damageMin)-\(none.damageMax), 32: \(full.damageMin)-\(full.damageMax)")
    }

    @Test("Full HP is still passed as full")
    func fullHP() throws {
        let gen = ShowdownGen0.shared
        let snap = Self.side(Self.typhlosion, hpPoints: 32, percent: 100)
        let species = try #require(CalcEngine.showdownSpecies(gen, for: snap))
        let pokemon = CalcEngine.makeShowdownPokemon(gen, side: snap, species: species,
                                                    moveType: "Fire", isAttacker: true,
                                                    field: FieldSnapshot())
        #expect(pokemon.curHP() == pokemon.maxHP())
    }
}
