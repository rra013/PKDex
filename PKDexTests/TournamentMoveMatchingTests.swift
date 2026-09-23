//
//  TournamentMoveMatchingTests.swift
//  PKDexTests
//
//  Exercise the normalized matching used by the tournament team downloader for
//  move and ability names. The actual `findMove`/`matchAbility` helpers live
//  on the SwiftUI view, but they delegate to `BattleSimSeed.normalize` for the
//  hard work — testing that shared helper at the call sites it supports keeps
//  the U-turn / King's Rock-style mismatches from regressing.
//

import Testing
import Foundation
@testable import PKDex

@Suite("Tournament Downloader — Normalized Name Matching")
struct TournamentNameMatchingTests {

    // MARK: - Hyphen / space / case folding

    @Test func limitlessHyphenMatchesSyncedSpace() {
        // Limitless says "U-turn"; PokeAPI sync stores "U Turn".
        #expect(BattleSimSeed.normalize("U-turn") == BattleSimSeed.normalize("U Turn"))
    }

    @Test func upperAndLowerVariantsCollapse() {
        // Variants seen across data sources for the same move.
        let canonical = BattleSimSeed.normalize("U-Turn")
        #expect(BattleSimSeed.normalize("u-turn") == canonical)
        #expect(BattleSimSeed.normalize("U-turn") == canonical)
        #expect(BattleSimSeed.normalize("u turn") == canonical)
        #expect(BattleSimSeed.normalize("uTurn")  == canonical)
    }

    @Test func apostrophesAndPunctuationStripped() {
        // "King's Rock" vs "Kings Rock" — apostrophes shouldn't break the match.
        #expect(BattleSimSeed.normalize("King's Rock") == BattleSimSeed.normalize("Kings Rock"))
        // "Will-O-Wisp" vs "Will O Wisp"
        #expect(BattleSimSeed.normalize("Will-O-Wisp") == BattleSimSeed.normalize("Will O Wisp"))
        // "Double-Edge" vs "Double Edge"
        #expect(BattleSimSeed.normalize("Double-Edge") == BattleSimSeed.normalize("Double Edge"))
    }

    @Test func differentMovesStillDistinguishable() {
        // Sanity check — the normalizer shouldn't collapse unrelated moves.
        #expect(BattleSimSeed.normalize("U-Turn") != BattleSimSeed.normalize("U-Wave"))
        #expect(BattleSimSeed.normalize("Flamethrower") != BattleSimSeed.normalize("Flame Wheel"))
    }

    // MARK: - Move ID matching against synthetic MoveData

    private func makeMove(id: Int, name: String) -> MoveData {
        MoveData(id: id, name: name, type: "Normal", damageClass: "physical",
                 power: 70, accuracy: 100, pp: 20, priority: 0,
                 minHits: nil, maxHits: nil, drain: 0, healing: 0,
                 critRate: 0, makesContact: true)
    }

    /// Mirrors the `findMove` lookup the view performs: normalize both sides
    /// and pick the first hit. Lets us verify the algorithm independent of the
    /// SwiftUI layer.
    private func lookup(_ attackName: String, in allMoves: [MoveData]) -> MoveData? {
        let target = BattleSimSeed.normalize(attackName)
        return allMoves.first { BattleSimSeed.normalize($0.name) == target }
    }

    @Test func uTurnResolvesAgainstSyncedSpaceName() {
        // The local Pokedex stores "U Turn" (space), Limitless says "U-turn".
        let move = makeMove(id: 369, name: "U Turn")
        let hit = lookup("U-turn", in: [move])
        #expect(hit?.id == 369)
    }

    @Test func willOWispMatchesAcrossPunctuation() {
        let move = makeMove(id: 261, name: "Will O Wisp")
        #expect(lookup("Will-O-Wisp", in: [move])?.id == 261)
        #expect(lookup("Will-o-Wisp", in: [move])?.id == 261)
    }

    @Test func multipleMovesPickFirstNormalizedHit() {
        let uturn = makeMove(id: 369, name: "U Turn")
        let unrelated = makeMove(id: 4, name: "Tackle")
        #expect(lookup("U-turn", in: [unrelated, uturn])?.id == 369)
    }

    @Test func emptyAttackStringFails() {
        let move = makeMove(id: 1, name: "Tackle")
        #expect(lookup("", in: [move]) == nil)
    }

    @Test func attackWithNoLettersStillFails() {
        // Pure punctuation collapses to "" under the normalizer.
        let move = makeMove(id: 1, name: "Tackle")
        #expect(lookup("---", in: [move]) == nil)
    }

    // MARK: - Ability lookup

    @Test func abilityListMatchAcrossSpaces() {
        // Stats list abilities as hyphenated IDs; Limitless emits display names.
        let stats = PKMNStats(id: 681, speciesID: 681, name: "Aegislash-Shield",
                              type1: "Steel", type2: "Ghost",
                              baseHP: 60, baseAtk: 50, baseDef: 140,
                              baseSpAtk: 50, baseSpDef: 140, baseSpeed: 60,
                              ability1: "stance-change")
        // The view's matcher walks `stats.allAbilities` with the same normalizer.
        let target = BattleSimSeed.normalize("Stance Change")
        let hit = stats.allAbilities.first { BattleSimSeed.normalize($0) == target }
        #expect(hit == "stance-change")
    }
}
