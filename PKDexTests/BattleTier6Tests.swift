//
//  BattleTier6Tests.swift
//  PKDexTests
//
//  Tier 6 — the previously-deferred abilities: Mold Breaker, Unaware, Moody,
//  Cute Charm (with infatuation), Battle Bond (Gen 9), Imposter, Zero to Hero.
//

import Testing
import Foundation
@testable import PKDex

@MainActor
private enum T6 {
    static func pkmn(_ name: String, id: Int = 1,
                     type1: String = "Normal", type2: String? = nil,
                     ability: String = "blaze",
                     hp: Int = 100, atk: Int = 100, def: Int = 100,
                     spa: Int = 100, spd: Int = 100, spe: Int = 100) -> PKMNStats {
        PKMNStats(id: id, speciesID: id, name: name,
                  type1: type1, type2: type2,
                  baseHP: hp, baseAtk: atk, baseDef: def,
                  baseSpAtk: spa, baseSpDef: spd, baseSpeed: spe,
                  ability1: ability)
    }

    static func mv(_ name: String, id: Int,
                   type: String = "Normal", dmg: String = "physical",
                   power: Int? = 60, priority: Int = 0,
                   makesContact: Bool = true) -> MoveData {
        MoveData(id: id, name: name, type: type, damageClass: dmg,
                 power: power, accuracy: 100, pp: 16, priority: priority,
                 minHits: nil, maxHits: nil, drain: 0, healing: 0,
                 critRate: 0, makesContact: makesContact)
    }

    static func slot(_ p: PKMNStats, ability: String, moves: [MoveData]) -> TeamSlotInfo {
        TeamSlotInfo(
            spreadName: "fx-\(p.name)",
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

    static func engine(_ a: (PKMNStats, String, [MoveData]),
                       _ b: (PKMNStats, String, [MoveData])) -> BattleEngine {
        let sA = slot(a.0, ability: a.1, moves: a.2)
        let sB = slot(b.0, ability: b.1, moves: b.2)
        let allP = [a.0, b.0]
        let allM = a.2 + b.2
        let bs1 = BattleSide(label: "Side 1", slots: [sA], format: .singles,
                             allPokemon: allP, allMoves: allM)
        let bs2 = BattleSide(label: "Side 2", slots: [sB], format: .singles,
                             allPokemon: allP, allMoves: allM)
        return BattleEngine(format: .singles, side1: bs1, side2: bs2,
                            allPokemon: allP, allMoves: allM)
    }
}

@MainActor
@Suite("Tier 6 — Mold Breaker & Unaware")
struct BattleTier6CoreTests {

    @Test func moldBreakerBypassesLevitate() {
        // A Levitate user normally takes 0 damage from Ground moves. A Mold
        // Breaker attacker bypasses that immunity.
        let a = T6.pkmn("Excadrill", id: 100, ability: "mold-breaker")
        let b = T6.pkmn("Flygon", id: 101, type1: "Ground", type2: "Dragon",
                        ability: "levitate", hp: 300)
        let quake = T6.mv("Earthquake", id: 1, type: "Ground", dmg: "physical",
                          power: 100, makesContact: false)
        let e = T6.engine((a, "mold-breaker", [quake]), (b, "levitate", [quake]))
        let B = e.side2.active(at: 0)!
        let before = B.currentHP
        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e.executeTurn()
        #expect(B.currentHP < before, "Mold Breaker should bypass Levitate")
    }

    @Test func levitateBlocksWithoutMoldBreaker() {
        // Sanity check — Levitate should still block when attacker has a
        // different ability.
        let a = T6.pkmn("Excadrill", id: 100, ability: "blaze")
        let b = T6.pkmn("Flygon", id: 101, type1: "Ground", type2: "Dragon",
                        ability: "levitate", hp: 300)
        let quake = T6.mv("Earthquake", id: 1, type: "Ground", dmg: "physical",
                          power: 100, makesContact: false)
        let e = T6.engine((a, "blaze", [quake]), (b, "levitate", [quake]))
        let B = e.side2.active(at: 0)!
        let before = B.currentHP
        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e.executeTurn()
        #expect(B.currentHP == before, "Levitate should still block Earthquake from non-Mold-Breakers")
    }

    @Test func unawareIgnoresOpposingBoosts() {
        // Defender with Unaware should ignore attacker's +6 Atk boost. Run two
        // engines: one with Unaware defender, one with regular — the boosted
        // attack should hit the regular defender harder.
        let a = T6.pkmn("Atk", id: 100, atk: 200)
        let b1 = T6.pkmn("Calm", id: 101, ability: "unaware", hp: 300)
        let b2 = T6.pkmn("Calm", id: 102, ability: "blaze", hp: 300)
        let tackle = T6.mv("Tackle", id: 1, dmg: "physical", power: 60, makesContact: true)
        let e1 = T6.engine((a, "blaze", [tackle]), (b1, "unaware", [tackle]))
        let e2 = T6.engine((a, "blaze", [tackle]), (b2, "blaze", [tackle]))
        // Pump up attacker's Atk on both copies.
        e1.side1.active(at: 0)!.atkStage = 6
        e2.side1.active(at: 0)!.atkStage = 6
        e1.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e2.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e1.executeTurn()
        e2.executeTurn()
        let unawareDmg = e1.side2.active(at: 0)!.maxHP - e1.side2.active(at: 0)!.currentHP
        let normalDmg = e2.side2.active(at: 0)!.maxHP - e2.side2.active(at: 0)!.currentHP
        #expect(normalDmg > unawareDmg * 2,
                "Unaware should make the boosted attack much less effective")
    }
}

@MainActor
@Suite("Tier 6 — Moody")
struct BattleTier6MoodyTests {

    @Test func moodyShiftsStatsEachEOT() {
        let a = T6.pkmn("Bibarel", id: 100, ability: "moody")
        let b = T6.pkmn("Other", id: 101)
        let splash = T6.mv("Splash", id: 1, dmg: "status", power: nil)
        let e = T6.engine((a, "moody", [splash]), (b, "blaze", [splash]))
        let A = e.side1.active(at: 0)!
        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 0, targetSlot: 0))
        e.executeTurn()
        // After one EOT, exactly one stat should be +2 and exactly one should be -1.
        let stages = [A.atkStage, A.defStage, A.spAtkStage, A.spDefStage, A.speedStage]
        let plusTwo = stages.filter { $0 == 2 }.count
        let minusOne = stages.filter { $0 == -1 }.count
        #expect(plusTwo == 1 && minusOne == 1,
                "Moody should raise exactly one stat by 2 and lower a different one by 1")
    }
}

@MainActor
@Suite("Tier 6 — Cute Charm & Infatuation")
struct BattleTier6CuteCharmTests {

    @Test func cuteCharmEventuallyInfatuates() {
        var any = false
        for _ in 0..<50 {
            let a = T6.pkmn("Atk", id: 100)
            let b = T6.pkmn("Def", id: 101, ability: "cute-charm")
            let tackle = T6.mv("Tackle", id: 1, dmg: "physical", power: 40, makesContact: true)
            let e = T6.engine((a, "blaze", [tackle]), (b, "cute-charm", [tackle]))
            e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
            e.executeTurn()
            if e.side1.active(at: 0)?.infatuated == true { any = true; break }
        }
        #expect(any, "Cute Charm should infatuate the contact attacker eventually (30% per hit)")
    }

    @Test func infatuatedHolderSometimesFizzles() {
        // Set infatuated directly and run many turns — at least one turn should
        // fizzle (50% chance per move).
        let a = T6.pkmn("Atk", id: 100)
        let b = T6.pkmn("Def", id: 101, hp: 300)
        let tackle = T6.mv("Tackle", id: 1, dmg: "physical", power: 40, makesContact: true)
        let e = T6.engine((a, "blaze", [tackle]), (b, "blaze", [tackle]))
        e.side1.active(at: 0)!.infatuated = true
        var fizzles = 0
        for _ in 0..<30 {
            let logBefore = e.log.count
            e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
            e.executeTurn()
            if e.log[logBefore...].map(\.text).contains(where: { $0.contains("immobilized by love") }) {
                fizzles += 1
            }
        }
        #expect(fizzles > 0, "An infatuated holder should fizzle on at least one turn over 30 trials")
    }
}

@MainActor
@Suite("Tier 6 — Battle Bond")
struct BattleTier6BattleBondTests {

    @Test func battleBondBoostsSpAtkOnKO() {
        let a = T6.pkmn("Greninja", id: 100, ability: "battle-bond", spa: 200)
        let b = T6.pkmn("Frail", id: 101, hp: 20)
        let pulse = T6.mv("Water Pulse", id: 1, type: "Water", dmg: "special",
                          power: 200, makesContact: false)
        let e = T6.engine((a, "battle-bond", [pulse]), (b, "blaze", [pulse]))
        let A = e.side1.active(at: 0)!
        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e.executeTurn()
        #expect(e.side2.active(at: 0)?.fainted == true)
        #expect(A.battleBondTriggered)
        #expect(A.spAtkStage == 1, "Battle Bond should boost SpA on KO")
    }
}

@MainActor
@Suite("Tier 6 — Imposter")
struct BattleTier6ImposterTests {

    @Test func imposterCopiesOpponentStatsOnEntry() {
        // The slot-0 opponent has a unique Atk stat the imposter should copy.
        let a = T6.pkmn("Ditto", id: 100, ability: "imposter", atk: 30)
        let b = T6.pkmn("Buff", id: 101, ability: "blaze", atk: 250, def: 250)
        let tackle = T6.mv("Tackle", id: 1, dmg: "physical", power: 40, makesContact: true)
        let e = T6.engine((a, "imposter", [tackle]), (b, "blaze", [tackle]))
        let A = e.side1.active(at: 0)!
        #expect(A.imposterSnapshot != nil)
        #expect(A.baseAtk == 250, "Imposter should mirror the opponent's Atk")
        #expect(A.displayName.contains("Buff"),
                "Imposter display name should reference the copied target")
    }

    @Test func imposterCopiesOpponentAbility() {
        let a = T6.pkmn("Ditto", id: 100, ability: "imposter")
        let b = T6.pkmn("Charizard", id: 101, type1: "Fire", ability: "blaze")
        let tackle = T6.mv("Tackle", id: 1, dmg: "physical", power: 40, makesContact: true)
        let e = T6.engine((a, "imposter", [tackle]), (b, "blaze", [tackle]))
        #expect(e.side1.active(at: 0)?.activeAbility == "blaze",
                "Imposter should expose the opponent's ability via activeAbility")
        #expect(e.side1.active(at: 0)?.activeType1 == "Fire",
                "Imposter should mirror the opponent's primary type")
    }
}

@MainActor
@Suite("Tier 6 — Zero to Hero")
struct BattleTier6ZeroToHeroTests {

    @Test func palafinFlipsToHeroOnSwitchOut() {
        let a = T6.pkmn("Palafin", id: 100, ability: "zero-to-hero")
        let bench = T6.pkmn("Bench", id: 102)
        let b = T6.pkmn("Other", id: 101)
        let tackle = T6.mv("Tackle", id: 1, dmg: "physical", power: 40, makesContact: true)
        let aSlot = T6.slot(a, ability: "zero-to-hero", moves: [tackle])
        let benchSlot = T6.slot(bench, ability: "blaze", moves: [])
        let bSlot = T6.slot(b, ability: "blaze", moves: [])
        let allP = [a, bench, b]
        let bs1 = BattleSide(label: "Side 1", slots: [aSlot, benchSlot], format: .singles,
                             allPokemon: allP, allMoves: [tackle])
        let bs2 = BattleSide(label: "Side 2", slots: [bSlot], format: .singles,
                             allPokemon: allP, allMoves: [tackle])
        let e = BattleEngine(format: .singles, side1: bs1, side2: bs2,
                             allPokemon: allP, allMoves: [tackle])
        let palafin = e.side1.active(at: 0)!
        let baseAtkBefore = palafin.baseAtk
        // Switch out — the flag should flip.
        e.setAction(side: 0, slot: 0, action: .switchTo(benchIndex: 1))
        e.executeTurn()
        #expect(palafin.palafinHeroActive,
                "Switching out should flip Zero to Hero on")
        #expect(palafin.baseAtk > baseAtkBefore,
                "Hero form's base Atk should exceed the Zero form's")
    }
}
