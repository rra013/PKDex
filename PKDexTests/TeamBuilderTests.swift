//
//  TeamBuilderTests.swift
//  PKDexTests
//
//  Created by Rishi Anand on 4/16/26.
//

import Testing
import Foundation
@testable import PKDex

// MARK: - Type Coverage Logic

@Suite("Type Coverage Analysis")
struct TypeCoverageTests {

    // MARK: Helpers

    /// Build a minimal team slot with the given types and moves.
    private func slot(
        name: String = "TestMon",
        type1: String = "Normal",
        type2: String? = nil,
        moves: [(name: String, type: String, power: Int, damageClass: String)] = []
    ) -> TeamSlotInfo {
        let pokemonTypes = [type1] + [type2].compactMap { $0 }
        let moveSlots = moves.map { m in
            TeamMoveInfo(
                moveID: 0,
                moveName: m.name,
                moveType: m.type,
                damageClass: m.damageClass,
                power: m.power,
                isSTAB: pokemonTypes.contains(m.type)
            )
        }
        return TeamSlotInfo(
            spreadName: name,
            pokemonID: 0,
            pokemonName: name,
            type1: type1,
            type2: type2,
            moveSlots: moveSlots
        )
    }

    // MARK: Empty Team

    @Test func emptyTeamHasNoSECoverage() {
        let entries = computeTypeCoverage(slots: [])
        for entry in entries {
            #expect(!entry.isCovered, "\(entry.defenderType) should not be covered with an empty team")
            #expect(entry.stabSources.isEmpty)
            #expect(entry.nonStabSources.isEmpty)
        }
        #expect(entries.count == 18)
    }

    // MARK: Single STAB Move

    @Test func fireSTABHitsGrassIceBugSteel() {
        let team = [slot(name: "Charizard", type1: "Fire", type2: "Flying",
                         moves: [("Flamethrower", "Fire", 90, "special")])]
        let entries = computeTypeCoverage(slots: team)

        let covered = entries.filter { $0.hasSTABCoverage }.map(\.defenderType)
        #expect(covered.contains("Grass"))
        #expect(covered.contains("Ice"))
        #expect(covered.contains("Bug"))
        #expect(covered.contains("Steel"))

        // Fire should NOT be SE against Water, Fire, Rock, Dragon
        let notSE = entries.filter { !$0.isCovered }.map(\.defenderType)
        #expect(notSE.contains("Water"))
        #expect(notSE.contains("Dragon"))
    }

    @Test func stabSourceIncludesPokemonAndMoveName() {
        let team = [slot(name: "Arcanine", type1: "Fire",
                         moves: [("Flamethrower", "Fire", 90, "special")])]
        let entries = computeTypeCoverage(slots: team)
        let grassEntry = entries.first(where: { $0.defenderType == "Grass" })!

        #expect(grassEntry.stabSources.count == 1)
        #expect(grassEntry.stabSources[0].pokemonName == "Arcanine")
        #expect(grassEntry.stabSources[0].moveName == "Flamethrower")
        #expect(grassEntry.stabSources[0].moveType == "Fire")
        #expect(grassEntry.stabSources[0].isSTAB == true)
    }

    // MARK: Non-STAB Coverage

    @Test func nonSTABMoveShowsAsNonSTAB() {
        // Water mon using Ice Beam (not STAB)
        let team = [slot(name: "Vaporeon", type1: "Water",
                         moves: [("Ice Beam", "Ice", 90, "special")])]
        let entries = computeTypeCoverage(slots: team)

        let grassEntry = entries.first(where: { $0.defenderType == "Grass" })!
        #expect(grassEntry.stabSources.isEmpty, "Ice on a Water mon is not STAB")
        #expect(grassEntry.nonStabSources.count == 1)
        #expect(grassEntry.nonStabSources[0].pokemonName == "Vaporeon")
        #expect(grassEntry.nonStabSources[0].isSTAB == false)
    }

    // MARK: STAB vs Non-STAB Separation

    @Test func sameTypeCoveredByBothSTABAndNonSTAB() {
        // Grass is hit SE by both Fire (STAB from Charizard) and Ice (non-STAB from Vaporeon)
        let team = [
            slot(name: "Charizard", type1: "Fire", type2: "Flying",
                 moves: [("Flamethrower", "Fire", 90, "special")]),
            slot(name: "Vaporeon", type1: "Water",
                 moves: [("Ice Beam", "Ice", 90, "special")])
        ]
        let entries = computeTypeCoverage(slots: team)
        let grassEntry = entries.first(where: { $0.defenderType == "Grass" })!

        #expect(grassEntry.hasSTABCoverage)
        #expect(grassEntry.stabSources.count == 1)
        #expect(grassEntry.stabSources[0].pokemonName == "Charizard")
        #expect(grassEntry.nonStabSources.count == 1)
        #expect(grassEntry.nonStabSources[0].pokemonName == "Vaporeon")
    }

    // MARK: Multiple Pokemon Covering Same Type

    @Test func multiplePokemonCanCoverSameType() {
        let team = [
            slot(name: "Arcanine", type1: "Fire",
                 moves: [("Flamethrower", "Fire", 90, "special")]),
            slot(name: "Charizard", type1: "Fire", type2: "Flying",
                 moves: [("Fire Blast", "Fire", 110, "special")])
        ]
        let entries = computeTypeCoverage(slots: team)
        let grassEntry = entries.first(where: { $0.defenderType == "Grass" })!

        #expect(grassEntry.stabSources.count == 2)
        let names = grassEntry.stabSources.map(\.pokemonName)
        #expect(names.contains("Arcanine"))
        #expect(names.contains("Charizard"))
    }

    // MARK: Status Moves Ignored

    @Test func statusMovesDoNotCountAsCoverage() {
        let team = [slot(name: "Gengar", type1: "Ghost", type2: "Poison",
                         moves: [("Will-O-Wisp", "Fire", 0, "status")])]
        let entries = computeTypeCoverage(slots: team)
        let grassEntry = entries.first(where: { $0.defenderType == "Grass" })!
        #expect(!grassEntry.isCovered, "Status moves should not provide coverage")
    }

    @Test func zeroPowerMovesDoNotCountAsCoverage() {
        let team = [slot(name: "Gengar", type1: "Ghost", type2: "Poison",
                         moves: [("Toxic", "Poison", 0, "status")])]
        let entries = computeTypeCoverage(slots: team)
        for entry in entries {
            #expect(!entry.isCovered, "\(entry.defenderType) should not be covered by a zero-power move")
        }
    }

    // MARK: Full Coverage

    @Test func diverseTeamCanAchieveFullCoverage() {
        // Build a team that covers all 18 types SE
        let team = [
            slot(name: "Mon1", type1: "Fire", moves: [
                ("Fire Move", "Fire", 90, "special"),      // SE: Grass, Ice, Bug, Steel
                ("Ground Move", "Ground", 90, "physical")  // SE: Fire, Electric, Poison, Rock, Steel
            ]),
            slot(name: "Mon2", type1: "Water", moves: [
                ("Water Move", "Water", 90, "special"),    // SE: Fire, Ground, Rock
                ("Ice Move", "Ice", 90, "special")         // SE: Grass, Ground, Flying, Dragon
            ]),
            slot(name: "Mon3", type1: "Fighting", moves: [
                ("Fight Move", "Fighting", 90, "physical"), // SE: Normal, Ice, Rock, Dark, Steel
                ("Rock Move", "Rock", 90, "physical")       // SE: Fire, Ice, Flying, Bug
            ]),
            slot(name: "Mon4", type1: "Ghost", moves: [
                ("Ghost Move", "Ghost", 90, "special"),     // SE: Psychic, Ghost
                ("Dark Move", "Dark", 90, "physical")       // SE: Psychic, Ghost
            ]),
            slot(name: "Mon5", type1: "Fairy", moves: [
                ("Fairy Move", "Fairy", 90, "special"),     // SE: Fighting, Dragon, Dark
                ("Poison Move", "Poison", 90, "special")    // SE: Grass, Fairy
            ]),
            slot(name: "Mon6", type1: "Electric", moves: [
                ("Electric Move", "Electric", 90, "special") // SE: Water, Flying
            ])
        ]

        let entries = computeTypeCoverage(slots: team)
        let uncovered = entries.filter { !$0.isCovered }

        // Verify we cover the tricky types
        let coveredTypes = Set(entries.filter { $0.isCovered }.map(\.defenderType))
        #expect(coveredTypes.contains("Normal"),   "Normal should be covered by Fighting")
        #expect(coveredTypes.contains("Dragon"),   "Dragon should be covered by Ice or Fairy")
        #expect(coveredTypes.contains("Psychic"),  "Psychic should be covered by Ghost or Dark")
        #expect(coveredTypes.contains("Water"),    "Water should be covered by Electric")
        #expect(coveredTypes.contains("Flying"),   "Flying should be covered by Rock, Ice, or Electric")

        // Check for full coverage
        // Note: this specific team may not cover all 18 perfectly (e.g., Water type),
        // but the key SE matchups should hold
        for type in uncovered {
            // Just report which types aren't covered — this validates the algorithm works
            #expect(Bool(false), "Uncovered type: \(type.defenderType) — team may need adjustment")
        }
    }

    // MARK: All 18 Types Returned

    @Test func coverageReturnsAll18Types() {
        let entries = computeTypeCoverage(slots: [])
        let types = entries.map(\.defenderType)
        #expect(types.count == 18)
        for t in allTypes {
            #expect(types.contains(t), "Missing type: \(t)")
        }
    }

    // MARK: Dual-Type STAB

    @Test func dualTypeMonGetsBothSTABs() {
        // Fire/Flying mon using both Fire and Flying moves — both should be STAB
        let team = [slot(name: "Charizard", type1: "Fire", type2: "Flying",
                         moves: [
                            ("Flamethrower", "Fire", 90, "special"),
                            ("Air Slash", "Flying", 75, "special")
                         ])]
        let entries = computeTypeCoverage(slots: team)

        // Fire STAB SE targets: Grass, Ice, Bug, Steel
        // Flying STAB SE targets: Grass, Fighting, Bug
        // Both Fire and Flying are SE against Grass, so Grass gets 2 STAB sources
        let grassEntry = entries.first(where: { $0.defenderType == "Grass" })!
        #expect(grassEntry.stabSources.count == 2)
        let grassStabMoves = grassEntry.stabSources.map(\.moveName)
        #expect(grassStabMoves.contains("Flamethrower"))
        #expect(grassStabMoves.contains("Air Slash"))

        // Only Flying is SE against Fighting (not Fire)
        let fightingEntry = entries.first(where: { $0.defenderType == "Fighting" })!
        #expect(fightingEntry.stabSources.count == 1)
        #expect(fightingEntry.stabSources[0].moveName == "Air Slash")
    }

    // MARK: Normal Type Has No SE

    @Test func normalMoveHitsNothingSuperEffective() {
        let team = [slot(name: "Snorlax", type1: "Normal",
                         moves: [("Body Slam", "Normal", 85, "physical")])]
        let entries = computeTypeCoverage(slots: team)
        for entry in entries {
            #expect(entry.stabSources.isEmpty, "Normal should not be SE against \(entry.defenderType)")
            #expect(entry.nonStabSources.isEmpty, "Normal should not be SE against \(entry.defenderType)")
        }
    }
}

// MARK: - TeamSlotInfo Creation

@Suite("TeamSlotInfo")
struct TeamSlotInfoTests {

    @Test func createsSlotFromSpreadWithResolvedMoves() {
        let spread = SavedSpread(
            name: "Test Spread",
            pokemonID: 6, pokemonName: "Charizard",
            abilityName: "blaze", itemRawValue: "Choice Specs",
            championsMode: false, natureID: "timid", level: 50,
            evHP: 0, evAtk: 0, evDef: 0, evSpAtk: 252, evSpDef: 4, evSpeed: 252,
            moveID1: 53, moveID2: 394, moveID3: nil, moveID4: nil
        )

        let pokemon = PKMNStats(
            id: 6, speciesID: 6, name: "Charizard",
            type1: "Fire", type2: "Flying",
            baseHP: 78, baseAtk: 84, baseDef: 78,
            baseSpAtk: 109, baseSpDef: 85, baseSpeed: 100
        )

        let moves = [
            MoveData(id: 53, name: "Flamethrower", type: "Fire", damageClass: "special", power: 90),
            MoveData(id: 394, name: "Air Slash", type: "Flying", damageClass: "special", power: 75)
        ]

        let slot = TeamSlotInfo.from(spread: spread, pokemon: pokemon, moves: moves)

        #expect(slot != nil)
        let s = slot!
        #expect(s.pokemonName == "Charizard")
        #expect(s.pokemonID == 6)
        #expect(s.type1 == "Fire")
        #expect(s.type2 == "Flying")
        #expect(s.abilityName == "blaze")
        #expect(s.itemRawValue == "Choice Specs")
        #expect(s.championsMode == false)
        #expect(s.natureID == "timid")
        #expect(s.evSpAtk == 252)
        #expect(s.evSpeed == 252)
        #expect(s.moveSlots.count == 2)

        // Flamethrower is Fire on a Fire/Flying mon — should be STAB
        #expect(s.moveSlots[0].moveName == "Flamethrower")
        #expect(s.moveSlots[0].moveType == "Fire")
        #expect(s.moveSlots[0].isSTAB == true)

        // Air Slash is Flying on a Fire/Flying mon — also STAB
        #expect(s.moveSlots[1].moveName == "Air Slash")
        #expect(s.moveSlots[1].moveType == "Flying")
        #expect(s.moveSlots[1].isSTAB == true)
    }

    @Test func returnsNilWhenPokemonIsNil() {
        let spread = SavedSpread(name: "Empty", pokemonID: 999)
        let slot = TeamSlotInfo.from(spread: spread, pokemon: nil, moves: [])
        #expect(slot == nil)
    }

    @Test func nonSTABMoveMarkedCorrectly() {
        let spread = SavedSpread(name: "Vaporeon", pokemonID: 134, pokemonName: "Vaporeon",
                                 moveID1: 58)
        let pokemon = PKMNStats(id: 134, speciesID: 134, name: "Vaporeon",
                                type1: "Water",
                                baseHP: 130, baseAtk: 65, baseDef: 60,
                                baseSpAtk: 110, baseSpDef: 95, baseSpeed: 65)
        let moves = [MoveData(id: 58, name: "Ice Beam", type: "Ice", damageClass: "special", power: 90)]

        let slot = TeamSlotInfo.from(spread: spread, pokemon: pokemon, moves: moves)!
        #expect(slot.moveSlots[0].isSTAB == false, "Ice Beam is not STAB on a Water mon")
    }

    @Test func unresolvableMoveIDsAreSkipped() {
        let spread = SavedSpread(name: "Test", pokemonID: 1, pokemonName: "Bulbasaur",
                                 moveID1: 999, moveID2: 998)
        let pokemon = PKMNStats(id: 1, speciesID: 1, name: "Bulbasaur",
                                type1: "Grass", type2: "Poison",
                                baseHP: 45, baseAtk: 49, baseDef: 49,
                                baseSpAtk: 65, baseSpDef: 65, baseSpeed: 45)

        let slot = TeamSlotInfo.from(spread: spread, pokemon: pokemon, moves: [])!
        #expect(slot.moveSlots.isEmpty, "Unresolvable move IDs should be skipped")
    }
}

// MARK: - SavedTeam Serialization

@Suite("SavedTeam Serialization")
struct SavedTeamSerializationTests {

    @Test func emptyTeamRoundTrips() {
        let team = SavedTeam(name: "Empty", slots: [])
        #expect(team.name == "Empty")
        #expect(team.slots.isEmpty)
    }

    @Test func slotsRoundTripThroughJSON() {
        let moveInfo = TeamMoveInfo(moveID: 53, moveName: "Flamethrower", moveType: "Fire",
                                    damageClass: "special", power: 90, isSTAB: true)
        let slotInfo = TeamSlotInfo(
            spreadName: "Charizard Spec",
            pokemonID: 6, pokemonName: "Charizard",
            type1: "Fire", type2: "Flying",
            abilityName: "blaze",
            itemRawValue: "Choice Specs",
            championsMode: true,
            natureID: "timid",
            level: 50,
            evHP: 0, evAtk: 0, evDef: 0,
            evSpAtk: 32, evSpDef: 0, evSpeed: 32,
            moveSlots: [moveInfo]
        )

        let team = SavedTeam(name: "Test Team", slots: [slotInfo])
        let decoded = team.slots

        #expect(decoded.count == 1)
        let s = decoded[0]
        #expect(s.pokemonName == "Charizard")
        #expect(s.type1 == "Fire")
        #expect(s.type2 == "Flying")
        #expect(s.abilityName == "blaze")
        #expect(s.itemRawValue == "Choice Specs")
        #expect(s.championsMode == true)
        #expect(s.natureID == "timid")
        #expect(s.evSpAtk == 32)
        #expect(s.evSpeed == 32)
        #expect(s.moveSlots.count == 1)
        #expect(s.moveSlots[0].moveName == "Flamethrower")
        #expect(s.moveSlots[0].isSTAB == true)
    }

    @Test func sixSlotTeamRoundTrips() {
        let slots = (1...6).map { i in
            TeamSlotInfo(
                spreadName: "Mon \(i)",
                pokemonID: i, pokemonName: "Pokemon\(i)",
                type1: allTypes[i - 1],
                moveSlots: []
            )
        }
        let team = SavedTeam(name: "Full Team", slots: slots)
        let decoded = team.slots

        #expect(decoded.count == 6)
        for (i, slot) in decoded.enumerated() {
            #expect(slot.pokemonName == "Pokemon\(i + 1)")
            #expect(slot.type1 == allTypes[i])
        }
    }

    @Test func settingSlotsUpdatesJSON() {
        let team = SavedTeam(name: "Mutable", slots: [])
        #expect(team.slots.isEmpty)

        let newSlot = TeamSlotInfo(
            spreadName: "Added",
            pokemonID: 25, pokemonName: "Pikachu",
            type1: "Electric",
            moveSlots: []
        )
        team.slots = [newSlot]

        #expect(team.slots.count == 1)
        #expect(team.slots[0].pokemonName == "Pikachu")
    }
}

// MARK: - Type Coverage Edge Cases

@Suite("Coverage Edge Cases")
struct CoverageEdgeCaseTests {

    private func slot(
        name: String, type1: String, type2: String? = nil,
        moves: [(String, String, Int, String)]
    ) -> TeamSlotInfo {
        let pokemonTypes = [type1] + [type2].compactMap { $0 }
        return TeamSlotInfo(
            spreadName: name, pokemonID: 0, pokemonName: name,
            type1: type1, type2: type2,
            moveSlots: moves.map { m in
                TeamMoveInfo(moveID: 0, moveName: m.0, moveType: m.1,
                             damageClass: m.3, power: m.2,
                             isSTAB: pokemonTypes.contains(m.1))
            }
        )
    }

    @Test func groundDoesNotCoverFlying() {
        let team = [slot(name: "Garchomp", type1: "Dragon", type2: "Ground",
                         moves: [("Earthquake", "Ground", 100, "physical")])]
        let entries = computeTypeCoverage(slots: team)
        let flyingEntry = entries.first(where: { $0.defenderType == "Flying" })!
        #expect(!flyingEntry.isCovered, "Ground is immune against Flying, not SE")
    }

    @Test func dragonDoesNotCoverFairy() {
        let team = [slot(name: "Dragonite", type1: "Dragon", type2: "Flying",
                         moves: [("Dragon Claw", "Dragon", 80, "physical")])]
        let entries = computeTypeCoverage(slots: team)
        let fairyEntry = entries.first(where: { $0.defenderType == "Fairy" })!
        #expect(!fairyEntry.isCovered, "Dragon is immune against Fairy, not SE")
    }

    @Test func poisonCoversGrassAndFairy() {
        let team = [slot(name: "Gengar", type1: "Ghost", type2: "Poison",
                         moves: [("Sludge Bomb", "Poison", 90, "special")])]
        let entries = computeTypeCoverage(slots: team)

        let grassEntry = entries.first(where: { $0.defenderType == "Grass" })!
        #expect(grassEntry.isCovered)
        #expect(grassEntry.stabSources.count == 1, "Poison is STAB on Ghost/Poison")

        let fairyEntry = entries.first(where: { $0.defenderType == "Fairy" })!
        #expect(fairyEntry.isCovered)
    }

    @Test func iceCoversGroundFlyingGrassDragon() {
        let team = [slot(name: "Weavile", type1: "Dark", type2: "Ice",
                         moves: [("Ice Punch", "Ice", 75, "physical")])]
        let entries = computeTypeCoverage(slots: team)

        for targetType in ["Grass", "Ground", "Flying", "Dragon"] {
            let entry = entries.first(where: { $0.defenderType == targetType })!
            #expect(entry.isCovered, "Ice should be SE against \(targetType)")
            #expect(entry.stabSources.count == 1, "Ice Punch should be STAB on Dark/Ice")
        }
    }

    @Test func fightingDoesNotCoverPoisonFlyingPsychicBugFairy() {
        let team = [slot(name: "Lucario", type1: "Fighting", type2: "Steel",
                         moves: [("Close Combat", "Fighting", 120, "physical")])]
        let entries = computeTypeCoverage(slots: team)

        for resistType in ["Poison", "Flying", "Psychic", "Bug", "Fairy"] {
            let entry = entries.first(where: { $0.defenderType == resistType })!
            #expect(!entry.isCovered, "Fighting should not be SE against \(resistType)")
        }
    }

    @Test func fightingCoversCoveredTypes() {
        let team = [slot(name: "Lucario", type1: "Fighting", type2: "Steel",
                         moves: [("Close Combat", "Fighting", 120, "physical")])]
        let entries = computeTypeCoverage(slots: team)

        for seType in ["Normal", "Ice", "Rock", "Dark", "Steel"] {
            let entry = entries.first(where: { $0.defenderType == seType })!
            #expect(entry.isCovered, "Fighting should be SE against \(seType)")
        }
    }
}
