//
//  SpreadMoves.swift
//  PKDex
//
//  Which moves hit more than one Pokemon in doubles, and whom they hit.
//
//  The bundled Showdown data carries each move's `target`, which is the source
//  of truth: `allAdjacentFoes` (Hyper Voice, Heat Wave, Rock Slide…) hits both
//  foes; `allAdjacent` (Earthquake, Surf, Explosion…) hits both foes *and* the
//  user's ally. The port reads the same field, so the damage calc, the battle
//  sim and the EV solver can't disagree about what's a spread move.
//
//  This replaces a hand-written list in the battle sim that had 19 of the
//  data's 39 spread moves and wrongly included Earth Power (single-target).
//  Moves missing from the Champions data fall back to a short canonical list.
//
//  Not modelled: Expanding Force, which becomes spread only in Psychic
//  Terrain when the user is grounded. The port handles it for damage; the sim
//  and this helper treat it as single-target.
//

import Foundation

nonisolated enum MoveTargeting: Equatable, Sendable {
    case single
    /// Both foes.
    case allAdjacentFoes
    /// Both foes and the user's ally.
    case allAdjacent

    var isSpread: Bool { self != .single }
    var hitsAlly: Bool { self == .allAdjacent }
}

nonisolated enum SpreadMoves {

    /// How `moveName` targets in doubles. Case, spacing and punctuation don't
    /// matter ("Hyper Voice", "hyper-voice", "HyperVoice").
    static func targeting(of moveName: String) -> MoveTargeting {
        let id = toID(moveName)
        if let data = ShowdownGen0.shared.move(id) {
            switch data.target {
            case "allAdjacentFoes": return .allAdjacentFoes
            case "allAdjacent":     return .allAdjacent
            default:                return .single
            }
        }
        return fallback[id] ?? .single
    }

    static func isSpread(_ moveName: String) -> Bool {
        targeting(of: moveName).isSpread
    }

    /// Spread moves outside the Champions data (mainline-only), by ID.
    static let fallback: [String: MoveTargeting] = [
        "originpulse": .allAdjacentFoes, "precipiceblades": .allAdjacentFoes,
        "glaciate": .allAdjacentFoes, "diamondstorm": .allAdjacentFoes,
        "razorleaf": .allAdjacentFoes, "swift": .allAdjacentFoes,
        "twister": .allAdjacentFoes, "powdersnow": .allAdjacentFoes,
        "bleakwindstorm": .allAdjacentFoes, "wildboltstorm": .allAdjacentFoes,
        "sandsearstorm": .allAdjacentFoes, "springtidestorm": .allAdjacentFoes,
        "mindblown": .allAdjacent, "searingshot": .allAdjacent,
        "magnitude": .allAdjacent, "synchronoise": .allAdjacent,
    ]
}
