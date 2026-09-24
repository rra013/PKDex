//
//  LimitlessTeamImportTests.swift
//  PKDexTests
//
//  Covers `LimitlessTeamImport.swift`: resolving Limitless species names
//  ("Hisuian Arcanine", "Indeedee ♀", bare "Maushold") to Pokedex rows, and
//  planning tournament saves through the paste importer. Names and slugs are
//  the ones Limitless sends, and row names and default-form flags match the
//  synced Pokedex. Hermetic: synthetic `PKMNStats` / `MoveData`, nothing
//  inserted into SwiftData, and no stat prediction (it needs the bundled
//  model).
//

import Testing
import Foundation
@testable import PKDex

// MARK: - Resolver

@Suite("Limitless Species Resolver")
struct LimitlessSpeciesResolverTests {

    /// (row name, is default form), as in the Pokedex.
    private static let rows: [(String, Bool)] = [
        ("Arcanine", true), ("Arcanine-Hisui", false),
        ("Raichu", true), ("Raichu-Alola", false), ("Raichu-Mega-X", false),
        ("Indeedee-Male", true), ("Indeedee-Female", false),
        ("Maushold-Family-Of-Four", true),
        ("Tauros", true), ("Tauros-Paldea-Combat-Breed", false),
        ("Tauros-Paldea-Blaze-Breed", false),
        ("Floette", true), ("Floette-Eternal", false), ("Floette-Mega", false),
        ("Toxtricity-Amped", true),
        ("Calyrex", true), ("Calyrex-Ice", false), ("Calyrex-Shadow", false),
        ("Meowstic-Male", true), ("Meowstic-Female-Mega", false),
        ("Iron-Hands", true), ("Iron-Treads", true),
        ("Mr-Mime", true), ("Mr-Rime", true),
        ("Flabebe", true),
    ]

    private static let resolver = LimitlessSpeciesResolver(
        rows.map { LimitlessSpeciesResolver.Entry(name: $0.0, isDefaultForm: $0.1) })

    private func resolve(_ name: String, _ slug: String? = nil) -> String? {
        Self.resolver.resolve(name: name, slug: slug)
    }

    @Test("Exact names still resolve, and a base name doesn't turn into a form")
    func exactNames() {
        #expect(resolve("Raichu", "raichu") == "Raichu")
        #expect(resolve("Arcanine") == "Arcanine")
        #expect(resolve("Iron Hands", "iron-hands") == "Iron-Hands")
        #expect(resolve("Mr. Rime") == "Mr-Rime")
    }

    @Test("Regional adjectives find the regional form")
    func regionalForms() {
        #expect(resolve("Hisuian Arcanine") == "Arcanine-Hisui")
        #expect(resolve("Hisuian Arcanine", "arcanine-hisui") == "Arcanine-Hisui")
        #expect(resolve("Alolan Raichu") == "Raichu-Alola")
    }

    @Test("Gender marks find the gendered form")
    func genderedForms() {
        #expect(resolve("Indeedee ♀") == "Indeedee-Female")
        #expect(resolve("Indeedee ♀", "indeedee-f") == "Indeedee-Female")
    }

    @Test("Extra words in a display name pick the most specific form")
    func mostSpecificForm() {
        #expect(resolve("Paldean Tauros Blaze Breed", "tauros-paldea-blaze")
                == "Tauros-Paldea-Blaze-Breed")
        #expect(resolve("Shadow Rider Calyrex", "calyrex-shadow-rider") == "Calyrex-Shadow")
        #expect(resolve("Ice Rider Calyrex") == "Calyrex-Ice")
    }

    @Test("A bare base name falls back to the default form")
    func defaultForms() {
        #expect(resolve("Maushold", "maushold") == "Maushold-Family-Of-Four")
        #expect(resolve("Indeedee", "indeedee") == "Indeedee-Male")
        // Forms the Pokedex doesn't store, because they only differ
        // cosmetically, land on the default form too.
        #expect(resolve("Low Key Toxtricity", "toxtricity-low-key") == "Toxtricity-Amped")
        #expect(resolve("Meowstic ♀", "meowstic-f") == "Meowstic-Male")
    }

    @Test("Aliases beat the slug: Champions Floette means the Eternal Flower form")
    func aliasesWin() {
        #expect(resolve("Floette", "floette") == "Floette-Eternal")
        #expect(resolve("Eternal Flower Floette", "floette-eternal") == "Floette-Eternal")
        #expect(resolve("Paldean Tauros") == "Tauros-Paldea-Combat-Breed")
    }

    @Test("A first word shared across species doesn't guess")
    func sharedFirstWordIsAmbiguous() {
        #expect(resolve("Iron Crown") == nil)
        #expect(resolve("Mr. Nobody") == nil)
    }

    @Test("Unknown names and accents")
    func unknownAndAccents() {
        #expect(resolve("Missingno") == nil)
        #expect(resolve("") == nil)
        #expect(resolve("Flabébé") == "Flabebe")
    }
}

// MARK: - Importer

@MainActor
@Suite("Limitless Team Import")
struct LimitlessTeamImportTests {

    // MARK: Fixtures

    private static func pokemon(_ id: Int, _ name: String, species: Int? = nil,
                                form: String? = nil, types: (String, String?),
                                abilities: [String]) -> PKMNStats {
        PKMNStats(id: id, speciesID: species ?? id, name: name, formName: form,
                  type1: types.0, type2: types.1,
                  baseHP: 80, baseAtk: 80, baseDef: 80,
                  baseSpAtk: 80, baseSpDef: 80, baseSpeed: 80,
                  ability1: abilities.first,
                  ability2: abilities.count > 1 ? abilities[1] : nil,
                  hiddenAbility: abilities.count > 2 ? abilities[2] : nil)
    }

    private static func move(_ id: Int, _ name: String, _ type: String,
                             _ damageClass: String) -> MoveData {
        MoveData(id: id, name: name, type: type, damageClass: damageClass,
                 power: damageClass == "status" ? nil : 80, accuracy: 100, pp: 10,
                 priority: 0, minHits: nil, maxHits: nil, drain: 0, healing: 0,
                 critRate: 0, makesContact: false, generationId: 9)
    }

    private static let pokedex: [PKMNStats] = [
        pokemon(727, "Incineroar", types: ("Fire", "Dark"), abilities: ["blaze", "intimidate"]),
        pokemon(59, "Arcanine", types: ("Fire", nil), abilities: ["intimidate", "flash-fire"]),
        pokemon(10230, "Arcanine-Hisui", species: 59, form: "hisui",
                types: ("Fire", "Rock"), abilities: ["intimidate", "flash-fire", "rock-head"]),
        pokemon(876, "Indeedee-Male", types: ("Psychic", "Normal"), abilities: ["psychic-surge"]),
        pokemon(10186, "Indeedee-Female", species: 876, form: "female",
                types: ("Psychic", "Normal"), abilities: ["psychic-surge"]),
        pokemon(902, "Basculegion-Male", types: ("Water", "Ghost"), abilities: ["adaptability"]),
        pokemon(10248, "Basculegion-Female", species: 902, form: "female",
                types: ("Water", "Ghost"), abilities: ["adaptability"]),
        pokemon(681, "Aegislash-Shield", types: ("Steel", "Ghost"), abilities: ["stance-change"]),
    ]

    private static let moves: [MoveData] = [
        move(252, "Fake Out", "Normal", "physical"),
        move(369, "U Turn", "Bug", "physical"),
        move(182, "Protect", "Normal", "status"),
        move(433, "Trick Room", "Psychic", "status"),
        move(94, "Psychic", "Psychic", "special"),
        move(247, "Shadow Ball", "Ghost", "special"),
        move(503, "Scald", "Water", "special"),
        move(710, "Last Respects", "Ghost", "physical"),
        move(57, "Wave Crash", "Water", "physical"),
    ]

    private static let importer = LimitlessTeamImporter(allPokemon: pokedex, allMoves: moves)

    private static func member(_ name: String, slug: String? = nil, item: String? = nil,
                               ability: String? = nil, nature: String? = nil,
                               moves: [String] = ["Protect"]) -> LimitlessStanding.TeamMember {
        .init(name: name, limitlessID: slug, item: item, ability: ability,
              attacks: moves, nature: nature, tera: nil)
    }

    /// A slice of a real M-C decklist, in Limitless's spelling.
    private static let team: [LimitlessStanding.TeamMember] = [
        member("Incineroar", slug: "incineroar", item: "Sitrus Berry", ability: "Intimidate",
               nature: "Careful", moves: ["Fake Out", "U-turn", "Protect"]),
        member("Hisuian Arcanine", slug: "arcanine-hisui", item: "Air Balloon",
               ability: "Rock Head", nature: "adamant", moves: ["Protect"]),
        member("Indeedee ♀", slug: "indeedee-f", item: "Psychic Seed",
               ability: "Psychic Surge", nature: "Sassy", moves: ["Trick Room", "Psychic"]),
    ]

    /// The refusal's lines, or nil when the plan succeeded.
    private func unmatched<T>(_ result: Result<T, LimitlessUnmatchedNames>) -> [String]? {
        if case .failure(let unmatched) = result { return unmatched.lines }
        return nil
    }

    private func plan(_ members: [LimitlessStanding.TeamMember], taken: Set<String> = [])
        throws -> TeamImportPlan
    {
        try Self.importer.planTeam(members, teamName: "Alex's Team", taken: taken,
                                   predictStats: false).get()
    }

    // MARK: Team plans

    @Test("A decklist plans one spread per member, resolved to Pokedex rows")
    func plansTeam() throws {
        let plan = try plan(Self.team)
        #expect(plan.team.name == "Alex's Team")
        #expect(plan.team.slots.map(\.pokemonName)
                == ["Incineroar", "Arcanine-Hisui", "Indeedee-Female"])
        #expect(plan.spreads.map(\.name) == ["Alex's Team · Incineroar",
                                             "Alex's Team · Arcanine-Hisui",
                                             "Alex's Team · Indeedee-Female"])
        #expect(plan.team.slots.map(\.spreadName) == plan.spreads.map(\.name))
    }

    @Test("Limitless's nature is used, whatever its casing")
    func usesLimitlessNature() throws {
        let plan = try plan(Self.team)
        #expect(plan.spreads.map(\.natureID) == ["careful", "adamant", "sassy"])
    }

    @Test("Moves resolve across spelling, abilities to the species' own spelling")
    func resolvesMovesAndAbilities() throws {
        let incineroar = try #require(try plan(Self.team).spreads.first)
        #expect([incineroar.moveID1, incineroar.moveID2, incineroar.moveID3] == [252, 369, 182])
        #expect(incineroar.abilityName == "intimidate")
        #expect(incineroar.level == 50)
        #expect(incineroar.championsMode)
    }

    @Test("Items the calc doesn't model are kept as text")
    func keepsUnmodelledItems() throws {
        let plan = try plan(Self.team)
        #expect(plan.spreads.map(\.itemRawValue) == ["Sitrus Berry", "Air Balloon", "Psychic Seed"])
        #expect(plan.team.slots.map(\.itemRawValue) == ["Sitrus Berry", "Air Balloon", "Psychic Seed"])
    }

    @Test("Abilities save as the engine's hyphenated IDs, listed on the species or not")
    func abilityFallback() throws {
        let member = Self.member("Aegislash", ability: "Stance Change")
        let spread = try Self.importer.planSpread(member, taken: [], predictStats: false).get()
        #expect(spread.pokemonName == "Aegislash-Shield")
        #expect(spread.abilityName == "stance-change")

        let unlisted = Self.member("Incineroar", ability: "Snow Warning")
        let other = try Self.importer.planSpread(unlisted, taken: [], predictStats: false).get()
        #expect(other.abilityName == "snow-warning")
    }

    @Test("A missing nature defaults to neutral")
    func missingNature() throws {
        let plan = try plan([Self.member("Incineroar")])
        #expect(plan.spreads.first?.natureID == "serious")
    }

    @Test("Spread names avoid names already taken")
    func uniqueNames() throws {
        let plan = try plan(Array(Self.team.prefix(1)), taken: ["Alex's Team · Incineroar"])
        #expect(plan.spreads.map(\.name) == ["Alex's Team · Incineroar 2"])
    }

    // MARK: Unmatched names

    @Test("Any unmatched species or move refuses the save and lists every one")
    func unmatchedNames() {
        let members = [
            Self.member("Missingno", moves: ["Protect"]),
            Self.member("Incineroar", moves: ["Fake Out", "Earthquack"]),
        ]
        let result = Self.importer.planTeam(members, teamName: "T", taken: [],
                                            predictStats: false)
        #expect(unmatched(result) == [
            "no match found for Missingno",
            "no match found for move Earthquack on Incineroar",
        ])
    }

    @Test("A single member's save has the same rule")
    func unmatchedSingleMember() {
        let result = Self.importer.planSpread(
            Self.member("Hisuian Arcanine", moves: ["Flare Blits"]),
            taken: [], predictStats: false)
        #expect(unmatched(result) == ["no match found for move Flare Blits on Hisuian Arcanine"])
    }

    @Test("A single member's spread is named after its row, numbered when taken")
    func singleMemberName() throws {
        let member = Self.team[1]
        let first = try Self.importer.planSpread(member, taken: [], predictStats: false).get()
        let second = try Self.importer.planSpread(member, taken: [first.name],
                                                  predictStats: false).get()
        #expect(first.name == "Arcanine-Hisui")
        #expect(second.name == "Arcanine-Hisui 2")
    }

    // MARK: Basculegion

    @Test("Basculegion follows Limitless's label: plain is male, ♀ is female")
    func basculegion() {
        // The moveset no longer decides. A special-attacking plain
        // "Basculegion" is still the male form, because Limitless marks the
        // female form "Basculegion ♀".
        let special = Self.member("Basculegion", slug: "basculegion",
                                  moves: ["Scald", "Shadow Ball", "Protect"])
        let labelled = Self.member("Basculegion ♀", slug: "basculegion-f",
                                   moves: ["Wave Crash", "Last Respects"])
        #expect(Self.importer.pokemon(for: special)?.name == "Basculegion-Male")
        #expect(Self.importer.pokemon(for: labelled)?.name == "Basculegion-Female")
    }
}
