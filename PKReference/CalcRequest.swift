//
//  CalcRequest.swift
//  PKReference
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
    /// Full investment, as above, and a nature that raises the stat the
    /// move uses: Adamant or Modest for the attacker, Bold or Calm for the
    /// defender.
    case fullInvestmentBoostingNature
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
        case .noInvestment, .fullInvestment, .fullInvestmentBoostingNature:
            guard let match = allPokemon.first(where: { $0.id == pokemonID }) else { return false }
            loadUninvested(match, championsMode: championsMode, allPokemon: allPokemon)
            let physical = move.damageClass == "physical"
            if stats != .noInvestment {
                let full = evPerStatMax
                if isAttacker {
                    if physical { evAtk = full } else { evSpAtk = full }
                } else {
                    evHP = full
                    if physical { evDef = full } else { evSpDef = full }
                }
            }
            if stats == .fullInvestmentBoostingNature {
                // Each lowers a stat the calc doesn't use on that side.
                let natureID = isAttacker ? (physical ? "adamant" : "modest") : (physical ? "bold" : "calm")
                nature = allNatures.first { $0.id == natureID } ?? nature
            }
        }
        moves = isAttacker ? [move, nil, nil, nil] : [nil, nil, nil, nil]
        moveSearchTexts = ["", "", "", ""]
        return true
    }

    /// `pokemon` with no set: its first ability, no item, `championsMode`,
    /// a neutral nature, level 50 and no EVs or stat points. What "no
    /// investment" means to every App Intent that asks for stats. A Mega
    /// is its species holding the Mega Stone and Mega Evolved, as the calc
    /// sets one up by hand.
    func loadUninvested(_ match: PKMNStats, championsMode: Bool, allPokemon: [PKMNStats]) {
        pokemon = match
        selectedAbility = match.ability1
        heldItem = .none
        megaActive = false
        teraType = nil
        loadedSpreadName = nil
        setChampionsMode(championsMode)
        nature = allNatures.first { $0.id == "serious" } ?? allNatures[0]
        level = 50
        evHP = 0; evAtk = 0; evDef = 0; evSpAtk = 0; evSpDef = 0; evSpeed = 0
        let form = match.formName?.lowercased() ?? ""
        if form == "mega" || form.hasPrefix("mega-"),
           let base = allPokemon.first(where: { $0.speciesID == match.speciesID && !$0.isForm }),
           let mega = MegaForms.all.first(where: {
               $0.displayName == IntentNames.spoken(name: match.name, formName: match.formName)
           }),
           let stone = mega.stone {
            pokemon = base
            selectedAbility = base.ability1
            heldItem = stone
            megaActive = true
        }
    }
}

// MARK: - A whole side

/// Everything about one calc side, to load it back exactly: the Pokémon
/// and its set, investment, stages, condition and side conditions. The
/// Problem Solver opens its answers in the calc with it.
struct SideSetup: Hashable, Sendable {
    /// `PKMNStats.id`; a Mega is its species with `megaActive`.
    var pokemonID: Int
    var ability: String?
    var item: HeldItem
    var natureID: String
    var level: Int
    var championsMode: Bool
    var megaActive: Bool
    var evs: [Int]
    var ivs: [Int]
    /// Atk, Def, SpA, SpD, Speed.
    var stages: [Int]
    var status: ShowdownStatus
    var currentHPPercent: Int
    var abilityOn: Bool
    var conditions: [Bool]
    var spikesLayers: Int
    var moveIDs: [Int?]
}

extension SideSetup {
    /// `side` as it is now; nil without a Pokémon.
    init?(_ side: CalcSide) {
        guard let pokemon = side.pokemon else { return nil }
        self.init(
            pokemonID: pokemon.id, ability: side.selectedAbility, item: side.heldItem, natureID: side.nature.id,
            level: side.level, championsMode: side.championsMode, megaActive: side.megaActive,
            evs: [side.evHP, side.evAtk, side.evDef, side.evSpAtk, side.evSpDef, side.evSpeed],
            ivs: [side.ivHP, side.ivAtk, side.ivDef, side.ivSpAtk, side.ivSpDef, side.ivSpeed],
            stages: [side.atkStage, side.defStage, side.spAtkStage, side.spDefStage, side.speedStage],
            status: side.status, currentHPPercent: side.currentHPPercent, abilityOn: side.abilityOn,
            conditions: [side.isReflect, side.isLightScreen, side.isAuroraVeil, side.isFriendGuard,
                         side.isProtected, side.isStealthRock, side.isHelpingHand, side.isTailwind],
            spikesLayers: side.spikesLayers, moveIDs: side.moves.map { $0?.id })
    }

    /// `snapshot` of the Pokémon `pokemonID`, with its moves.
    init(_ snapshot: CalcSnapshot, pokemonID: Int) {
        self.init(
            pokemonID: pokemonID, ability: snapshot.selectedAbility, item: snapshot.heldItem,
            natureID: snapshot.nature.id, level: snapshot.level, championsMode: snapshot.championsMode,
            megaActive: snapshot.megaForm != nil,
            evs: [snapshot.evHP, snapshot.evAtk, snapshot.evDef, snapshot.evSpAtk, snapshot.evSpDef, snapshot.evSpeed],
            ivs: [snapshot.ivHP, snapshot.ivAtk, snapshot.ivDef, snapshot.ivSpAtk, snapshot.ivSpDef, snapshot.ivSpeed],
            stages: [snapshot.atkStage, snapshot.defStage, snapshot.spAtkStage, snapshot.spDefStage, snapshot.speedStage],
            status: snapshot.status, currentHPPercent: snapshot.currentHPPercent, abilityOn: snapshot.abilityOn,
            conditions: [snapshot.isReflect, snapshot.isLightScreen, snapshot.isAuroraVeil, snapshot.isFriendGuard,
                         snapshot.isProtected, snapshot.isStealthRock, snapshot.isHelpingHand, snapshot.isTailwind],
            spikesLayers: snapshot.spikesLayers, moveIDs: snapshot.moves.map { $0.id })
    }

    /// Loads this into `side`. Returns false when the Pokémon isn't in
    /// `allPokemon`. Moves not in `allMoves` are left empty.
    @discardableResult
    func apply(to side: CalcSide, allPokemon: [PKMNStats], allMoves: [MoveData]) -> Bool {
        guard let pokemon = allPokemon.first(where: { $0.id == pokemonID }) else { return false }
        side.pokemon = pokemon
        side.searchText = ""
        side.selectedAbility = ability
        side.heldItem = item
        side.teraType = nil
        side.loadedSpreadName = nil
        side.nature = allNatures.first { $0.id == natureID } ?? side.nature
        side.level = level
        side.championsMode = championsMode
        side.megaActive = megaActive
        (side.evHP, side.evAtk, side.evDef, side.evSpAtk, side.evSpDef, side.evSpeed)
            = (evs[0], evs[1], evs[2], evs[3], evs[4], evs[5])
        (side.ivHP, side.ivAtk, side.ivDef, side.ivSpAtk, side.ivSpDef, side.ivSpeed)
            = (ivs[0], ivs[1], ivs[2], ivs[3], ivs[4], ivs[5])
        (side.atkStage, side.defStage, side.spAtkStage, side.spDefStage, side.speedStage)
            = (stages[0], stages[1], stages[2], stages[3], stages[4])
        side.status = status
        side.currentHPPercent = currentHPPercent
        side.abilityOn = abilityOn
        (side.isReflect, side.isLightScreen, side.isAuroraVeil, side.isFriendGuard,
         side.isProtected, side.isStealthRock, side.isHelpingHand, side.isTailwind)
            = (conditions[0], conditions[1], conditions[2], conditions[3],
               conditions[4], conditions[5], conditions[6], conditions[7])
        side.spikesLayers = spikesLayers
        let slots = (moveIDs + [nil, nil, nil, nil]).prefix(4)
        side.moves = slots.map { id in id.flatMap { id in allMoves.first { $0.id == id } } }
        side.moveSearchTexts = ["", "", "", ""]
        return true
    }
}

/// Both sides of a calc to open, and whether it's doubles.
struct CalcSides: Hashable, Sendable {
    var attacker: SideSetup
    var defender: SideSetup
    var doubles: Bool
}
