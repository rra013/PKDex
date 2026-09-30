//
//  SpeedRequest.swift
//  PKReference
//
//  A speed comparison asked for by Siri, Spotlight or Shortcuts: two
//  Pokémon and each one's Speed, which is always chosen, never assumed. The
//  intent answers with it, and its Open button loads the first into Speed
//  Tiers with the second as the benchmark.
//

import Foundation
import SwiftData

/// A Pokémon's Speed in a speed comparison.
enum SpeedChoice: Hashable, Codable, Sendable {
    /// No Speed EVs or stat points, a neutral nature, level 50.
    case noInvestment
    /// Full Speed EVs or stat points, a neutral nature, level 50.
    case fullInvestment
    /// Full Speed EVs or stat points and a nature that raises Speed (Jolly),
    /// level 50.
    case fullInvestmentSpeedNature
    /// A saved set, as saved: its Speed, nature, level and mode, with its
    /// Choice Scarf, and as its Mega when it holds the Mega Stone.
    case savedSet(PersistentIdentifier)
}

struct SpeedRequest: Hashable, Sendable {
    /// `PKMNStats.id` of each Pokémon.
    var firstID: Int
    var firstStats: SpeedChoice
    var secondID: Int
    var secondStats: SpeedChoice
}

extension CalcSide {
    /// Loads one Pokémon of a speed comparison, with no stat stages. A
    /// Pokémon without a saved set gets `championsMode`; a saved set brings
    /// its own. Returns false when the Pokémon or the set isn't in the store,
    /// or the set is another Pokémon's.
    func load(pokemonID: Int, speed: SpeedChoice, championsMode: Bool,
              allPokemon: [PKMNStats], allMoves: [MoveData], context: ModelContext) -> Bool {
        switch speed {
        case .savedSet(let id):
            let descriptor = FetchDescriptor<SavedSpread>(predicate: #Predicate { $0.persistentModelID == id })
            guard let spread = try? context.fetch(descriptor).first else { return false }
            loadSpread(spread, allPokemon: allPokemon, allMoves: allMoves)
            guard pokemon?.id == pokemonID else { return false }
            // Mega Evolution comes before anyone moves, so the Mega's Speed
            // is the one that counts.
            megaActive = canMegaEvolve
        case .noInvestment, .fullInvestment, .fullInvestmentSpeedNature:
            guard let match = allPokemon.first(where: { $0.id == pokemonID }) else { return false }
            loadUninvested(match, championsMode: championsMode)
            if speed == .fullInvestmentSpeedNature {
                nature = allNatures.first { $0.id == "jolly" } ?? nature
            }
            if speed != .noInvestment {
                evSpeed = evPerStatMax
            }
        }
        speedStage = 0
        return true
    }

    /// The side's Speed with its Choice Scarf, if it holds one: Speed
    /// Tiers' "Your Speed" with the item picked to match.
    var speedWithItem: Int {
        applySpeedModifiers(speed, item: holdsChoiceScarf ? .choiceScarf : .none, ability: .none)
    }

    var holdsChoiceScarf: Bool { effectiveHeldItem == .choiceScarf }
}
