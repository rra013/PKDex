//
//  BattleDrainRecoilTests.swift
//  PKDexTests
//

import Testing
import Foundation
@testable import PKDex

@MainActor
@Suite("Battle Engine — Drain, Recoil, and Self-Heal")
struct BattleDrainRecoilTests {

    private func snorlax(ability: String = "thick-fat") -> PKMNStats {
        PKMNStats(id: 143, speciesID: 143, name: "Snorlax",
                  type1: "Normal", type2: nil,
                  baseHP: 160, baseAtk: 110, baseDef: 65,
                  baseSpAtk: 65, baseSpDef: 110, baseSpeed: 30,
                  ability1: ability)
    }

    private func chansey(ability: String = "natural-cure") -> PKMNStats {
        PKMNStats(id: 113, speciesID: 113, name: "Chansey",
                  type1: "Normal", type2: nil,
                  baseHP: 250, baseAtk: 5, baseDef: 5,
                  baseSpAtk: 35, baseSpDef: 105, baseSpeed: 50,
                  ability1: ability)
    }

    private func aggron(ability: String = "rock-head") -> PKMNStats {
        PKMNStats(id: 306, speciesID: 306, name: "Aggron",
                  type1: "Steel", type2: "Rock",
                  baseHP: 70, baseAtk: 110, baseDef: 180,
                  baseSpAtk: 60, baseSpDef: 60, baseSpeed: 50,
                  ability1: ability)
    }

    private func gigaDrain() -> MoveData {
        MoveData(id: 202, name: "Giga Drain", type: "Grass", damageClass: "special",
                 power: 75, accuracy: 100, pp: 10, priority: 0,
                 minHits: nil, maxHits: nil, drain: 50, healing: 0,
                 critRate: 0, makesContact: false)
    }

    private func braveBird() -> MoveData {
        MoveData(id: 413, name: "Brave Bird", type: "Flying", damageClass: "physical",
                 power: 120, accuracy: 100, pp: 15, priority: 0,
                 minHits: nil, maxHits: nil, drain: -33, healing: 0,
                 critRate: 0, makesContact: true)
    }

    private func recover() -> MoveData {
        MoveData(id: 105, name: "Recover", type: "Normal", damageClass: "status",
                 power: nil, accuracy: nil, pp: 5, priority: 0,
                 minHits: nil, maxHits: nil, drain: 0, healing: 50,
                 critRate: 0, makesContact: false)
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

    @Test func gigaDrainHealsAttackerWhenBelowFull() {
        let e = engine(side1: chansey(), ab1: "natural-cure", moves1: [gigaDrain()],
                       side2: snorlax(), ab2: "thick-fat", moves2: [])
        let atk = e.side1.active(at: 0)!
        atk.currentHP = atk.maxHP / 2
        let before = atk.currentHP
        e.setAction(side: 0, slot: 0,
                    action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e.executeTurn()
        // Drain heals when the attacker is below full HP. We can't pin the exact heal
        // (depends on damage roll), but it must be > 0.
        #expect(atk.currentHP > before)
    }

    @Test func braveBirdRecoilsAttacker() {
        let e = engine(side1: snorlax(), ab1: "thick-fat", moves1: [braveBird()],
                       side2: chansey(), ab2: "natural-cure", moves2: [])
        let atk = e.side1.active(at: 0)!
        let before = atk.currentHP
        e.setAction(side: 0, slot: 0,
                    action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e.executeTurn()
        // Recoil is a positive HP loss strictly less than total HP.
        #expect(atk.currentHP < before)
    }

    @Test func rockHeadNegatesRecoil() {
        let e = engine(side1: aggron(ability: "rock-head"), ab1: "rock-head",
                       moves1: [braveBird()],
                       side2: chansey(), ab2: "natural-cure", moves2: [])
        let atk = e.side1.active(at: 0)!
        let before = atk.currentHP
        e.setAction(side: 0, slot: 0,
                    action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e.executeTurn()
        #expect(atk.currentHP == before, "Rock Head must zero out move recoil")
    }

    @Test func lifeOrbChipsAttacker() {
        let move = MoveData(id: 9999, name: "Test Special", type: "Normal",
                            damageClass: "special", power: 60, accuracy: 100, pp: 30,
                            priority: 0, minHits: nil, maxHits: nil, drain: 0,
                            healing: 0, critRate: 0, makesContact: false)
        let e = engine(side1: snorlax(), ab1: "thick-fat", item1: .lifeOrb, moves1: [move],
                       side2: chansey(), ab2: "natural-cure", moves2: [])
        let atk = e.side1.active(at: 0)!
        let before = atk.currentHP
        let expectedChip = max(1, atk.maxHP / 10)
        e.setAction(side: 0, slot: 0,
                    action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e.executeTurn()
        // Life Orb chip is exact.
        #expect(atk.currentHP == before - expectedChip)
    }

    @Test func recoverRestoresAboutFiftyPercent() {
        let e = engine(side1: snorlax(), ab1: "thick-fat", moves1: [recover()],
                       side2: chansey(), ab2: "natural-cure", moves2: [])
        let atk = e.side1.active(at: 0)!
        atk.currentHP = 1
        let expectedHeal = max(1, atk.maxHP * 50 / 100)
        e.setAction(side: 0, slot: 0,
                    action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e.executeTurn()
        #expect(atk.currentHP == min(atk.maxHP, 1 + expectedHeal))
    }
}
