//
//  CountersRequest.swift
//  PKReference
//
//  "What beats Incineroar?" asked of Siri, Spotlight or Shortcuts: the
//  Pokémon to beat, with its investment chosen, never assumed. The intent
//  answers from the Problem Solver, and its Open button opens the Problem
//  Solver on the same set, so the two can't disagree.
//

import Foundation
import SwiftData

/// The investment of the Pokémon to beat.
enum TargetStats: Hashable, Codable, Sendable {
    /// No EVs or stat points, a neutral nature, level 50.
    case noInvestment
    /// Full HP and Defense, a neutral nature, level 50.
    case physicallyBulky
    /// Full HP and Special Defense, a neutral nature, level 50.
    case speciallyBulky
    /// A saved set, as saved, on Champions rules, and as its Mega when it
    /// holds the Mega Stone.
    case savedSet(PersistentIdentifier)
}

struct CountersRequest: Hashable, Sendable {
    /// `PKMNStats.id` of the Pokémon to beat.
    var pokemonID: Int
    var stats: TargetStats
}

extension CalcSide {
    /// Loads the Pokémon to beat on Champions rules, the Problem Solver's,
    /// with no moves. Without a saved set it gets `ability` if it has it
    /// (the one tournament teams run most), else its first. Returns false
    /// when the Pokémon or the set isn't in the store, or the set is
    /// another Pokémon's.
    func load(pokemonID: Int, target stats: TargetStats, ability: String?,
              allPokemon: [PKMNStats], allMoves: [MoveData], context: ModelContext) -> Bool {
        switch stats {
        case .savedSet(let id):
            let descriptor = FetchDescriptor<SavedSpread>(predicate: #Predicate { $0.persistentModelID == id })
            guard let spread = try? context.fetch(descriptor).first else { return false }
            loadSpread(spread, allPokemon: allPokemon, allMoves: allMoves)
            guard pokemon?.id == pokemonID else { return false }
            setChampionsMode(true)
            // Mega Evolution comes before anyone moves.
            megaActive = canMegaEvolve
        case .noInvestment, .physicallyBulky, .speciallyBulky:
            guard let match = allPokemon.first(where: { $0.id == pokemonID }) else { return false }
            loadUninvested(match, championsMode: true, allPokemon: allPokemon)
            if !megaActive, let ability, match.allAbilities.contains(ability) { selectedAbility = ability }
            if stats != .noInvestment {
                evHP = evPerStatMax
                if stats == .physicallyBulky { evDef = evPerStatMax } else { evSpDef = evPerStatMax }
            }
        }
        moves = [nil, nil, nil, nil]
        moveSearchTexts = ["", "", "", ""]
        return true
    }
}
