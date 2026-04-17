//
//  LearnsetInheritanceTests.swift
//  PKDexTests
//

import Testing
@testable import PKDex

@Suite("Learnset Inheritance (Egg Moves)")
struct LearnsetInheritanceTests {

    // MARK: - Basic Inheritance

    @Test func baseFormKeepsOwnMoves() {
        // Sneasel (base) has moves [1, 2, 3] and no pre-evo
        let entries = [
            SpeciesLearnsetEntry(speciesID: 215, moveIDs: [1, 2, 3], evolvesFromSpeciesID: nil)
        ]
        let result = inheritLearnsets(entries)
        #expect(result[215] == Set([1, 2, 3]))
    }

    @Test func singleStageEvolutionInheritsPreEvoMoves() {
        // Sneasel has egg move Fake Out (252), Sneasler evolves from Sneasel
        let entries = [
            SpeciesLearnsetEntry(speciesID: 215, moveIDs: [10, 20, 252], evolvesFromSpeciesID: nil),
            SpeciesLearnsetEntry(speciesID: 903, moveIDs: [30, 40], evolvesFromSpeciesID: 215)
        ]
        let result = inheritLearnsets(entries)

        // Sneasler should have its own moves + Sneasel's moves (including Fake Out)
        #expect(result[903]!.contains(252), "Sneasler should inherit Fake Out from Sneasel")
        #expect(result[903]!.contains(30), "Sneasler keeps its own moves")
        #expect(result[903]!.contains(40), "Sneasler keeps its own moves")
        #expect(result[903]!.contains(10), "Sneasler inherits Sneasel move 10")
        #expect(result[903]!.contains(20), "Sneasler inherits Sneasel move 20")
        #expect(result[903]! == Set([10, 20, 30, 40, 252]))

        // Sneasel itself is unchanged
        #expect(result[215] == Set([10, 20, 252]))
    }

    @Test func threeStageChainInheritsFromAllPreEvos() {
        // Charmander -> Charmeleon -> Charizard
        let entries = [
            SpeciesLearnsetEntry(speciesID: 4, moveIDs: [1, 2, 100], evolvesFromSpeciesID: nil),       // Charmander (egg move 100)
            SpeciesLearnsetEntry(speciesID: 5, moveIDs: [3, 4], evolvesFromSpeciesID: 4),               // Charmeleon
            SpeciesLearnsetEntry(speciesID: 6, moveIDs: [5, 6], evolvesFromSpeciesID: 5)                // Charizard
        ]
        let result = inheritLearnsets(entries)

        // Charizard should have all moves from the chain
        #expect(result[6]! == Set([1, 2, 3, 4, 5, 6, 100]))

        // Charmeleon inherits from Charmander
        #expect(result[5]! == Set([1, 2, 3, 4, 100]))

        // Charmander only has its own
        #expect(result[4]! == Set([1, 2, 100]))
    }

    @Test func branchedEvolutionBothInheritFromBase() {
        // Sneasel -> Weavile AND Sneasel -> Sneasler
        let entries = [
            SpeciesLearnsetEntry(speciesID: 215, moveIDs: [1, 252], evolvesFromSpeciesID: nil),   // Sneasel
            SpeciesLearnsetEntry(speciesID: 461, moveIDs: [10, 11], evolvesFromSpeciesID: 215),   // Weavile
            SpeciesLearnsetEntry(speciesID: 903, moveIDs: [20, 21], evolvesFromSpeciesID: 215)    // Sneasler
        ]
        let result = inheritLearnsets(entries)

        // Both evolutions inherit Sneasel's egg move
        #expect(result[461]!.contains(252), "Weavile inherits Fake Out from Sneasel")
        #expect(result[903]!.contains(252), "Sneasler inherits Fake Out from Sneasel")

        // Each keeps its own moves
        #expect(result[461]! == Set([1, 10, 11, 252]))
        #expect(result[903]! == Set([1, 20, 21, 252]))

        // Siblings don't share moves with each other
        #expect(!result[461]!.contains(20), "Weavile should not get Sneasler's moves")
        #expect(!result[903]!.contains(10), "Sneasler should not get Weavile's moves")
    }

    // MARK: - Overlap Handling

    @Test func duplicateMovesAreDeduped() {
        // Pre-evo and evo both know the same move
        let entries = [
            SpeciesLearnsetEntry(speciesID: 1, moveIDs: [10, 20, 30], evolvesFromSpeciesID: nil),
            SpeciesLearnsetEntry(speciesID: 2, moveIDs: [20, 30, 40], evolvesFromSpeciesID: 1)
        ]
        let result = inheritLearnsets(entries)
        #expect(result[2]! == Set([10, 20, 30, 40]))
    }

    // MARK: - Edge Cases

    @Test func noEvolutionRelationships() {
        // Standalone species with no evolution chain
        let entries = [
            SpeciesLearnsetEntry(speciesID: 132, moveIDs: [144], evolvesFromSpeciesID: nil),  // Ditto
            SpeciesLearnsetEntry(speciesID: 302, moveIDs: [10, 20], evolvesFromSpeciesID: nil) // Sableye
        ]
        let result = inheritLearnsets(entries)
        #expect(result[132] == Set([144]))
        #expect(result[302] == Set([10, 20]))
    }

    @Test func emptyLearnsetStillInherits() {
        // Evo has no moves of its own but should inherit from pre-evo
        let entries = [
            SpeciesLearnsetEntry(speciesID: 1, moveIDs: [10, 20], evolvesFromSpeciesID: nil),
            SpeciesLearnsetEntry(speciesID: 2, moveIDs: [], evolvesFromSpeciesID: 1)
        ]
        let result = inheritLearnsets(entries)
        #expect(result[2]! == Set([10, 20]))
    }

    @Test func preEvoNotInDatasetGracefullyHandled() {
        // Species references a pre-evo that doesn't exist in the dataset
        let entries = [
            SpeciesLearnsetEntry(speciesID: 903, moveIDs: [30, 40], evolvesFromSpeciesID: 999)
        ]
        let result = inheritLearnsets(entries)
        // Should just keep its own moves without crashing
        #expect(result[903] == Set([30, 40]))
    }

    @Test func emptyInputReturnsEmptyResult() {
        let result = inheritLearnsets([])
        #expect(result.isEmpty)
    }
}
