//
//  BattleSecondaryEffectTests.swift
//  PKDexTests
//

import Testing
import Foundation
@testable import PKDex

@MainActor
@Suite("Battle Engine — Move Secondary Effects")
struct BattleSecondaryEffectTests {

    private func milotic(ability: String = "marvel-scale") -> PKMNStats {
        PKMNStats(id: 350, speciesID: 350, name: "Milotic",
                  type1: "Water", type2: nil,
                  baseHP: 95, baseAtk: 60, baseDef: 79,
                  baseSpAtk: 100, baseSpDef: 125, baseSpeed: 81,
                  ability1: ability)
    }

    private func snorlax(ability: String = "thick-fat") -> PKMNStats {
        PKMNStats(id: 143, speciesID: 143, name: "Snorlax",
                  type1: "Normal", type2: nil,
                  baseHP: 160, baseAtk: 110, baseDef: 65,
                  baseSpAtk: 65, baseSpDef: 110, baseSpeed: 30,
                  ability1: ability)
    }

    private func conkeldurr(ability: String = "guts") -> PKMNStats {
        PKMNStats(id: 534, speciesID: 534, name: "Conkeldurr",
                  type1: "Fighting", type2: nil,
                  baseHP: 105, baseAtk: 140, baseDef: 95,
                  baseSpAtk: 55, baseSpDef: 65, baseSpeed: 45,
                  ability1: ability)
    }

    private func scald() -> MoveData {
        MoveData(id: 503, name: "Scald", type: "Water", damageClass: "special",
                 power: 80, accuracy: 100, pp: 15, priority: 0,
                 minHits: nil, maxHits: nil, drain: 0, healing: 0,
                 critRate: 0, makesContact: false)
    }

    private func closeCombat() -> MoveData {
        MoveData(id: 370, name: "Close Combat", type: "Fighting", damageClass: "physical",
                 power: 120, accuracy: 100, pp: 5, priority: 0,
                 minHits: nil, maxHits: nil, drain: 0, healing: 0,
                 critRate: 0, makesContact: true)
    }

    private func slot(for p: PKMNStats, ability: String, moves: [MoveData]) -> TeamSlotInfo {
        TeamSlotInfo(
            spreadName: "fixture-\(p.name)",
            pokemonID: p.id, pokemonName: p.name,
            type1: p.type1, type2: p.type2,
            abilityName: ability, itemRawValue: nil,
            championsMode: false, natureID: "hardy", level: 50,
            evHP: 0, evAtk: 0, evDef: 0, evSpAtk: 0, evSpDef: 0, evSpeed: 0,
            moveSlots: moves.map {
                TeamMoveInfo(moveID: $0.id, moveName: $0.name, moveType: $0.type,
                             damageClass: $0.damageClass, power: $0.power, isSTAB: false)
            }
        )
    }

    private func engine(side1: PKMNStats, ab1: String, moves1: [MoveData],
                        side2: PKMNStats, ab2: String, moves2: [MoveData])
        -> BattleEngine
    {
        let s1Slot = slot(for: side1, ability: ab1, moves: moves1)
        let s2Slot = slot(for: side2, ability: ab2, moves: moves2)
        let pokemon = [side1, side2]
        let moves = moves1 + moves2
        let bs1 = BattleSide(label: "Side 1", slots: [s1Slot], format: .singles,
                             allPokemon: pokemon, allMoves: moves)
        let bs2 = BattleSide(label: "Side 2", slots: [s2Slot], format: .singles,
                             allPokemon: pokemon, allMoves: moves)
        return BattleEngine(format: .singles, side1: bs1, side2: bs2,
                            allPokemon: pokemon, allMoves: moves)
    }

    @Test func scaldCanBurnNonFireTarget() {
        // 30% burn chance per hit — run many trials, expect at least one burn.
        var anyBurn = false
        for _ in 0..<100 {
            let e = engine(side1: milotic(), ab1: "marvel-scale", moves1: [scald()],
                           side2: snorlax(), ab2: "thick-fat", moves2: [])
            e.setAction(side: 0, slot: 0,
                        action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
            e.executeTurn()
            if e.side2.active(at: 0)?.status == .burn { anyBurn = true; break }
        }
        #expect(anyBurn, "Scald should burn the target in at least one of 100 trials")
    }

    @Test func shieldDustBlocksSecondaryStatus() {
        // Shield Dust on the defender prevents the burn chance entirely.
        for _ in 0..<100 {
            let e = engine(side1: milotic(), ab1: "marvel-scale", moves1: [scald()],
                           side2: snorlax(ability: "shield-dust"),
                           ab2: "shield-dust", moves2: [])
            e.setAction(side: 0, slot: 0,
                        action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
            e.executeTurn()
            #expect(e.side2.active(at: 0)?.status != .burn,
                    "Shield Dust must block secondary effects")
        }
    }

    @Test func sheerForceSuppressesSecondary() {
        for _ in 0..<50 {
            let e = engine(side1: milotic(ability: "sheer-force"),
                           ab1: "sheer-force", moves1: [scald()],
                           side2: snorlax(), ab2: "thick-fat", moves2: [])
            e.setAction(side: 0, slot: 0,
                        action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
            e.executeTurn()
            #expect(e.side2.active(at: 0)?.status != .burn,
                    "Sheer Force should suppress secondary status effects")
        }
    }

    @Test func closeCombatAlwaysDropsUsersDefenses() {
        let e = engine(side1: conkeldurr(), ab1: "guts", moves1: [closeCombat()],
                       side2: snorlax(), ab2: "thick-fat", moves2: [])
        let atk = e.side1.active(at: 0)!
        e.setAction(side: 0, slot: 0,
                    action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e.executeTurn()
        #expect(atk.defStage == -1)
        #expect(atk.spDefStage == -1)
    }
}
