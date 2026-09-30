//
//  AppIntentsTests.swift
//  PKReferenceTests
//
//  Covers what the Siri, Spotlight and Shortcuts actions say and how they
//  find things: Pokémon said the way people say them ("Mega Charizard X",
//  "Alolan Ninetales", "Mr. Mime", "Flabébé"); a Pokémon's matchups by type;
//  the damage calc's answer, against the numbers the calc screen showed for
//  the same matchup, and its knock-out wording; each side's stats loaded as
//  chosen, never assumed; the choices Siri offers; and Team Search's
//  answer. The damage cases use a store in memory, built from the real
//  data's values.
//
//  Siri and Spotlight themselves need a person: the phrases were tried on
//  the owner's devices.
//

import Testing
import Foundation
import SwiftData
@testable import PKReference

@MainActor
@Suite("App Intents")
struct AppIntentsTests {

    // MARK: Names

    @Test("Pokémon are named the way they're said")
    func spokenNames() {
        #expect(IntentNames.spoken(name: "Charizard-Mega-X", formName: "mega-x") == "Mega Charizard X")
        #expect(IntentNames.spoken(name: "Garchomp-Mega", formName: "mega") == "Mega Garchomp")
        #expect(IntentNames.spoken(name: "Ninetales-Alola", formName: "alola") == "Alolan Ninetales")
        #expect(IntentNames.spoken(name: "Mr-Mime", formName: nil) == "Mr Mime")
        #expect(IntentNames.spoken(name: "Rotom-Wash", formName: "wash") == "Rotom (Wash)")
    }

    private let candidates: [IntentNames.Candidate] = [
        (6, "Charizard", nil), (10034, "Charizard-Mega-X", "mega-x"), (10035, "Charizard-Mega-Y", "mega-y"),
        (38, "Ninetales", nil), (10104, "Ninetales-Alola", "alola"), (122, "Mr-Mime", nil),
        (445, "Garchomp", nil), (10058, "Garchomp-Mega", "mega"), (669, "Flabebe", nil),
    ].map { IntentNames.Candidate(id: $0.0, keys: IntentNames.keys(name: $0.1, formName: $0.2), length: $0.1.count) }

    @Test("What someone says finds the Pokémon", arguments: [
        ("Mega Charizard X", [10034]),
        ("charizard mega x", [10034]),
        ("Alolan Ninetales", [10104]),
        ("Ninetales Alola", [10104]),
        ("Mr. Mime", [122]),
        ("Garchomp", [445]),
        ("Flabébé", [669]),
        ("chariz", [6, 10034, 10035]),
        ("", []),
    ])
    func matching(said: String, ids: [Int]) {
        #expect(IntentNames.matches(said, in: candidates) == ids)
    }

    // MARK: Look Up Pokémon

    @Test("A lookup lists matchups by type, strongest first")
    func lookup() {
        let answer = PokemonLookupAnswer(name: "Garchomp", types: ["Dragon", "Ground"],
                                         baseStats: [108, 130, 95, 80, 85, 102])
        #expect(answer.baseStatTotal == 600)
        #expect(answer.matchups.map(\.multiplier) == [4, 2, 0.5, 0])
        #expect(answer.matchups.map { Set($0.types) }
                == [["Ice"], ["Dragon", "Fairy"], ["Fire", "Poison", "Rock"], ["Electric"]])
        #expect(answer.spoken.hasPrefix("Garchomp is Dragon and Ground type, with a base stat total of 600."))
        #expect(answer.spoken.contains("it takes 4 times damage from Ice"))
        #expect(answer.spoken.hasSuffix("and none from Electric."))
    }

    // MARK: Calculate Damage

    /// Garchomp, Heatran and Earthquake, with the store's values. Keep the
    /// container while using its context: the context doesn't keep it.
    private func store() throws -> ModelContainer {
        let container = try ModelContainer(
            for: PKMNStats.self, MoveData.self, SavedSpread.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        context.insert(PKMNStats(id: 445, speciesID: 445, name: "Garchomp", type1: "Dragon", type2: "Ground",
                                 baseHP: 108, baseAtk: 130, baseDef: 95, baseSpAtk: 80, baseSpDef: 85, baseSpeed: 102,
                                 ability1: "sand-veil", hiddenAbility: "rough-skin", learnableMoveIDs: [89]))
        context.insert(PKMNStats(id: 485, speciesID: 485, name: "Heatran", type1: "Fire", type2: "Steel",
                                 baseHP: 91, baseAtk: 90, baseDef: 106, baseSpAtk: 130, baseSpDef: 106, baseSpeed: 77,
                                 ability1: "flash-fire", hiddenAbility: "flame-body"))
        context.insert(MoveData(id: 89, name: "Earthquake", type: "Ground", damageClass: "physical",
                                power: 100, accuracy: 100, pp: 10, generationId: 1))
        try context.save()
        return container
    }

    private func request(_ attacker: StatChoice = .noInvestment,
                         _ defender: StatChoice = .noInvestment) -> CalcRequest {
        CalcRequest(attackerID: 445, attackerStats: attacker, defenderID: 485, defenderStats: defender, moveID: 89)
    }

    /// The calc screen showed 268–324, 161.4–195.2%, for this matchup with
    /// no investment under Champions rules (2026-09-30).
    @Test("The answer matches the calc screen for the same matchup")
    func damage() throws {
        let container = try store()
        let answer = try IntentData.damage(request(), championsMode: true, in: container.mainContext)
        #expect(answer.minDamage == 268 && answer.maxDamage == 324)
        #expect(DamageAnswer.percent(answer.minPercent) == "161.4%")
        #expect(DamageAnswer.percent(answer.maxPercent) == "195.2%")
        #expect(answer.spoken == "Garchomp's Earthquake does 161.4% to 195.2% to Heatran: a guaranteed one-hit KO.")
        #expect(answer.details
                == "Garchomp: Sand Veil, no investment. Heatran: Flash Fire, no investment. Champions rules, no field effects.")
    }

    @Test("Knock-out wording", arguments: [
        (120.0, 140.0, "a guaranteed one-hit KO"),
        (40.0, 55.0, "a two- to three-hit KO"),
        (26.0, 30.0, "a guaranteed four-hit KO"),
    ])
    func knockOut(min: Double, max: Double, expected: String) {
        let answer = DamageAnswer(attacker: "A", defender: "B", move: "M", minPercent: min, maxPercent: max,
                                  minDamage: 0, maxDamage: 0, attackerSetup: "", defenderSetup: "",
                                  championsRules: true)
        #expect(answer.knockOut == expected)
    }

    @Test("No damage says so")
    func noDamage() {
        let answer = DamageAnswer(attacker: "Garchomp", defender: "Corviknight", move: "Earthquake",
                                  minPercent: 0, maxPercent: 0, minDamage: 0, maxDamage: 0,
                                  attackerSetup: "", defenderSetup: "", championsRules: true)
        #expect(answer.knockOut == nil)
        #expect(answer.spoken == "Garchomp's Earthquake does no damage to Corviknight.")
    }

    @Test("Each side's stats are loaded as chosen")
    func statChoices() throws {
        let container = try store()
        let context = container.mainContext
        let set = SavedSpread(name: "Physical Sweeper", pokemonID: 445, abilityName: "rough-skin",
                              championsMode: false, natureID: "jolly", evAtk: 252, evSpeed: 252, moveID1: 89)
        context.insert(set)
        try context.save()

        let vm = DamageCalcVM()
        #expect(vm.load(request(.fullInvestment, .fullInvestment), championsMode: true, context: context))
        #expect(vm.side1.nature.id == "serious" && vm.side1.level == 50)
        #expect(vm.side1.evAtk == vm.side1.evPerStatMax && vm.side1.evSpAtk == 0)
        #expect(vm.side2.evHP == vm.side2.evPerStatMax && vm.side2.evDef == vm.side2.evPerStatMax)
        #expect(vm.side1.moves.compactMap { $0?.id } == [89] && vm.side2.moves.allSatisfy { $0 == nil })

        #expect(vm.load(request(.savedSet(set.persistentModelID)), championsMode: true, context: context))
        #expect(vm.side1.loadedSpreadName == "Physical Sweeper")
        #expect(!vm.side1.championsMode && vm.side1.nature.id == "jolly" && vm.side1.evAtk == 252)
        #expect(vm.side1.selectedAbility == "rough-skin")
        #expect(vm.side2.championsMode)

        // A set of another Pokémon isn't used for this one.
        #expect(!vm.load(CalcRequest(attackerID: 485, attackerStats: .savedSet(set.persistentModelID),
                                     defenderID: 445, defenderStats: .noInvestment, moveID: 89),
                         championsMode: true, context: context))
    }

    @Test("Siri offers no investment, full investment, then the Pokémon's saved sets")
    func offeredStats() throws {
        let container = try store()
        let context = container.mainContext
        let set = SavedSpread(name: "Physical Sweeper", pokemonID: 445, natureID: "jolly")
        context.insert(set)
        context.insert(SavedSpread(name: "Heatran Set", pokemonID: 485))
        try context.save()

        let offered = try IntentData.statsChoices(for: 445, in: context)
        #expect(offered.map(\.title) == ["No investment", "Full investment", "Physical Sweeper"])
        #expect(offered[2].choice == .savedSet(set.persistentModelID))
        #expect(try IntentData.statsChoices(for: nil, in: context).count == 2)
    }

    // MARK: Search Teams

    @Test("Team Search's answer")
    func teamSearch() {
        let answer = TeamSearchAnswer(query: "Trick Room", compositions: 592, teams: 1348, top: [
            .init(species: ["Charizard", "Golisopod", "Grimmsnarl"], teams: 64),
        ])
        #expect(answer.spoken.hasPrefix("592 compositions, from 1,348 teams, match \"Trick Room\". The top one, from 64 teams: Charizard, Golisopod"))
        #expect(TeamSearchAnswer(query: "Nothing", compositions: 0, teams: 0, top: []).spoken
                == "No tournament teams match \"Nothing\".")
    }
}
