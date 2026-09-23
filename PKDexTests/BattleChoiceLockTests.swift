//
//  BattleChoiceLockTests.swift
//  PKDexTests
//

import Testing
import Foundation
@testable import PKDex

@MainActor
@Suite("Battle Engine — Choice Lock & Contact Recoil")
struct BattleChoiceLockTests {

    private func ferrothorn(ability: String = "iron-barbs") -> PKMNStats {
        PKMNStats(id: 598, speciesID: 598, name: "Ferrothorn",
                  type1: "Grass", type2: "Steel",
                  baseHP: 74, baseAtk: 94, baseDef: 131,
                  baseSpAtk: 54, baseSpDef: 116, baseSpeed: 20,
                  ability1: ability)
    }

    private func snorlax(ability: String = "thick-fat") -> PKMNStats {
        PKMNStats(id: 143, speciesID: 143, name: "Snorlax",
                  type1: "Normal", type2: nil,
                  baseHP: 160, baseAtk: 110, baseDef: 65,
                  baseSpAtk: 65, baseSpDef: 110, baseSpeed: 30,
                  ability1: ability)
    }

    private func tackle() -> MoveData {
        // Contact move.
        MoveData(id: 33, name: "Tackle", type: "Normal", damageClass: "physical",
                 power: 40, accuracy: 100, pp: 35, priority: 0,
                 minHits: nil, maxHits: nil, drain: 0, healing: 0,
                 critRate: 0, makesContact: true)
    }

    private func bodyPress() -> MoveData {
        MoveData(id: 776, name: "Body Press", type: "Fighting", damageClass: "physical",
                 power: 80, accuracy: 100, pp: 10, priority: 0,
                 minHits: nil, maxHits: nil, drain: 0, healing: 0,
                 critRate: 0, makesContact: true)
    }

    private func slot(for p: PKMNStats, ability: String, item: HeldItem = .none,
                      moves: [MoveData]) -> TeamSlotInfo {
        TeamSlotInfo(
            spreadName: "fixture-\(p.name)",
            pokemonID: p.id, pokemonName: p.name,
            type1: p.type1, type2: p.type2,
            abilityName: ability,
            itemRawValue: item == .none ? nil : item.rawValue,
            championsMode: false, natureID: "hardy", level: 50,
            evHP: 0, evAtk: 0, evDef: 0, evSpAtk: 0, evSpDef: 0, evSpeed: 0,
            moveSlots: moves.map {
                TeamMoveInfo(moveID: $0.id, moveName: $0.name, moveType: $0.type,
                             damageClass: $0.damageClass, power: $0.power, isSTAB: false)
            }
        )
    }

    private func engine(side1: PKMNStats, ab1: String, item1: HeldItem = .none, moves1: [MoveData],
                        side2: PKMNStats, ab2: String, item2: HeldItem = .none, moves2: [MoveData])
        -> BattleEngine
    {
        let s1Slot = slot(for: side1, ability: ab1, item: item1, moves: moves1)
        let s2Slot = slot(for: side2, ability: ab2, item: item2, moves: moves2)
        let pokemon = [side1, side2]
        let moves = moves1 + moves2
        let bs1 = BattleSide(label: "Side 1", slots: [s1Slot], format: .singles,
                             allPokemon: pokemon, allMoves: moves)
        let bs2 = BattleSide(label: "Side 2", slots: [s2Slot], format: .singles,
                             allPokemon: pokemon, allMoves: moves)
        return BattleEngine(format: .singles, side1: bs1, side2: bs2,
                            allPokemon: pokemon, allMoves: moves)
    }

    // MARK: - Choice Lock

    @Test func choiceBandLocksFirstMoveUsed() {
        let e = engine(side1: snorlax(), ab1: "thick-fat", item1: .choiceBand,
                       moves1: [tackle(), bodyPress()],
                       side2: ferrothorn(), ab2: "iron-barbs", moves2: [])
        let atk = e.side1.active(at: 0)!
        #expect(atk.choiceLockedMoveIndex == nil)
        e.setAction(side: 0, slot: 0,
                    action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e.executeTurn()
        #expect(atk.choiceLockedMoveIndex == 0)
    }

    @Test func switchOutClearsChoiceLock() {
        // Direct property reset via resetVolatile() — switches call this.
        let e = engine(side1: snorlax(), ab1: "thick-fat", item1: .choiceBand,
                       moves1: [tackle()],
                       side2: ferrothorn(), ab2: "iron-barbs", moves2: [])
        let atk = e.side1.active(at: 0)!
        atk.choiceLockedMoveIndex = 0
        atk.resetVolatile()
        #expect(atk.choiceLockedMoveIndex == nil)
    }

    @Test func nonChoiceItemDoesNotLock() {
        let e = engine(side1: snorlax(), ab1: "thick-fat", item1: .leftovers,
                       moves1: [tackle()],
                       side2: ferrothorn(), ab2: "iron-barbs", moves2: [])
        let atk = e.side1.active(at: 0)!
        e.setAction(side: 0, slot: 0,
                    action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e.executeTurn()
        #expect(atk.choiceLockedMoveIndex == nil)
    }

    // MARK: - Contact Recoil

    @Test func rockyHelmetChipsContactAttacker() {
        let e = engine(side1: snorlax(), ab1: "thick-fat", moves1: [tackle()],
                       side2: ferrothorn(ability: "anticipation"),
                       ab2: "anticipation", item2: .rockyHelmet, moves2: [])
        let atk = e.side1.active(at: 0)!
        let beforeHP = atk.currentHP
        let expectedChip = max(1, atk.maxHP / 6)
        e.setAction(side: 0, slot: 0,
                    action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e.executeTurn()
        #expect(atk.currentHP == beforeHP - expectedChip,
                "Rocky Helmet should chip 1/6 of attacker's maxHP on contact")
    }

    @Test func roughSkinChipsContactAttacker() {
        let e = engine(side1: snorlax(), ab1: "thick-fat", moves1: [tackle()],
                       side2: ferrothorn(ability: "rough-skin"),
                       ab2: "rough-skin", moves2: [])
        let atk = e.side1.active(at: 0)!
        let beforeHP = atk.currentHP
        let expectedChip = max(1, atk.maxHP / 8)
        e.setAction(side: 0, slot: 0,
                    action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e.executeTurn()
        #expect(atk.currentHP == beforeHP - expectedChip,
                "Rough Skin should chip 1/8 of attacker's maxHP on contact")
    }

    @Test func magicGuardExemptsAttackerFromContactRecoil() {
        let e = engine(side1: snorlax(ability: "magic-guard"),
                       ab1: "magic-guard", moves1: [tackle()],
                       side2: ferrothorn(ability: "rough-skin"),
                       ab2: "rough-skin", item2: .rockyHelmet, moves2: [])
        let atk = e.side1.active(at: 0)!
        let beforeHP = atk.currentHP
        e.setAction(side: 0, slot: 0,
                    action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e.executeTurn()
        #expect(atk.currentHP == beforeHP,
                "Magic Guard must zero out contact recoil from Rocky Helmet AND Rough Skin")
    }
}
