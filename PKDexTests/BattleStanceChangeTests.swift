//
//  BattleStanceChangeTests.swift
//  PKDexTests
//
//  Coverage for Aegislash's Stance Change ability and the tournament-downloader
//  alias map that resolves "Aegislash" to the canonical "Aegislash-Shield" row.
//

import Testing
import Foundation
@testable import PKDex

@MainActor
@Suite("Battle Engine — Stance Change")
struct BattleStanceChangeTests {

    private func aegislashShield() -> PKMNStats {
        // Mirrors what the GraphQL sync inserts as the default Aegislash row.
        PKMNStats(id: 681, speciesID: 681, name: "Aegislash-Shield",
                  type1: "Steel", type2: "Ghost",
                  baseHP: 60, baseAtk: 50, baseDef: 150,
                  baseSpAtk: 50, baseSpDef: 150, baseSpeed: 60,
                  ability1: "stance-change")
    }

    private func aegislashBlade() -> PKMNStats {
        // Alternate-form row inserted by the sync. Used to confirm even a saved
        // Blade-named spread still starts the battle in Shield Forme.
        PKMNStats(id: 10027, speciesID: 681, name: "Aegislash-Blade",
                  type1: "Steel", type2: "Ghost",
                  baseHP: 60, baseAtk: 150, baseDef: 50,
                  baseSpAtk: 150, baseSpDef: 50, baseSpeed: 60,
                  ability1: "stance-change")
    }

    private func charmander() -> PKMNStats {
        PKMNStats(id: 4, speciesID: 4, name: "Charmander",
                  type1: "Fire", type2: nil,
                  baseHP: 39, baseAtk: 52, baseDef: 43,
                  baseSpAtk: 60, baseSpDef: 50, baseSpeed: 65,
                  ability1: "blaze")
    }

    private func shadowBall() -> MoveData {
        MoveData(id: 247, name: "Shadow Ball", type: "Ghost", damageClass: "special",
                 power: 80, accuracy: 100, pp: 15, priority: 0,
                 minHits: nil, maxHits: nil, drain: 0, healing: 0,
                 critRate: 0, makesContact: false)
    }

    private func kingsShield() -> MoveData {
        MoveData(id: 588, name: "King's Shield", type: "Steel", damageClass: "status",
                 power: nil, accuracy: nil, pp: 10, priority: 4,
                 minHits: nil, maxHits: nil, drain: 0, healing: 0,
                 critRate: 0, makesContact: false)
    }

    private func slot(for p: PKMNStats, ability: String, moves: [MoveData]) -> TeamSlotInfo {
        TeamSlotInfo(
            spreadName: "fixture-\(p.name)",
            pokemonID: p.id, pokemonName: p.name,
            type1: p.type1, type2: p.type2,
            abilityName: ability, itemRawValue: nil,
            championsMode: false, natureID: "hardy", level: 50,
            evHP: 0, evAtk: 0, evDef: 0, evSpAtk: 0, evSpDef: 0, evSpeed: 0,
            moveSlots: moves.map {
                TeamMoveInfo(moveID: $0.id, moveName: $0.name, moveType: $0.type,
                             damageClass: $0.damageClass, power: $0.power, isSTAB: false)
            }
        )
    }

    private func engine(aegislash: PKMNStats, moves: [MoveData],
                        opponent: PKMNStats) -> BattleEngine {
        let aSlot = slot(for: aegislash, ability: "stance-change", moves: moves)
        let oSlot = slot(for: opponent, ability: opponent.ability1 ?? "blaze", moves: [])
        let pokemon = [aegislash, opponent]
        let bs1 = BattleSide(label: "Side 1", slots: [aSlot], format: .singles,
                             allPokemon: pokemon, allMoves: moves)
        let bs2 = BattleSide(label: "Side 2", slots: [oSlot], format: .singles,
                             allPokemon: pokemon, allMoves: moves)
        return BattleEngine(format: .singles, side1: bs1, side2: bs2,
                            allPokemon: pokemon, allMoves: moves)
    }

    @Test func aegislashStartsInShieldForme() {
        let e = engine(aegislash: aegislashShield(), moves: [shadowBall()],
                       opponent: charmander())
        let a = e.side1.active(at: 0)!
        #expect(a.stanceForm == .aegislashShield)
        #expect(a.baseDef == 150)
        #expect(a.baseAtk == 50)
        #expect(a.displayName == "Aegislash-Shield")
    }

    @Test func aegislashStartsInShieldFormeEvenIfBladeRowWasSaved() {
        // Even when the user's saved spread points at the Blade row (e.g. team
        // builder picked that form), Stance Change forces Shield Forme on entry.
        let e = engine(aegislash: aegislashBlade(), moves: [shadowBall()],
                       opponent: charmander())
        let a = e.side1.active(at: 0)!
        #expect(a.stanceForm == .aegislashShield)
        #expect(a.baseDef == 150, "Should reflect Shield-Forme Def regardless of saved row")
    }

    @Test func damagingMoveFlipsToBladeForme() {
        let e = engine(aegislash: aegislashShield(), moves: [shadowBall()],
                       opponent: charmander())
        e.setAction(side: 0, slot: 0,
                    action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e.executeTurn()
        let a = e.side1.active(at: 0)!
        #expect(a.stanceForm == .aegislashBlade)
        #expect(a.baseAtk == 150)
        #expect(a.baseDef == 50)
    }

    @Test func kingsShieldFlipsBackToShieldForme() {
        let e = engine(aegislash: aegislashShield(),
                       moves: [shadowBall(), kingsShield()],
                       opponent: charmander())
        let a = e.side1.active(at: 0)!
        // Flip to Blade with a damaging move.
        e.setAction(side: 0, slot: 0,
                    action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e.executeTurn()
        #expect(a.stanceForm == .aegislashBlade)
        // Flip back with King's Shield.
        e.setAction(side: 0, slot: 0,
                    action: .move(moveIndex: 1, targetSide: 1, targetSlot: 0))
        e.executeTurn()
        #expect(a.stanceForm == .aegislashShield)
        #expect(a.baseDef == 150)
    }

    @Test func switchOutResetsStanceToShield() {
        let e = engine(aegislash: aegislashShield(), moves: [shadowBall()],
                       opponent: charmander())
        let a = e.side1.active(at: 0)!
        a.stanceForm = .aegislashBlade
        a.resetVolatile()
        #expect(a.stanceForm == .aegislashShield,
                "Aegislash always sheds Blade Forme on switch out")
    }

    @Test func nonStanceChangeIgnoresForm() {
        // A different ability shouldn't pick up the Stance Change init logic.
        let stats = aegislashShield()
        stats.ability1 = "battle-armor" // hypothetical
        let aSlot = slot(for: stats, ability: "battle-armor", moves: [shadowBall()])
        let oSlot = slot(for: charmander(), ability: "blaze", moves: [])
        let pokemon = [stats, charmander()]
        let bs1 = BattleSide(label: "Side 1", slots: [aSlot], format: .singles,
                             allPokemon: pokemon, allMoves: [shadowBall()])
        let bs2 = BattleSide(label: "Side 2", slots: [oSlot], format: .singles,
                             allPokemon: pokemon, allMoves: [shadowBall()])
        let e = BattleEngine(format: .singles, side1: bs1, side2: bs2,
                             allPokemon: pokemon, allMoves: [shadowBall()])
        #expect(e.side1.active(at: 0)?.stanceForm == nil)
    }
}

@Suite("Tournament Downloader — Species Alias Map")
struct TournamentSpeciesAliasTests {

    @Test func aegislashAliasesShieldThenBladeThenRaw() {
        let candidates = TournamentSpeciesAlias.candidates(for: "Aegislash")
        // Aliases come first so the downloader prefers the canonical form rows
        // over the (non-existent) raw "Aegislash" row.
        #expect(candidates.first == "Aegislash-Shield")
        let shieldIdx = candidates.firstIndex(of: "Aegislash-Shield") ?? Int.max
        let bladeIdx = candidates.firstIndex(of: "Aegislash-Blade") ?? Int.max
        let rawIdx = candidates.firstIndex(of: "Aegislash") ?? Int.max
        #expect(shieldIdx < bladeIdx)
        #expect(bladeIdx < rawIdx)
    }

    @Test func aliasMatchIsCaseInsensitive() {
        let candidates = TournamentSpeciesAlias.candidates(for: "aegislash")
        #expect(candidates.contains("Aegislash-Shield"))
    }

    @Test func unknownSpeciesGetsOnlyRawCandidate() {
        let candidates = TournamentSpeciesAlias.candidates(for: "Garchomp")
        #expect(candidates == ["Garchomp"])
    }

    @Test func floetteResolvesToEternalForm() {
        // Champions reports list Eternal Flower as just "Floette". The local
        // Pokedex has BOTH regular "Floette" and "Floette-Eternal" — the alias
        // must win so the right row is picked.
        let candidates = TournamentSpeciesAlias.candidates(for: "Floette")
        #expect(candidates.first == "Floette-Eternal")
        let eternalIdx = candidates.firstIndex(of: "Floette-Eternal") ?? Int.max
        let rawIdx = candidates.firstIndex(of: "Floette") ?? Int.max
        #expect(eternalIdx < rawIdx)
    }

    @Test func eternalFlowerFloetteCanonicalNameResolves() {
        // The canonical English form name.
        let candidates = TournamentSpeciesAlias.candidates(for: "Eternal Flower Floette")
        #expect(candidates.first == "Floette-Eternal")
    }

    @Test func formNamePassesThroughForFloetteEternal() {
        // Showdown-style name is already disambiguated.
        let candidates = TournamentSpeciesAlias.candidates(for: "Floette-Eternal")
        #expect(candidates.contains("Floette-Eternal"))
    }

    // MARK: - Basculegion (form picked from moveset)

    @Test func basculegionPicksMaleWhenMostlyPhysical() {
        // 3 physical, 1 special → strict majority physical → Male first.
        let candidates = TournamentSpeciesAlias.basculegionFormCandidates(
            physicalCount: 3, specialCount: 1)
        #expect(candidates.first == "Basculegion-Male")
        let maleIdx = candidates.firstIndex(of: "Basculegion-Male") ?? Int.max
        let femaleIdx = candidates.firstIndex(of: "Basculegion-Female") ?? Int.max
        #expect(maleIdx < femaleIdx)
    }

    @Test func basculegionPicksFemaleWhenMostlySpecial() {
        let candidates = TournamentSpeciesAlias.basculegionFormCandidates(
            physicalCount: 1, specialCount: 3)
        #expect(candidates.first == "Basculegion-Female")
    }

    @Test func basculegionDefaultsToFemaleOnTie() {
        // "otherwise female" — ties don't favor Male.
        let candidates = TournamentSpeciesAlias.basculegionFormCandidates(
            physicalCount: 2, specialCount: 2)
        #expect(candidates.first == "Basculegion-Female")
    }

    @Test func basculegionDefaultsToFemaleWithOnlyStatusMoves() {
        // All status moves → both counts 0 → falls into the "otherwise" branch.
        let candidates = TournamentSpeciesAlias.basculegionFormCandidates(
            physicalCount: 0, specialCount: 0)
        #expect(candidates.first == "Basculegion-Female")
    }

    @Test func basculegionCandidatesIncludeRawAsFallback() {
        let candidates = TournamentSpeciesAlias.basculegionFormCandidates(
            physicalCount: 4, specialCount: 0)
        #expect(candidates.contains("Basculegion"))
        // Raw "Basculegion" exists in the local Pokedex (the Male-form row uses
        // the species name), so keeping it as a fallback prevents a hard fail.
        let rawIdx = candidates.firstIndex(of: "Basculegion") ?? Int.max
        let maleIdx = candidates.firstIndex(of: "Basculegion-Male") ?? Int.max
        #expect(maleIdx < rawIdx)
    }
}

@Suite("Champions Format — Reverse Species Canonicalization")
struct ChampionsFormatCanonicalNameTests {

    @Test func floetteEternalCollapsesToFloette() {
        // The Champions whitelist uses "Floette" with Eternal Flower stats, so
        // the slot's local row name must collapse for validation.
        #expect(ChampionsFormat.canonicalChampionsSpecies("Floette-Eternal") == "Floette")
    }

    @Test func aegislashFormsCollapseToBase() {
        // Whitelist has just "Aegislash"; both stored form rows must collapse.
        #expect(ChampionsFormat.canonicalChampionsSpecies("Aegislash-Shield") == "Aegislash")
        #expect(ChampionsFormat.canonicalChampionsSpecies("Aegislash-Blade") == "Aegislash")
    }

    @Test func basculegionFormsCollapseToBase() {
        // Champions whitelist treats Basculegion as a single species.
        #expect(ChampionsFormat.canonicalChampionsSpecies("Basculegion-Male") == "Basculegion")
        #expect(ChampionsFormat.canonicalChampionsSpecies("Basculegion-Female") == "Basculegion")
    }

    @Test func unmappedNamesPassThroughUnchanged() {
        #expect(ChampionsFormat.canonicalChampionsSpecies("Garchomp") == "Garchomp")
        #expect(ChampionsFormat.canonicalChampionsSpecies("Mega Charizard Y") == "Mega Charizard Y")
    }

    @Test func pokemonSetUsesCanonicalChampionsName() {
        // End-to-end: a slot saved as "Floette-Eternal" must produce a
        // PokemonSet with species "Floette" so the validator's whitelist hits.
        let slot = TeamSlotInfo(
            spreadName: "test",
            pokemonID: 10061, pokemonName: "Floette-Eternal",
            type1: "Fairy", type2: nil,
            abilityName: "flower-veil", itemRawValue: nil,
            championsMode: true, natureID: "modest", level: 50,
            evHP: 0, evAtk: 0, evDef: 0, evSpAtk: 32, evSpDef: 0, evSpeed: 32,
            moveSlots: []
        )
        let set = ChampionsFormat.pokemonSet(from: slot)
        #expect(set.species == "Floette")
    }
}
