//
//  AppIntentsTests.swift
//  PKReferenceTests
//
//  Covers what the Siri, Spotlight and Shortcuts actions say and how they
//  find things: Pokémon said the way people say them ("Mega Charizard X",
//  "Alolan Ninetales", "Mr. Mime", "Flabébé"); a Pokémon's matchups by type;
//  the damage calc's answer, against the numbers the calc screen showed for
//  the same matchup, and its knock-out wording; each side's stats loaded as
//  chosen, never assumed; the choices Siri offers; Team Search's answer;
//  speed comparisons, against Speed Tiers' arithmetic, with a saved set's
//  Choice Scarf and Mega; and legality, from each regulation's files, for
//  species, Megas and forms. The damage and speed cases use a store in
//  memory, built from the real data's values. Saved sets and teams are in
//  `SavedIntentsTests`.
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

    @Test("Siri offers three investments, then the Pokémon's saved sets")
    func offeredStats() throws {
        let container = try store()
        let context = container.mainContext
        let set = SavedSpread(name: "Physical Sweeper", pokemonID: 445, natureID: "jolly")
        context.insert(set)
        context.insert(SavedSpread(name: "Heatran Set", pokemonID: 485))
        try context.save()

        let offered = try IntentData.statsChoices(for: 445, in: context)
        #expect(offered.map(\.title)
                == ["No investment", "Full investment", "Full investment and a boosting nature", "Physical Sweeper"])
        #expect(offered[3].choice == .savedSet(set.persistentModelID))
        #expect(try IntentData.statsChoices(for: nil, in: context).count == 3)
    }

    /// Adamant for a physical attacker; Bold for its target, whose Attack
    /// the calc doesn't use.
    @Test("Full investment and a boosting nature raises the stat the move uses")
    func boostingNature() throws {
        let container = try store()
        let vm = DamageCalcVM()
        #expect(vm.load(request(.fullInvestmentBoostingNature, .fullInvestmentBoostingNature),
                        championsMode: true, context: container.mainContext))
        #expect(vm.side1.nature.id == "adamant" && vm.side1.evAtk == vm.side1.evPerStatMax)
        #expect(vm.side2.nature.id == "bold")
        #expect(vm.side2.evHP == vm.side2.evPerStatMax && vm.side2.evDef == vm.side2.evPerStatMax)
        let answer = try IntentData.damage(request(.fullInvestmentBoostingNature, .fullInvestment),
                                           championsMode: true, in: container.mainContext)
        #expect(answer.details.hasPrefix("Garchomp: Sand Veil, full investment, Adamant nature. Heatran: Flash Fire, full investment."))
    }

    @Test("How players say an investment", arguments: [
        ("max def", IntentNames.Investment.full),
        ("Max", .full),
        ("252 Atk", .full),
        ("fully invested", .full),
        ("max Adamant", .fullWithNature),
        ("max with a plus nature", .fullWithNature),
        ("Jolly max Speed", .fullWithNature),
        ("uninvested", .uninvested),
        ("no EVs", .uninvested),
    ] as [(String, IntentNames.Investment)])
    func investmentWords(said: String, expected: IntentNames.Investment) {
        #expect(IntentNames.investment(said: said) == expected)
    }

    @Test("A saved set's name isn't an investment")
    func notAnInvestment() {
        #expect(IntentNames.investment(said: "Scarf Koko") == nil)
        #expect(IntentNames.investment(said: "") == nil)
    }

    @Test("Answering Siri's question with \"max def\" or a set's name")
    func spokenStats() throws {
        let container = try store()
        let context = container.mainContext
        context.insert(SavedSpread(name: "Physical Sweeper", pokemonID: 445))
        try context.save()
        #expect(IntentData.statsEntities(matching: "max def", in: context).map(\.id) == ["full"])
        #expect(IntentData.statsEntities(matching: "max plus", in: context).map(\.id) == ["boosted"])
        #expect(IntentData.statsEntities(matching: "physical sweeper", in: context).map(\.title) == ["Physical Sweeper"])
        #expect(IntentData.speedStatsEntities(matching: "max speed", in: context).map(\.id) == ["full"])
        #expect(IntentData.speedStatsEntities(matching: "Jolly max", in: context).map(\.id) == ["fast"])
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

    // MARK: Compare Speed

    /// Dragapult, Tapu Koko and Garchomp, with the store's values.
    private func speedStore() throws -> ModelContainer {
        let container = try ModelContainer(
            for: PKMNStats.self, MoveData.self, SavedSpread.self, PKMN.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        context.insert(PKMNStats(id: 887, speciesID: 887, name: "Dragapult", type1: "Dragon", type2: "Ghost",
                                 baseHP: 88, baseAtk: 120, baseDef: 75, baseSpAtk: 100, baseSpDef: 75, baseSpeed: 142,
                                 ability1: "clear-body"))
        context.insert(PKMNStats(id: 785, speciesID: 785, name: "Tapu-Koko", type1: "Electric", type2: "Fairy",
                                 baseHP: 70, baseAtk: 115, baseDef: 85, baseSpAtk: 95, baseSpDef: 75, baseSpeed: 130,
                                 ability1: "electric-surge"))
        context.insert(PKMNStats(id: 445, speciesID: 445, name: "Garchomp", type1: "Dragon", type2: "Ground",
                                 baseHP: 108, baseAtk: 130, baseDef: 95, baseSpAtk: 80, baseSpDef: 85, baseSpeed: 102,
                                 ability1: "sand-veil"))
        try context.save()
        return container
    }

    /// Level 50 with 31 IVs, as Speed Tiers works it out: Dragapult is 162
    /// with nothing, 194 with full investment and 213 with a Speed nature
    /// too; Tapu Koko is 182 with full investment.
    @Test("Speeds follow the choices, and the faster one is named")
    func speed() throws {
        let container = try speedStore()
        let context = container.mainContext
        func compare(_ first: SpeedChoice, _ second: SpeedChoice) throws -> SpeedAnswer {
            try IntentData.speed(SpeedRequest(firstID: 887, firstStats: first, secondID: 785, secondStats: second),
                                 championsMode: true, in: context)
        }
        #expect(try compare(.noInvestment, .fullInvestment).first.speed == 162)
        #expect(try compare(.fullInvestment, .fullInvestment).first.speed == 194)
        let answer = try compare(.fullInvestmentSpeedNature, .fullInvestment)
        #expect(answer.first.speed == 213 && answer.second.speed == 182)
        #expect(answer.spoken == "Dragapult is faster: 213 Speed to Tapu Koko's 182.")
        #expect(answer.details
                == "Dragapult: full investment and a Speed nature. Tapu Koko: full investment. Champions rules, no field effects.")
        #expect(try compare(.noInvestment, .fullInvestment).spoken
                == "Tapu Koko is faster: 182 Speed to Dragapult's 162.")
    }

    @Test("A saved set brings its Choice Scarf and its Mega")
    func speedSavedSets() throws {
        let container = try speedStore()
        let context = container.mainContext
        let scarf = SavedSpread(name: "Scarf Koko", pokemonID: 785, itemRawValue: "Choice Scarf",
                                championsMode: true, natureID: "timid", evSpeed: 32)
        let mega = SavedSpread(name: "Mega Chomp", pokemonID: 445, itemRawValue: "Garchompite",
                               championsMode: true, natureID: "jolly", evSpeed: 32)
        context.insert(scarf)
        context.insert(mega)
        try context.save()

        // 200 with a Speed nature, times 1.5.
        let scarfAnswer = try IntentData.speed(
            SpeedRequest(firstID: 887, firstStats: .fullInvestmentSpeedNature,
                         secondID: 785, secondStats: .savedSet(scarf.persistentModelID)),
            championsMode: true, in: context)
        #expect(scarfAnswer.second.speed == 300)
        #expect(scarfAnswer.second.setup == "your set Scarf Koko, with Choice Scarf")
        #expect(scarfAnswer.spoken == "Tapu Koko is faster: 300 Speed to Dragapult's 213.")

        // Mega Garchomp's base Speed is 92, not Garchomp's 102.
        let megaAnswer = try IntentData.speed(
            SpeedRequest(firstID: 445, firstStats: .savedSet(mega.persistentModelID),
                         secondID: 887, secondStats: .noInvestment),
            championsMode: true, in: context)
        #expect(megaAnswer.first.name == "Mega Garchomp" && megaAnswer.first.speed == 158)

        // A set of another Pokémon isn't used for this one.
        #expect(throws: IntentError.self) {
            try IntentData.speed(SpeedRequest(firstID: 887, firstStats: .savedSet(scarf.persistentModelID),
                                              secondID: 785, secondStats: .noInvestment),
                                 championsMode: true, in: context)
        }
    }

    @Test("A tie says either could move first")
    func speedTie() {
        let side = SpeedAnswer.Side(name: "Garchomp", speed: 169, setup: "full investment", championsRules: true)
        let other = SpeedAnswer.Side(name: "Garchomp", speed: 169, setup: "full investment", championsRules: false)
        let answer = SpeedAnswer(first: side, second: other)
        #expect(answer.spoken == "Garchomp and Garchomp tie at 169 Speed, so either could move first.")
        #expect(answer.details.hasSuffix("Garchomp on Champions rules, Garchomp on mainline rules, no field effects."))
    }

    @Test("Siri offers three investments, then the Pokémon's saved sets")
    func offeredSpeeds() throws {
        let container = try speedStore()
        let context = container.mainContext
        context.insert(SavedSpread(name: "Scarf Koko", pokemonID: 785, itemRawValue: "Choice Scarf",
                                   championsMode: true, natureID: "timid", evSpeed: 32))
        try context.save()
        let offered = IntentData.speedChoices(for: 785, in: context)
        #expect(offered.map(\.title)
                == ["No investment", "Full investment", "Full investment and a Speed nature", "Scarf Koko"])
        #expect(offered[3].subtitle == "Saved set · Timid · 32 Speed stat points · Choice Scarf")
        #expect(IntentData.speedChoices(for: nil, in: context).count == 3)
    }

    // MARK: Check Legality

    private let noListing = PokemonLegality.Listing(megas: [], forms: [])

    @Test("Legality of species, Megas and forms", arguments: [
        (nil, "Incineroar", "Incineroar", LegalityAnswer.Verdict.legal),
        ("mega-x", "Mega Charizard X", "Charizard", .legal),
        ("mega", "Mega Garchomp Z", "Garchomp", .formNotInRegulation(species: "Garchomp")),
        ("mega", "Mega Rayquaza", "Rayquaza", .megaNotAllowed("Mega Rayquaza")),
        ("alola", "Alolan Ninetales", "Ninetales", .legal),
        ("hisui", "Hisuian Arcanine", "Arcanine", .legal),
        ("paldea-combat-breed", "Tauros (Paldea Combat Breed)", "Tauros", .legal),
        ("galar", "Galarian Ninetales", "Ninetales", .formNotInRegulation(species: "Ninetales")),
        ("wash", "Rotom (Wash)", "Rotom", .formNotInRegulation(species: "Rotom")),
        ("blue-plumage", "Squawkabilly (Blue Plumage)", "Squawkabilly", .legal),
        ("yellow-plumage", "Squawkabilly (Yellow Plumage)", "Squawkabilly", .formNotInRegulation(species: "Squawkabilly")),
    ] as [(String?, String, String, LegalityAnswer.Verdict)])
    func legalityVerdicts(form: String?, name: String, species: String, expected: LegalityAnswer.Verdict) {
        let listing = PokemonLegality.Listing(
            megas: ["Mega Charizard X", "Mega Charizard Y", "Mega Garchomp", "Mega Rayquaza"],
            forms: ["Alola Form", "Hisuian Form", "Paldean Form", "White/Blue Plumage"])
        let verdict = PokemonLegality.verdict(formName: form, spokenName: name, listedSpecies: species,
                                              speciesName: species, rules: .fallback, listing: listing)
        #expect(verdict == expected)
    }

    @Test("A species the regulation doesn't list, or Megas it doesn't allow")
    func legalityRefusals() {
        #expect(PokemonLegality.verdict(formName: nil, spokenName: "Tapu Koko", listedSpecies: nil,
                                        speciesName: "Tapu Koko", rules: .fallback, listing: nil) == .notInRegulation)
        let noMegas = ChampionsRules(
            speciesClause: true, itemClause: false, statPointsMaxTotal: 66, statPointsMaxPerStat: 32,
            ivLockedAt: 31, teamSize: 6, maxRestrictedPerTeam: 0, megaEvolutionsAllowed: false,
            megaRayquazaAllowed: false, teraAllowed: false, zMovesAllowed: false, dynamaxAllowed: false)
        #expect(PokemonLegality.verdict(formName: "mega", spokenName: "Mega Garchomp", listedSpecies: "Garchomp",
                                        speciesName: "Garchomp", rules: noMegas,
                                        listing: .init(megas: ["Mega Garchomp"], forms: []))
                == .megaNotAllowed("Mega Evolution"))
    }

    @Test("Listed forms become the start of the Pokédex's form names")
    func formKeys() {
        #expect(PokemonLegality.formKeys("Hisuian Form") == ["hisui"])
        #expect(PokemonLegality.formKeys("Alola Form") == ["alola"])
        #expect(PokemonLegality.formKeys("Low Key Form") == ["lowkey"])
        #expect(PokemonLegality.formKeys("White/Blue Plumage") == ["whiteplumage", "blueplumage"])
    }

    @Test("Legality answers say yes or no, and why")
    func legalitySpoken() {
        func answer(_ name: String, _ verdict: LegalityAnswer.Verdict) -> String {
            LegalityAnswer(name: name, regulation: "Regulation M-C", verdict: verdict, schedule: nil).spoken
        }
        #expect(answer("Incineroar", .legal) == "Yes, Incineroar is legal in Regulation M-C.")
        #expect(answer("Tapu Koko", .notInRegulation) == "No, Tapu Koko isn't in Regulation M-C.")
        #expect(answer("Mega Rayquaza", .megaNotAllowed("Mega Rayquaza"))
                == "No, Regulation M-C doesn't allow Mega Rayquaza.")
        #expect(answer("Rotom (Wash)", .formNotInRegulation(species: "Rotom"))
                == "No, Rotom is in Regulation M-C, but not as Rotom (Wash).")
    }

    @Test("A regulation's dates, in the right tense")
    func legalitySchedule() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        func day(_ month: Int, _ day: Int, hour: Int = 0) throws -> Date {
            try #require(calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour)))
        }
        let from = try day(9, 9), until = try day(12, 2)
        func schedule(on now: Date) -> String? {
            LegalityAnswer.schedule(regulation: "Regulation M-C", from: from, until: until, now: now)
        }
        #expect(schedule(on: try day(9, 30)) == "Regulation M-C runs from September 9, 2026 to December 2, 2026.")
        #expect(schedule(on: try day(12, 2, hour: 20)) == "Regulation M-C runs from September 9, 2026 to December 2, 2026.")
        #expect(schedule(on: try day(12, 3, hour: 1)) == "Regulation M-C ran from September 9, 2026 to December 2, 2026.")
        #expect(schedule(on: try day(8, 1)) == "Regulation M-C starts on September 9, 2026 and runs until December 2, 2026.")
        #expect(LegalityAnswer.schedule(regulation: "Regulation M-C", from: from, until: nil) == nil)
    }

    /// Against the bundled Regulation M-C, with the Pokédex's own names:
    /// "Kommo-O" where the regulation says "Kommo-o", and Floette's Eternal
    /// form, which is Champions' Floette.
    @Test("Legality from the bundled regulation")
    func legalityFromRegulation() throws {
        let container = try ModelContainer(
            for: PKMNStats.self, MoveData.self, SavedSpread.self, PKMN.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let rows: [(Int, Int, String, String?)] = [
            (727, 727, "Incineroar", nil), (785, 785, "Tapu-Koko", nil),
            (6, 6, "Charizard", nil), (10034, 6, "Charizard-Mega-X", "mega-x"),
            (38, 38, "Ninetales", nil), (10104, 38, "Ninetales-Alola", "alola"),
            (479, 479, "Rotom", nil), (10009, 479, "Rotom-Wash", "wash"),
            (784, 784, "Kommo-O", nil), (670, 670, "Floette", nil), (10061, 670, "Floette-Eternal", "eternal"),
        ]
        for (id, species, name, form) in rows {
            context.insert(PKMNStats(id: id, speciesID: species, name: name, formName: form, type1: "Normal",
                                     baseHP: 1, baseAtk: 1, baseDef: 1, baseSpAtk: 1, baseSpDef: 1, baseSpeed: 1))
        }
        try context.save()
        func verdict(_ id: Int) throws -> LegalityAnswer.Verdict {
            try IntentData.legality(id, regulation: .mC, in: context).verdict
        }
        #expect(try verdict(727) == .legal)
        #expect(try verdict(785) == .notInRegulation)
        #expect(try verdict(10034) == .legal)
        #expect(try verdict(10104) == .legal)
        #expect(try verdict(10009) == .formNotInRegulation(species: "Rotom"))
        #expect(try verdict(784) == .legal)
        #expect(try verdict(10061) == .legal)
        let answer = try IntentData.legality(727, regulation: .mC, in: context)
        #expect(answer.regulation == "Regulation M-C")
        #expect(answer.schedule?.contains("September 9, 2026") == true)
    }

    @Test("Every regulation can be asked about")
    func regulationChoices() {
        #expect(RegulationChoice.allCases.map(\.rawValue) == ChampionsRegulation.allCases.map(\.rawValue))
    }
}
