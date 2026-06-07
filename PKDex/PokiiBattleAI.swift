//
//  PokiiBattleAI.swift
//  PKDex
//
//  Decides actions for AI-controlled sides during a doubles battle. Watches
//  the BattleEngine and, whenever a side under its control has any unfilled
//  action slot (or is owed a force switch), runs the policy model once per
//  pending slot and commits the chosen action through `engine.setAction`.
//
//  The controller is intentionally passive: it never advances the turn, it
//  just *fills in* the side's choices. The user still presses "Execute Turn"
//  in human-vs-AI play; in AI-vs-AI play, BattleView's `.onChange` auto-runs
//  the engine once both sides are filled.
//

import Foundation
import SwiftUI

@MainActor
@Observable
final class PokiiBattleAI {

    /// Which sides this controller is responsible for. Index 0 = side 1,
    /// index 1 = side 2. `true` means the AI picks for that side.
    var sideControlled: [Bool]

    weak var engine: BattleEngine?

    init(engine: BattleEngine, side1AI: Bool, side2AI: Bool) {
        self.engine = engine
        self.sideControlled = [side1AI, side2AI]
    }

    var anyControlled: Bool { sideControlled.contains(true) }

    /// Returns true if any AI-controlled side has work to do right now —
    /// either an empty action slot, or a pending force switch. The view uses
    /// this to know when to trigger `fill()`.
    var hasPendingWork: Bool {
        guard let engine, engine.winner == nil else { return false }
        for s in 0..<2 where sideControlled[s] {
            if engine.pendingForceSwitches.contains(where: { $0.side == s }) { return true }
            for slot in 0..<engine.format.activeSlots {
                guard let p = engine.side(at: s).active(at: slot) else { continue }
                if p.fainted { continue }
                if p.moves.isEmpty && engine.side(at: s).benchIndices().isEmpty { continue }
                if engine.pendingActions[s][slot] == nil { return true }
            }
        }
        return false
    }

    /// Pick + commit one action per pending AI slot. Idempotent: slots that
    /// are already filled, or belong to a human side, are left alone.
    func fill() {
        guard let engine, engine.winner == nil else { return }

        // Per-side set of bench indices we've already committed to *this turn*.
        // Each slot's mask excludes these so two slots can't argmax onto the
        // same teammate. Seeded with whatever the human partner (if any) has
        // already queued before us.
        var claimed: [Set<Int>] = [
            claimedBench(in: engine, side: 0),
            claimedBench(in: engine, side: 1),
        ]

        // 1. Force switches take priority — the engine blocks new turns until
        //    those are resolved, so handle them before move selection.
        for fs in engine.pendingForceSwitches where sideControlled[fs.side] {
            if let bi = handleForceSwitch(side: fs.side, slot: fs.slot,
                                          claimedBench: claimed[fs.side]) {
                claimed[fs.side].insert(bi)
            }
        }

        // 2. Regular pending actions. We collect per-side mega votes alongside
        //    the chosen action so we can enforce "at most one mega per side
        //    per turn" — the engine itself caps at one per battle, but the
        //    model could request both slots in doubles, and only the higher
        //    probability one should win.
        struct MegaVote { let slot: Int; let probability: Float }
        var megaVotes: [[MegaVote]] = [[], []]

        for s in 0..<2 where sideControlled[s] {
            for slot in 0..<engine.format.activeSlots {
                guard let p = engine.side(at: s).active(at: slot), !p.fainted else { continue }
                if engine.pendingActions[s][slot] != nil { continue }
                if p.moves.isEmpty && engine.side(at: s).benchIndices().isEmpty { continue }

                let chosen = chooseAction(side: s, slot: slot, actor: p,
                                          claimedBench: claimed[s])
                let action = chosen?.action
                    ?? fallback(side: s, slot: slot, actor: p, claimedBench: claimed[s])
                guard let action else { continue }

                if case .switchTo(let bi) = action {
                    claimed[s].insert(bi)
                }
                engine.setAction(side: s, slot: slot, action: action)

                // The mega head only matters when the actor chose to move, the
                // engine says mega is legal (held stone + side hasn't used it),
                // and the model's sigmoid crosses 0.5.
                if case .move = action, let prob = chosen?.megaProbability,
                   prob >= 0.5,
                   engine.canMegaEvolve(side: s, slot: slot) {
                    megaVotes[s].append(MegaVote(slot: slot, probability: prob))
                }
            }
        }

        // Each side gets at most one mega per battle — pick the slot with the
        // higher probability if both wanted it. (Trying to set pendingMega on
        // multiple slots wouldn't break the engine, since it also enforces the
        // cap, but the lower-confidence vote shouldn't get to claim the slot.)
        for s in 0..<2 {
            guard let winner = megaVotes[s].max(by: { $0.probability < $1.probability }) else { continue }
            engine.pendingMega[s][winner.slot] = true
        }
    }

    /// Bench indices that a human (or a previous AI fill) has already wired
    /// into `pendingActions` for this side. We never want to argmax over them.
    private func claimedBench(in engine: BattleEngine, side s: Int) -> Set<Int> {
        var set = Set<Int>()
        for slot in 0..<engine.format.activeSlots {
            if case .switchTo(let bi) = engine.pendingActions[s][slot] {
                set.insert(bi)
            }
        }
        return set
    }

    // MARK: - Selection

    /// Pairs the decoded action with the mega head's probability so `fill()`
    /// can decide whether to also flip `pendingMega` for the slot.
    private struct ChosenAction {
        let action: BattleAction
        let megaProbability: Float
    }

    /// Runs the policy model for one decision point.
    private func chooseAction(side sIdx: Int, slot: Int, actor: BattleParticipant,
                              claimedBench: Set<Int>) -> ChosenAction? {
        guard let engine else { return nil }
        guard let inputs = PokiiFeaturizer.makeInputs(engine: engine, side: sIdx, slot: slot,
                                                     claimedBench: claimedBench) else {
            return nil
        }
        guard let decision = PokiiBattler.shared.chooseAction(xCat: inputs.xCat,
                                                              xCont: inputs.xCont,
                                                              mask: inputs.mask) else {
            return nil
        }
        guard let action = PokiiFeaturizer.decode(label: decision.label,
                                                  engine: engine, side: sIdx, slot: slot) else {
            return nil
        }
        return ChosenAction(action: action, megaProbability: decision.megaProbability)
    }

    /// Deterministic backup if the model gives us nothing usable (vocab miss,
    /// load failure, etc.): pick the first PP-bearing move with mirror
    /// targeting, or switch to the first un-claimed benched mon.
    private func fallback(side sIdx: Int, slot: Int, actor: BattleParticipant,
                          claimedBench: Set<Int>) -> BattleAction? {
        guard let engine else { return nil }
        // Prefer a move with PP.
        for (mi, _) in actor.moves.enumerated() {
            if actor.pp.indices.contains(mi), actor.pp[mi] > 0 {
                if BattleMoveEffects.isFixedSelfOrFieldTarget(actor.moves[mi].name) {
                    return .move(moveIndex: mi, targetSide: sIdx, targetSlot: slot)
                }
                let oppIdx = 1 - sIdx
                let oppSide = engine.side(at: oppIdx)
                let mirror = oppSide.active(at: slot) ?? oppSide.active(at: 0)
                if mirror != nil {
                    let normalized = BattleSimSeed.normalize(actor.moves[mi].name)
                    if engine.format == .doubles
                        && BattleMoveEffects.spreadMoves.contains(normalized)
                        && actor.moves[mi].damageClass != "status" {
                        return .spreadMove(moveIndex: mi)
                    }
                    let targetSlot = oppSide.active(at: slot) != nil ? slot : 0
                    return .move(moveIndex: mi, targetSide: oppIdx, targetSlot: targetSlot)
                }
            }
        }
        // No usable moves — try a switch to anyone the sibling slot hasn't claimed.
        if let bi = engine.side(at: sIdx).benchIndices().first(where: { !claimedBench.contains($0) }) {
            return .switchTo(benchIndex: bi)
        }
        // Last resort: Struggle.
        return .struggle(targetSide: 1 - sIdx, targetSlot: 0)
    }

    /// Returns the bench index we ended up sending in, so the caller can
    /// claim it before the next force-switch on the same side runs.
    @discardableResult
    private func handleForceSwitch(side sIdx: Int, slot: Int,
                                   claimedBench: Set<Int>) -> Int? {
        guard let engine else { return nil }
        let bench = engine.side(at: sIdx).benchIndices().filter { !claimedBench.contains($0) }
        guard !bench.isEmpty else { return nil }

        // Ask the model to choose among the available switches. The featurizer
        // builds a mask that only enables `switch_*` labels for current bench
        // species — minus any claimed indices — so the argmax should always
        // pick a valid one when the species is in vocab.
        var chosen = bench.first
        if let inputs = PokiiFeaturizer.makeInputs(engine: engine, side: sIdx, slot: slot,
                                                  claimedBench: claimedBench),
           let decision = PokiiBattler.shared.chooseAction(xCat: inputs.xCat,
                                                           xCont: inputs.xCont,
                                                           mask: maskForceSwitch(inputs.mask)) {
            if case .switchTo(let bi) = PokiiFeaturizer.decode(label: decision.label,
                                                              engine: engine, side: sIdx, slot: slot)
                ?? .switchTo(benchIndex: bench.first ?? 0) {
                if bench.contains(bi) { chosen = bi }
            }
        }
        if let bi = chosen {
            engine.forceSwitch(side: sIdx, slot: slot, benchIndex: bi)
            return bi
        }
        return nil
    }

    /// Zero out the move-action portion of the mask so the model only picks
    /// among switches. (A force switch can never resolve to a move.)
    private func maskForceSwitch(_ original: [Float]) -> [Float] {
        var out = original
        for (i, label) in PokiiBattler.shared.actionVocab.enumerated() where label.hasPrefix("move_") {
            out[i] = -1e9
        }
        return out
    }
}
