//
//  CalcRequest.swift
//  PKDex
//
//  A damage calc asked for by Siri, Spotlight or Shortcuts: two Pokémon, a
//  move, and each side's stats, which are always chosen, never assumed. The
//  intent answers with it, and its Open button loads the same request into
//  the calc screen, so the two can't disagree.
//

import Foundation
import SwiftData

/// A side's stats in a calc request.
enum StatChoice: Hashable, Codable, Sendable {
    /// No EVs or stat points, a neutral nature, level 50.
    case noInvestment
    /// Full EVs or stat points in the stats the move uses (the attacking
    /// stat for the attacker; HP and the matching defense for the
    /// defender), a neutral nature, level 50.
    case fullInvestment
    /// A saved set, as saved: its stats, nature, level, ability, item and
    /// mode.
    case savedSet(PersistentIdentifier)
}

struct CalcRequest: Hashable, Sendable {
    /// `PKMNStats.id` of each side, and `MoveData.id` of the move.
    var attackerID: Int
    var attackerStats: StatChoice
    var defenderID: Int
    var defenderStats: StatChoice
    var moveID: Int
}

extension DamageCalcVM {
    /// Loads `request` into two new sides: the attacker with just the move,
    /// the defender with no moves, and neither with stat stages, status or
    /// side conditions. A side without a saved set gets `championsMode`, its
    /// Pokémon's first ability and no item; a saved set brings its own.
    /// Returns false, leaving the sides partly loaded, when a Pokémon, the
    /// move or a set isn't in the store.
    @discardableResult
    func load(_ request: CalcRequest, championsMode: Bool, context: ModelContext) -> Bool {
        side1 = CalcSide()
        side2 = CalcSide()
        let allPokemon = (try? context.fetch(FetchDescriptor<PKMNStats>())) ?? []
        let allMoves = (try? context.fetch(FetchDescriptor<MoveData>())) ?? []
        guard let move = allMoves.first(where: { $0.id == request.moveID }) else { return false }
        return side1.load(pokemonID: request.attackerID, stats: request.attackerStats, move: move,
                          isAttacker: true, championsMode: championsMode,
                          allPokemon: allPokemon, allMoves: allMoves, context: context)
            && side2.load(pokemonID: request.defenderID, stats: request.defenderStats, move: move,
                          isAttacker: false, championsMode: championsMode,
                          allPokemon: allPokemon, allMoves: allMoves, context: context)
    }
}

extension CalcSide {
    fileprivate func load(pokemonID: Int, stats: StatChoice, move: MoveData, isAttacker: Bool,
                          championsMode: Bool, allPokemon: [PKMNStats], allMoves: [MoveData],
                          context: ModelContext) -> Bool {
        switch stats {
        case .savedSet(let id):
            let descriptor = FetchDescriptor<SavedSpread>(predicate: #Predicate { $0.persistentModelID == id })
            guard let spread = try? context.fetch(descriptor).first else { return false }
            loadSpread(spread, allPokemon: allPokemon, allMoves: allMoves)
            guard pokemon?.id == pokemonID else { return false }
        case .noInvestment, .fullInvestment:
            guard let match = allPokemon.first(where: { $0.id == pokemonID }) else { return false }
            pokemon = match
            selectedAbility = match.ability1
            heldItem = .none
            teraType = nil
            loadedSpreadName = nil
            setChampionsMode(championsMode)
            nature = allNatures.first { $0.id == "serious" } ?? allNatures[0]
            level = 50
            evHP = 0; evAtk = 0; evDef = 0; evSpAtk = 0; evSpDef = 0; evSpeed = 0
            if stats == .fullInvestment {
                let full = evPerStatMax
                let physical = move.damageClass == "physical"
                if isAttacker {
                    if physical { evAtk = full } else { evSpAtk = full }
                } else {
                    evHP = full
                    if physical { evDef = full } else { evSpDef = full }
                }
            }
        }
        moves = isAttacker ? [move, nil, nil, nil] : [nil, nil, nil, nil]
        moveSearchTexts = ["", "", "", ""]
        return true
    }
}
