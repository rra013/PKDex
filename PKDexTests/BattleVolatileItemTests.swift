//
//  BattleVolatileItemTests.swift
//  PKDexTests
//
//  Coverage for the previously-no-op Champions-legal items: Mental Herb,
//  Persim Berry, and Leppa Berry, plus the volatile mechanics they hook into.
//

import Testing
import Foundation
@testable import PKDex

@MainActor
@Suite("Battle Engine — Confusion + Persim Berry")
struct BattleConfusionTests {

    private func chansey() -> PKMNStats {
        PKMNStats(id: 113, speciesID: 113, name: "Chansey",
                  type1: "Normal", type2: nil,
                  baseHP: 250, baseAtk: 5, baseDef: 5,
                  baseSpAtk: 35, baseSpDef: 105, baseSpeed: 50,
                  ability1: "natural-cure")
    }

    private func snorlax() -> PKMNStats {
        PKMNStats(id: 143, speciesID: 143, name: "Snorlax",
                  type1: "Normal", type2: nil,
                  baseHP: 160, baseAtk: 110, baseDef: 65,
                  baseSpAtk: 65, baseSpDef: 110, baseSpeed: 30,
                  ability1: "thick-fat")
    }

    private func confuseRay() -> MoveData {
        MoveData(id: 109, name: "Confuse Ray", type: "Ghost", damageClass: "status",
                 power: nil, accuracy: 100, pp: 10, priority: 0,
                 minHits: nil, maxHits: nil, drain: 0, healing: 0,
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

    @Test func confuseRayConfusesTarget() {
        let e = engine(side1: chansey(), ab1: "natural-cure", moves1: [confuseRay()],
                       side2: snorlax(), ab2: "thick-fat", moves2: [])
        e.setAction(side: 0, slot: 0,
                    action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e.executeTurn()
        let target = e.side2.active(at: 0)!
        #expect(target.confused == true)
        #expect(target.confusionTurnsRemaining > 0)
    }

    @Test func persimBerryCuresConfusionImmediately() {
        let e = engine(side1: chansey(), ab1: "natural-cure", moves1: [confuseRay()],
                       side2: snorlax(), ab2: "thick-fat", item2: .persimBerry, moves2: [])
        e.setAction(side: 0, slot: 0,
                    action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e.executeTurn()
        let target = e.side2.active(at: 0)!
        #expect(target.confused == false, "Persim Berry should cure confusion on application")
        #expect(target.consumedItem == true, "Persim Berry should be consumed")
    }

    @Test func lumBerryCuresConfusionImmediately() {
        let e = engine(side1: chansey(), ab1: "natural-cure", moves1: [confuseRay()],
                       side2: snorlax(), ab2: "thick-fat", item2: .lumBerry, moves2: [])
        e.setAction(side: 0, slot: 0,
                    action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e.executeTurn()
        let target = e.side2.active(at: 0)!
        #expect(target.confused == false)
        #expect(target.consumedItem == true)
    }

    @Test func confusionClearsOnSwitch() {
        let e = engine(side1: chansey(), ab1: "natural-cure", moves1: [confuseRay()],
                       side2: snorlax(), ab2: "thick-fat", moves2: [])
        let target = e.side2.active(at: 0)!
        target.confused = true
        target.confusionTurnsRemaining = 4
        target.resetVolatile()
        #expect(target.confused == false)
        #expect(target.confusionTurnsRemaining == 0)
    }
}

@MainActor
@Suite("Battle Engine — Taunt + Mental Herb")
struct BattleTauntTests {

    private func gengar() -> PKMNStats {
        PKMNStats(id: 94, speciesID: 94, name: "Gengar",
                  type1: "Ghost", type2: "Poison",
                  baseHP: 60, baseAtk: 65, baseDef: 60,
                  baseSpAtk: 130, baseSpDef: 75, baseSpeed: 110,
                  ability1: "cursed-body")
    }

    private func chansey() -> PKMNStats {
        PKMNStats(id: 113, speciesID: 113, name: "Chansey",
                  type1: "Normal", type2: nil,
                  baseHP: 250, baseAtk: 5, baseDef: 5,
                  baseSpAtk: 35, baseSpDef: 105, baseSpeed: 50,
                  ability1: "natural-cure")
    }

    private func taunt() -> MoveData {
        MoveData(id: 269, name: "Taunt", type: "Dark", damageClass: "status",
                 power: nil, accuracy: 100, pp: 20, priority: 0,
                 minHits: nil, maxHits: nil, drain: 0, healing: 0,
                 critRate: 0, makesContact: false)
    }

    private func softBoiled() -> MoveData {
        MoveData(id: 135, name: "Soft-Boiled", type: "Normal", damageClass: "status",
                 power: nil, accuracy: nil, pp: 10, priority: 0,
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

    @Test func tauntSetsCounter() {
        let e = engine(side1: gengar(), ab1: "cursed-body", moves1: [taunt()],
                       side2: chansey(), ab2: "natural-cure", moves2: [softBoiled()])
        e.setAction(side: 0, slot: 0,
                    action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        // Chansey doesn't act this turn — just verify the taunt applied.
        e.executeTurn()
        let target = e.side2.active(at: 0)!
        #expect(target.tauntTurnsRemaining > 0)
    }

    @Test func mentalHerbCuresTauntImmediately() {
        let e = engine(side1: gengar(), ab1: "cursed-body", moves1: [taunt()],
                       side2: chansey(), ab2: "natural-cure", item2: .mentalHerb,
                       moves2: [softBoiled()])
        e.setAction(side: 0, slot: 0,
                    action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e.executeTurn()
        let target = e.side2.active(at: 0)!
        #expect(target.tauntTurnsRemaining == 0, "Mental Herb should cure Taunt on application")
        #expect(target.consumedItem == true, "Mental Herb should be consumed")
    }

    @Test func tauntedActorCannotUseStatusMove() {
        // Pre-apply Taunt directly so we control the order. Chansey tries Soft-Boiled
        // and should be refused.
        let e = engine(side1: gengar(), ab1: "cursed-body", moves1: [],
                       side2: chansey(), ab2: "natural-cure", moves2: [softBoiled()])
        let target = e.side2.active(at: 0)!
        target.tauntTurnsRemaining = 3
        target.currentHP = 1   // Verify Soft-Boiled doesn't heal.
        e.setAction(side: 1, slot: 0,
                    action: .move(moveIndex: 0, targetSide: 0, targetSlot: 0))
        e.executeTurn()
        #expect(target.currentHP == 1, "Soft-Boiled should fizzle while taunted")
    }

    @Test func tauntClearsOnSwitch() {
        let e = engine(side1: gengar(), ab1: "cursed-body", moves1: [],
                       side2: chansey(), ab2: "natural-cure", moves2: [])
        let target = e.side2.active(at: 0)!
        target.tauntTurnsRemaining = 3
        target.resetVolatile()
        #expect(target.tauntTurnsRemaining == 0)
    }
}

@MainActor
@Suite("Battle Engine — Leppa Berry")
struct BattleLeppaBerryTests {

    private func snorlax() -> PKMNStats {
        PKMNStats(id: 143, speciesID: 143, name: "Snorlax",
                  type1: "Normal", type2: nil,
                  baseHP: 160, baseAtk: 110, baseDef: 65,
                  baseSpAtk: 65, baseSpDef: 110, baseSpeed: 30,
                  ability1: "thick-fat")
    }

    private func bulbasaur() -> PKMNStats {
        PKMNStats(id: 1, speciesID: 1, name: "Bulbasaur",
                  type1: "Grass", type2: "Poison",
                  baseHP: 45, baseAtk: 49, baseDef: 49,
                  baseSpAtk: 65, baseSpDef: 65, baseSpeed: 45,
                  ability1: "overgrow")
    }

    /// Move with a deliberately tiny PP so we can drain it to zero in one turn.
    private func lowPPTackle() -> MoveData {
        MoveData(id: 33, name: "Tackle", type: "Normal", damageClass: "physical",
                 power: 40, accuracy: 100, pp: 1, priority: 0,
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

    @Test func leppaBerryRestoresPPWhenMoveHitsZero() {
        let e = engine(side1: snorlax(), ab1: "thick-fat", item1: .leppaBerry,
                       moves1: [lowPPTackle()],
                       side2: bulbasaur(), ab2: "overgrow", moves2: [])
        let attacker = e.side1.active(at: 0)!
        #expect(attacker.pp[0] == 1)
        e.setAction(side: 0, slot: 0,
                    action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e.executeTurn()
        // After the move runs, pp goes 1 → 0 → triggers Leppa → restored to 10
        // (capped at the move's max PP, which here is 1, so we get 1).
        #expect(attacker.pp[0] == 1, "Leppa Berry restored PP, capped at the move's max PP")
        #expect(attacker.consumedItem == true)
    }

    @Test func leppaBerryNoOpWhenPPNonZero() {
        // A normal move with 35 PP — won't hit zero in one turn.
        let normal = MoveData(id: 33, name: "Tackle", type: "Normal", damageClass: "physical",
                              power: 40, accuracy: 100, pp: 35, priority: 0,
                              minHits: nil, maxHits: nil, drain: 0, healing: 0,
                              critRate: 0, makesContact: true)
        let e = engine(side1: snorlax(), ab1: "thick-fat", item1: .leppaBerry,
                       moves1: [normal],
                       side2: bulbasaur(), ab2: "overgrow", moves2: [])
        let attacker = e.side1.active(at: 0)!
        e.setAction(side: 0, slot: 0,
                    action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e.executeTurn()
        #expect(attacker.consumedItem == false, "Leppa Berry should not trigger above 0 PP")
        #expect(attacker.pp[0] == 34)
    }
}
