//
//  BattleCritTests.swift
//  PKDexTests
//

import Testing
import Foundation
@testable import PKDex

@MainActor
@Suite("Battle Engine — Critical Hits & Stat Stages")
struct BattleCritTests {

    private func gengar() -> PKMNStats {
        PKMNStats(id: 94, speciesID: 94, name: "Gengar",
                  type1: "Ghost", type2: "Poison",
                  baseHP: 60, baseAtk: 65, baseDef: 60,
                  baseSpAtk: 130, baseSpDef: 75, baseSpeed: 110,
                  ability1: "cursed-body")
    }

    private func alakazam() -> PKMNStats {
        // Slowbro stats — Psychic-type so Shadow Ball is super-effective, plus chunky
        // HP/SpDef so a crit doesn't OHKO at +2 SpDef during the comparison. Naming
        // kept as `alakazam` for call-site brevity.
        PKMNStats(id: 80, speciesID: 80, name: "Slowbro",
                  type1: "Water", type2: "Psychic",
                  baseHP: 95, baseAtk: 75, baseDef: 110,
                  baseSpAtk: 100, baseSpDef: 80, baseSpeed: 30,
                  ability1: "regenerator")
    }

    /// Low-power Ghost-type probe move. Power is deliberately small (30 BP) so a
    /// guaranteed crit doesn't OHKO the bulky defender we set up — that would
    /// collapse the comparison since the HP loss bottoms out at maxHP.
    private func probeMove() -> MoveData {
        MoveData(id: 9990, name: "ProbeGhost", type: "Ghost", damageClass: "special",
                 power: 30, accuracy: 100, pp: 15, priority: 0,
                 minHits: nil, maxHits: nil, drain: 0, healing: 0,
                 critRate: 0, makesContact: false)
    }

    private func slot(for p: PKMNStats, moves: [MoveData]) -> TeamSlotInfo {
        TeamSlotInfo(
            spreadName: "fixture-\(p.name)",
            pokemonID: p.id, pokemonName: p.name,
            type1: p.type1, type2: p.type2,
            abilityName: p.ability1, itemRawValue: nil,
            championsMode: false, natureID: "hardy", level: 50,
            evHP: 0, evAtk: 0, evDef: 0, evSpAtk: 0, evSpDef: 0, evSpeed: 0,
            moveSlots: moves.map {
                TeamMoveInfo(moveID: $0.id, moveName: $0.name, moveType: $0.type,
                             damageClass: $0.damageClass, power: $0.power, isSTAB: false)
            }
        )
    }

    /// Build a fresh engine with the given pre-applied stat stages so we can verify
    /// damage parity for crit vs no-crit scenarios.
    private func engineWith(attackerStages: (atk: Int, spAtk: Int),
                            defenderStages: (def: Int, spDef: Int)) -> BattleEngine {
        let move = probeMove()
        let aSlot = slot(for: gengar(), moves: [move])
        let dSlot = slot(for: alakazam(), moves: [])
        let pokemon = [gengar(), alakazam()]
        let bs1 = BattleSide(label: "Side 1", slots: [aSlot], format: .singles,
                             allPokemon: pokemon, allMoves: [move])
        let bs2 = BattleSide(label: "Side 2", slots: [dSlot], format: .singles,
                             allPokemon: pokemon, allMoves: [move])
        let e = BattleEngine(format: .singles, side1: bs1, side2: bs2,
                             allPokemon: pokemon, allMoves: [move])
        let atk = e.side1.active(at: 0)!
        let def = e.side2.active(at: 0)!
        atk.atkStage = attackerStages.atk
        atk.spAtkStage = attackerStages.spAtk
        def.defStage = defenderStages.def
        def.spDefStage = defenderStages.spDef
        return e
    }

    /// Damage computed via the engine's bridge. We mirror the call signature by
    /// reflectively invoking through executeTurn — but that mutates state. Instead,
    /// we set up the engine, force a crit using a stage-3 move, and measure HP loss.
    private func crittedHPLoss(attackerStages: (atk: Int, spAtk: Int),
                               defenderStages: (def: Int, spDef: Int)) -> Int {
        let e = engineWith(attackerStages: attackerStages, defenderStages: defenderStages)
        let attacker = e.side1.active(at: 0)!
        let defender = e.side2.active(at: 0)!
        // Manually pump a guaranteed-crit (critRate 3 = always) move via a temporary
        // move replacement on the attacker. The engine takes its move from `attacker.moves`.
        let alwaysCrit = MoveData(id: 9991, name: "ProbeCrit",
                                  type: "Ghost", damageClass: "special",
                                  power: 30, accuracy: 100, pp: 5, priority: 0,
                                  minHits: nil, maxHits: nil, drain: 0, healing: 0,
                                  critRate: 3, makesContact: false)
        // The MoveData stored on the participant is shared, so swap via the slot's
        // move list. Rebuild a slot identical to the original but with the crit move.
        let aSlot = slot(for: gengar(), moves: [alwaysCrit])
        let pokemon = [gengar(), alakazam()]
        let bs1 = BattleSide(label: "Side 1", slots: [aSlot], format: .singles,
                             allPokemon: pokemon, allMoves: [alwaysCrit])
        // Reuse a fresh defender side mirroring the stages.
        let dSlot = slot(for: alakazam(), moves: [])
        let bs2 = BattleSide(label: "Side 2", slots: [dSlot], format: .singles,
                             allPokemon: pokemon, allMoves: [alwaysCrit])
        let e2 = BattleEngine(format: .singles, side1: bs1, side2: bs2,
                              allPokemon: pokemon, allMoves: [alwaysCrit])
        let a2 = e2.side1.active(at: 0)!
        let d2 = e2.side2.active(at: 0)!
        a2.atkStage = attacker.atkStage
        a2.spAtkStage = attacker.spAtkStage
        d2.defStage = defender.defStage
        d2.spDefStage = defender.spDefStage

        let before = d2.currentHP
        e2.setAction(side: 0, slot: 0,
                     action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e2.executeTurn()
        return before - d2.currentHP
    }

    @Test func critIgnoresPositiveDefenderDefenses() {
        // Run many trials; medians should be equal since stages are ignored on crit.
        // We compare individual sums across many trials to dampen the damage roll.
        var sumPlusTwo = 0, sumNeutral = 0
        let trials = 40
        for _ in 0..<trials {
            sumPlusTwo += crittedHPLoss(attackerStages: (0, 0),
                                        defenderStages: (0, 2))
            sumNeutral += crittedHPLoss(attackerStages: (0, 0),
                                        defenderStages: (0, 0))
        }
        // They should be within 10% of each other — crit ignores +2 SpDef.
        let avgA = Double(sumPlusTwo) / Double(trials)
        let avgB = Double(sumNeutral) / Double(trials)
        let ratio = avgA / avgB
        #expect(ratio > 0.9 && ratio < 1.1,
                "Crit must ignore +2 SpDef on defender. Got ratio \(ratio)")
    }

    @Test func critIgnoresNegativeAttackerOffense() {
        var sumMinusTwo = 0, sumNeutral = 0
        let trials = 40
        for _ in 0..<trials {
            sumMinusTwo += crittedHPLoss(attackerStages: (0, -2),
                                         defenderStages: (0, 0))
            sumNeutral  += crittedHPLoss(attackerStages: (0, 0),
                                         defenderStages: (0, 0))
        }
        let avgA = Double(sumMinusTwo) / Double(trials)
        let avgB = Double(sumNeutral) / Double(trials)
        let ratio = avgA / avgB
        #expect(ratio > 0.9 && ratio < 1.1,
                "Crit must ignore -2 SpAtk on attacker. Got ratio \(ratio)")
    }
}
