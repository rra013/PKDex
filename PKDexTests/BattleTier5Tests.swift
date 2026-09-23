//
//  BattleTier5Tests.swift
//  PKDexTests
//
//  Tier 5 — niche moves and abilities. OHKO, fixed-damage, damage modifiers
//  (Body Press / Foul Play / Acrobatics / Hex / Venoshock / Stored Power),
//  Counter / Mirror Coat, trap moves, status moves (Trick / Memento /
//  Belly Drum / Healing Wish / Roar / Endeavor), abilities (Cursed Body /
//  Pressure / Bulletproof / Soundproof / Pickpocket / Frisk).
//

import Testing
import Foundation
@testable import PKDex

@MainActor
private enum T5 {
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

    static func slot(_ p: PKMNStats, ability: String, moves: [MoveData],
                     item: String? = nil) -> TeamSlotInfo {
        TeamSlotInfo(
            spreadName: "fx-\(p.name)",
            pokemonID: p.id, pokemonName: p.name,
            type1: p.type1, type2: p.type2,
            abilityName: ability, itemRawValue: item,
            championsMode: false, natureID: "hardy", level: 50,
            evHP: 0, evAtk: 0, evDef: 0, evSpAtk: 0, evSpDef: 0, evSpeed: 0,
            moveSlots: moves.map {
                TeamMoveInfo(moveID: $0.id, moveName: $0.name, moveType: $0.type,
                             damageClass: $0.damageClass, power: $0.power, isSTAB: false)
            }
        )
    }

    static func engine(_ a: (PKMNStats, String, [MoveData]),
                       _ b: (PKMNStats, String, [MoveData]),
                       itemA: String? = nil, itemB: String? = nil) -> BattleEngine {
        let sA = slot(a.0, ability: a.1, moves: a.2, item: itemA)
        let sB = slot(b.0, ability: b.1, moves: b.2, item: itemB)
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
@Suite("Tier 5 — Status Moves (Trick / Memento / Belly Drum / Healing Wish / Endeavor)")
struct BattleTier5StatusTests {

    @Test func trickSwapsItems() {
        let a = T5.pkmn("MonA", id: 100)
        let b = T5.pkmn("MonB", id: 101)
        let trick = T5.mv("Trick", id: 1, dmg: "status", power: nil, makesContact: false)
        let e = T5.engine((a, "blaze", [trick]), (b, "blaze", [trick]),
                          itemA: HeldItem.choiceBand.rawValue,
                          itemB: HeldItem.leftovers.rawValue)
        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e.executeTurn()
        #expect(e.side1.active(at: 0)?.heldItem == .leftovers)
        #expect(e.side2.active(at: 0)?.heldItem == .choiceBand)
    }

    @Test func mementoFaintsUserAndDropsTarget() {
        let a = T5.pkmn("MonA", id: 100, hp: 200)
        let b = T5.pkmn("MonB", id: 101)
        let memento = T5.mv("Memento", id: 1, dmg: "status", power: nil, makesContact: false)
        let e = T5.engine((a, "blaze", [memento]), (b, "blaze", [memento]))
        let A = e.side1.active(at: 0)!
        let B = e.side2.active(at: 0)!
        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e.executeTurn()
        #expect(A.fainted)
        #expect(B.atkStage == -2)
        #expect(B.spAtkStage == -2)
    }

    @Test func bellyDrumCostsHalfHPMaxesAtk() {
        let a = T5.pkmn("MonA", id: 100, hp: 200)
        let b = T5.pkmn("MonB", id: 101)
        let bd = T5.mv("Belly Drum", id: 1, dmg: "status", power: nil, makesContact: false)
        let e = T5.engine((a, "blaze", [bd]), (b, "blaze", [bd]))
        let A = e.side1.active(at: 0)!
        let costExpected = max(1, A.maxHP / 2)
        let hpBefore = A.currentHP
        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 0, targetSlot: 0))
        e.executeTurn()
        #expect(A.atkStage == 6)
        #expect(A.currentHP == hpBefore - costExpected)
    }

    @Test func endeavorEqualizesHPDownward() {
        let a = T5.pkmn("MonA", id: 100, hp: 200)
        let b = T5.pkmn("MonB", id: 101, hp: 200)
        let endeavor = T5.mv("Endeavor", id: 1, dmg: "status", power: nil, makesContact: false)
        let e = T5.engine((a, "blaze", [endeavor]), (b, "blaze", [endeavor]))
        let A = e.side1.active(at: 0)!
        let B = e.side2.active(at: 0)!
        A.currentHP = 10
        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e.executeTurn()
        #expect(B.currentHP == 10, "Endeavor should drop target HP down to match user HP")
    }

    @Test func healingWishRevivesIncomingMon() {
        let a = T5.pkmn("MonA", id: 100, hp: 200)
        let bench = T5.pkmn("Bench", id: 102)
        let b = T5.pkmn("MonB", id: 101)
        let hw = T5.mv("Healing Wish", id: 1, dmg: "status", power: nil, makesContact: false)
        let aSlot = T5.slot(a, ability: "blaze", moves: [hw])
        let benchSlot = T5.slot(bench, ability: "blaze", moves: [])
        let bSlot = T5.slot(b, ability: "blaze", moves: [])
        let allP = [a, bench, b]
        let bs1 = BattleSide(label: "Side 1", slots: [aSlot, benchSlot], format: .singles,
                             allPokemon: allP, allMoves: [hw])
        let bs2 = BattleSide(label: "Side 2", slots: [bSlot], format: .singles,
                             allPokemon: allP, allMoves: [hw])
        let e = BattleEngine(format: .singles, side1: bs1, side2: bs2,
                             allPokemon: allP, allMoves: [hw])
        // Damage bench mon so we can verify it gets healed on switch.
        e.side1.participants[1].currentHP = e.side1.participants[1].maxHP / 4
        e.side1.participants[1].status = .burn
        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 0, targetSlot: 0))
        e.executeTurn()
        // After Healing Wish: user faints, slot 0 needs a force-switch.
        e.forceSwitch(side: 0, slot: 0, benchIndex: 1)
        let incoming = e.side1.active(at: 0)!
        #expect(incoming.currentHP == incoming.maxHP)
        #expect(incoming.status == .none)
    }
}

@MainActor
@Suite("Tier 5 — Fixed Damage + Counter/Mirror Coat")
struct BattleTier5FixedDamageTests {

    @Test func seismicTossDealsLevelDamage() {
        let a = T5.pkmn("MonA", id: 100)
        let b = T5.pkmn("MonB", id: 101, hp: 200)
        let st = T5.mv("Seismic Toss", id: 1, type: "Fighting", dmg: "physical",
                        power: 1, makesContact: true)
        let e = T5.engine((a, "blaze", [st]), (b, "blaze", [st]))
        let B = e.side2.active(at: 0)!
        let bHPBefore = B.currentHP
        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e.executeTurn()
        #expect(bHPBefore - B.currentHP == 50,
                "Seismic Toss should deal exactly level (50) damage")
    }

    @Test func superFangHalvesTargetHP() {
        let a = T5.pkmn("MonA", id: 100)
        let b = T5.pkmn("MonB", id: 101, hp: 200)
        let sf = T5.mv("Super Fang", id: 1, dmg: "physical", power: 1, makesContact: true)
        let e = T5.engine((a, "blaze", [sf]), (b, "blaze", [sf]))
        let B = e.side2.active(at: 0)!
        let bHPBefore = B.currentHP
        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e.executeTurn()
        let dealt = bHPBefore - B.currentHP
        // Implementation uses max(1, currentHP / 2). Allow the off-by-one from
        // integer-vs-rounding so this is robust to the calc-formula version.
        #expect(abs(dealt - bHPBefore / 2) <= 1,
                "Super Fang halves the target's current HP (±1)")
    }

    @Test func dragonRageDealsForty() {
        let a = T5.pkmn("MonA", id: 100)
        let b = T5.pkmn("MonB", id: 101, hp: 200)
        let dr = T5.mv("Dragon Rage", id: 1, type: "Dragon", dmg: "special",
                       power: 1, makesContact: false)
        let e = T5.engine((a, "blaze", [dr]), (b, "blaze", [dr]))
        let B = e.side2.active(at: 0)!
        let before = B.currentHP
        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e.executeTurn()
        #expect(before - B.currentHP == 40)
    }

    @Test func finalGambitFaintsUserDealsHPDamage() {
        let a = T5.pkmn("MonA", id: 100, hp: 200)
        let b = T5.pkmn("MonB", id: 101, hp: 200)
        let fg = T5.mv("Final Gambit", id: 1, type: "Fighting", dmg: "special",
                       power: 1, makesContact: false)
        let e = T5.engine((a, "blaze", [fg]), (b, "blaze", [fg]))
        let A = e.side1.active(at: 0)!
        let B = e.side2.active(at: 0)!
        A.currentHP = 50
        let bBefore = B.currentHP
        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e.executeTurn()
        #expect(A.fainted)
        #expect(bBefore - B.currentHP == 50, "Final Gambit deals damage = user's pre-hit HP")
    }

    @Test func counterReturnsPhysicalDoubled() {
        // B (slow) uses Tackle and takes nothing in return. A (fast) uses
        // Counter — but it's used by the one who got hit. Reorder: A is slower,
        // takes Tackle first, then uses Counter.
        let a = T5.pkmn("MonA", id: 100, hp: 300, spe: 50)
        let b = T5.pkmn("MonB", id: 101, hp: 200, atk: 200, spe: 200)
        let counter = T5.mv("Counter", id: 1, type: "Fighting", dmg: "physical",
                            power: 1, priority: -5, makesContact: true)
        let tackle = T5.mv("Tackle", id: 2, dmg: "physical", power: 60, makesContact: true)
        let e = T5.engine((a, "blaze", [counter]), (b, "blaze", [tackle]))
        let A = e.side1.active(at: 0)!
        let B = e.side2.active(at: 0)!
        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e.setAction(side: 1, slot: 0, action: .move(moveIndex: 0, targetSide: 0, targetSlot: 0))
        e.executeTurn()
        let aLoss = A.maxHP - A.currentHP
        let bLoss = B.maxHP - B.currentHP
        #expect(aLoss > 0, "A should have taken some damage from Tackle")
        #expect(bLoss == aLoss * 2, "Counter returns 2x the physical damage")
    }
}

@MainActor
@Suite("Tier 5 — Damage Modifiers")
struct BattleTier5DamageModTests {

    @Test func bodyPressUsesDefStat() {
        // Body Press scales by Def/Atk ratio. With Def 200 vs Atk 50, damage
        // should be ~4x what a same-power Atk move would deal.
        let a = T5.pkmn("MonA", id: 100, atk: 50, def: 200)
        let b = T5.pkmn("MonB", id: 101, hp: 300)
        let bp = T5.mv("Body Press", id: 1, type: "Fighting", dmg: "physical",
                       power: 80, makesContact: true)
        let tackle = T5.mv("Tackle", id: 2, dmg: "physical", power: 80, makesContact: true)
        let e1 = T5.engine((a, "blaze", [bp]), (b, "blaze", [bp]))
        e1.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e1.executeTurn()
        let pressDmg = e1.side2.active(at: 0)!.maxHP - e1.side2.active(at: 0)!.currentHP
        let e2 = T5.engine((a, "blaze", [tackle]), (b, "blaze", [tackle]))
        e2.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e2.executeTurn()
        let tackleDmg = e2.side2.active(at: 0)!.maxHP - e2.side2.active(at: 0)!.currentHP
        #expect(pressDmg > tackleDmg * 2,
                "Body Press should hit notably harder than Tackle when Def >> Atk")
    }

    @Test func acrobaticsDoublesWithoutItem() {
        let a = T5.pkmn("MonA", id: 100)
        let b = T5.pkmn("MonB", id: 101, hp: 300)
        let acro = T5.mv("Acrobatics", id: 1, type: "Flying", dmg: "physical",
                         power: 55, makesContact: true)
        // No item — should get 2x.
        let e1 = T5.engine((a, "blaze", [acro]), (b, "blaze", [acro]))
        e1.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e1.executeTurn()
        let noItemDmg = e1.side2.active(at: 0)!.maxHP - e1.side2.active(at: 0)!.currentHP
        // With Leftovers — should NOT get 2x.
        let e2 = T5.engine((a, "blaze", [acro]), (b, "blaze", [acro]),
                            itemA: HeldItem.leftovers.rawValue)
        e2.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e2.executeTurn()
        let itemDmg = e2.side2.active(at: 0)!.maxHP - e2.side2.active(at: 0)!.currentHP
        #expect(noItemDmg > itemDmg, "Acrobatics with no item should hit harder than with item")
    }

    @Test func hexDoublesOnStatusedTarget() {
        let a = T5.pkmn("MonA", id: 100)
        let b = T5.pkmn("MonB", id: 101, hp: 300)
        let hex = T5.mv("Hex", id: 1, type: "Ghost", dmg: "special",
                        power: 65, makesContact: false)
        let e1 = T5.engine((a, "blaze", [hex]), (b, "blaze", [hex]))
        e1.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e1.executeTurn()
        let cleanDmg = e1.side2.active(at: 0)!.maxHP - e1.side2.active(at: 0)!.currentHP
        let e2 = T5.engine((a, "blaze", [hex]), (b, "blaze", [hex]))
        e2.side2.active(at: 0)!.status = .burn
        e2.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e2.executeTurn()
        let burnedDmg = e2.side2.active(at: 0)!.maxHP - e2.side2.active(at: 0)!.currentHP
        #expect(burnedDmg > cleanDmg, "Hex should hit harder on a statused target")
    }
}

@MainActor
@Suite("Tier 5 — OHKO Moves")
struct BattleTier5OHKOTests {

    @Test func guillotineKOsAtSameLevel() {
        // With same level, 30% base accuracy. Run trials to confirm KO is possible.
        var anyKO = false
        for _ in 0..<30 {
            let a = T5.pkmn("MonA", id: 100)
            let b = T5.pkmn("MonB", id: 101, hp: 200)
            let g = T5.mv("Guillotine", id: 1, dmg: "physical", power: 1, makesContact: true)
            let e = T5.engine((a, "blaze", [g]), (b, "blaze", [g]))
            e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
            e.executeTurn()
            if e.side2.active(at: 0)?.fainted == true { anyKO = true; break }
        }
        #expect(anyKO, "Guillotine should eventually OHKO a same-level target")
    }

    @Test func sheerColdFailsOnIceType() {
        let a = T5.pkmn("MonA", id: 100)
        let b = T5.pkmn("Glaceon", id: 101, type1: "Ice", hp: 200)
        let sc = T5.mv("Sheer Cold", id: 1, type: "Ice", dmg: "special",
                       power: 1, makesContact: false)
        let e = T5.engine((a, "blaze", [sc]), (b, "blaze", [sc]))
        let B = e.side2.active(at: 0)!
        let before = B.currentHP
        // Run a handful of trials — none should KO an Ice-type.
        for _ in 0..<10 {
            e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
            e.executeTurn()
        }
        #expect(B.currentHP == before, "Sheer Cold should never KO an Ice-type")
    }
}

@MainActor
@Suite("Tier 5 — Trap Moves")
struct BattleTier5TrapTests {

    @Test func bindAppliesTrapVolatile() {
        let a = T5.pkmn("MonA", id: 100)
        let b = T5.pkmn("MonB", id: 101, hp: 300)
        let bind = T5.mv("Bind", id: 1, dmg: "physical", power: 15, makesContact: true)
        let e = T5.engine((a, "blaze", [bind]), (b, "blaze", [bind]))
        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e.executeTurn()
        let B = e.side2.active(at: 0)!
        #expect(B.trapTurnsRemaining > 0)
        #expect(B.trapMoveName == "Bind")
    }
}

@MainActor
@Suite("Tier 5 — Abilities")
struct BattleTier5AbilityTests {

    @Test func soundproofBlocksSoundMove() {
        let a = T5.pkmn("MonA", id: 100)
        let b = T5.pkmn("MonB", id: 101, ability: "soundproof", hp: 300)
        let snarl = T5.mv("Snarl", id: 1, type: "Dark", dmg: "special",
                          power: 55, makesContact: false)
        let e = T5.engine((a, "blaze", [snarl]), (b, "soundproof", [snarl]))
        let B = e.side2.active(at: 0)!
        let before = B.currentHP
        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e.executeTurn()
        #expect(B.currentHP == before, "Soundproof should block Snarl entirely")
    }

    @Test func bulletproofBlocksBallisticMove() {
        let a = T5.pkmn("MonA", id: 100)
        let b = T5.pkmn("Chesnaught", id: 101, ability: "bulletproof", hp: 300)
        let aSphere = T5.mv("Aura Sphere", id: 1, type: "Fighting", dmg: "special",
                             power: 80, makesContact: false)
        let e = T5.engine((a, "blaze", [aSphere]), (b, "bulletproof", [aSphere]))
        let B = e.side2.active(at: 0)!
        let before = B.currentHP
        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e.executeTurn()
        #expect(B.currentHP == before, "Bulletproof should block Aura Sphere")
    }

    @Test func pressureDrainsExtraPP() {
        let a = T5.pkmn("MonA", id: 100)
        let b = T5.pkmn("MonB", id: 101, ability: "pressure")
        let tackle = T5.mv("Tackle", id: 1, dmg: "physical", power: 40, makesContact: true)
        let e = T5.engine((a, "blaze", [tackle]), (b, "pressure", [tackle]))
        let A = e.side1.active(at: 0)!
        let ppBefore = A.pp[0]
        e.setAction(side: 0, slot: 0, action: .move(moveIndex: 0, targetSide: 1, targetSlot: 0))
        e.executeTurn()
        #expect(A.pp[0] == ppBefore - 2,
                "Pressure should drain 2 PP per opposing move use")
    }

    @Test func friskLogsTargetItemOnEntry() {
        let a = T5.pkmn("MonA", id: 100, ability: "frisk")
        let b = T5.pkmn("MonB", id: 101)
        let tackle = T5.mv("Tackle", id: 1, dmg: "physical", power: 40, makesContact: true)
        let e = T5.engine((a, "frisk", [tackle]), (b, "blaze", [tackle]),
                          itemB: HeldItem.leftovers.rawValue)
        // Trigger entry — Frisk fires on initial spawn (no explicit switch).
        #expect(e.log.contains(where: { $0.text.contains("Frisk spotted") }),
                "Frisk should log the target's held item on entry")
    }
}
