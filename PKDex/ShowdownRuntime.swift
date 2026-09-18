//
//  ShowdownRuntime.swift
//  PKDex
//
//  Port of @smogon/calc's runtime objects: move.ts and pokemon.ts, plus the
//  data model + "generation" data provider that upstream gets from @pkmn/dex.
//  MIT — see PKDex/ShowdownPort-NOTES.md (full port; Z/Max/Tera kept dormant).
//

import Foundation

// MARK: - Shared enums

enum ShowdownType: String, Hashable, Codable {
    case normal = "Normal", fire = "Fire", water = "Water", electric = "Electric"
    case grass = "Grass", ice = "Ice", fighting = "Fighting", poison = "Poison"
    case ground = "Ground", flying = "Flying", psychic = "Psychic", bug = "Bug"
    case rock = "Rock", ghost = "Ghost", dragon = "Dragon", dark = "Dark"
    case steel = "Steel", fairy = "Fairy", stellar = "Stellar", typeless = "???"
}

enum ShowdownCategory: String, Codable { case physical = "Physical", special = "Special", status = "Status" }
nonisolated enum ShowdownStatus: String, Sendable { case slp = "slp", psn = "psn", brn = "brn", frz = "frz", par = "par", tox = "tox", none = "" }

// MARK: - Data model (decoded from vendored JSON; populated by ShowdownData)

/// Species record — the fields `@smogon/calc` reads off `gen.species.get()`.
struct ShowdownSpecies: Codable, Hashable {
    var name: String
    var types: [ShowdownType]              // 1 or 2
    var baseStats: ShowdownStats
    var weightkg: Double
    var abilities: [String]                // slot 0 first; `.first` = default
    var gender: String?                    // "M"/"F"/"N"
    var nfe: Bool?                          // not-fully-evolved (Eviolite)
    var otherFormes: [String]?             // e.g. mega/forme names (order matters for getForme)
    var canGigantamax: Bool?
    var isMega: Bool?
}

/// Move record — mirrors the @pkmn `Move` fields the calc consumes.
struct ShowdownMoveData: Codable, Hashable {
    var name: String
    var basePower: Int
    var type: ShowdownType
    var category: ShowdownCategory?
    var flags: [String: Int]?
    var priority: Int?
    var target: String?
    var multihit: [Int]?                    // [] / [n] / [min,max]
    var multiaccuracy: Bool?
    var drain: [Int]?                       // [num, den]
    var recoil: [Int]?                      // [num, den]
    var hasCrashDamage: Bool?
    var mindBlownRecoil: Bool?
    var struggleRecoil: Bool?
    var willCrit: Bool?
    var breaksProtect: Bool?
    var ignoreDefensive: Bool?
    var overrideOffensiveStat: String?
    var overrideDefensiveStat: String?
    var overrideOffensivePokemon: String?
    var overrideDefensivePokemon: String?
    var isZ: Bool?
    var isMax: Bool?
    var secondaries: Bool?
    var selfBoosts: [String: Int]?          // data.self.boosts
    var zMoveBasePower: Int?                // data.zMove.basePower
    var maxMoveBasePower: Int?              // data.maxMove.basePower

    var id: ShowdownID { toID(name) }
}

// MARK: - Generation data provider (replaces @pkmn/dex `gen`)

/// Data access the mechanics need. `num` is the upstream generation number
/// (0 == Champions, 9 == SV). Backed by vendored JSON in `ShowdownData`.
protocol ShowdownGeneration {
    var num: Int { get }
    func species(_ id: ShowdownID) -> ShowdownSpecies?
    func move(_ id: ShowdownID) -> ShowdownMoveData?
    /// Type-effectiveness of `attacking` onto a single `defending` type.
    func effectiveness(_ attacking: ShowdownType, _ defending: ShowdownType) -> Double
    func nature(_ name: String?) -> ShowdownNature?
}

extension ShowdownGeneration {
    func nature(_ name: String?) -> ShowdownNature? { ShowdownNatures.get(name) }
}

// MARK: - Move (move.ts)

private let SPECIAL_TYPES: Set<ShowdownType> = [.fire, .water, .grass, .electric, .ice, .psychic, .dark, .dragon]

/// Reference type: the pipeline mutates `move.type`/`move.category`/flags in place.
final class ShowdownMove {
    var gen: Int
    var name: String
    var originalName: String
    var ability: String?
    var item: String?
    var useZ: Bool
    var useMax: Bool
    var hits: Int
    var timesUsed: Int
    var timesUsedWithMetronome: Int?
    var bp: Int
    var type: ShowdownType
    var category: ShowdownCategory
    var flags: [String: Int]
    var secondaries: Bool
    var target: String
    var recoil: [Int]?
    var hasCrashDamage: Bool
    var mindBlownRecoil: Bool
    var struggleRecoil: Bool
    var isCrit: Bool
    var isStellarFirstUse: Bool
    var drain: [Int]?
    var priority: Int
    var dropsStats: Int?
    var ignoreDefensive: Bool
    var overrideOffensiveStat: String?
    var overrideDefensiveStat: String?
    var overrideOffensivePokemon: String?
    var overrideDefensivePokemon: String?
    var breaksProtect: Bool
    var isZ: Bool
    var isMax: Bool
    var multiaccuracy: Bool

    /// Faithful port of the `Move` constructor. Z/Max resolution is preserved
    /// (dormant for Champions, which never sets `useZ`/`useMax`).
    init(_ gen: ShowdownGeneration, _ name: String, ability: String? = nil, item: String? = nil,
         useZ: Bool = false, useMax: Bool = false, isCrit: Bool = false,
         isStellarFirstUse: Bool = false, hits: Int? = nil, timesUsed: Int? = nil,
         timesUsedWithMetronome: Int? = nil, overrideBasePower: Int? = nil) {
        self.originalName = name
        var data = gen.move(toID(name)) ?? ShowdownMoveData(name: name, basePower: 0, type: .typeless)
        if let overrideBasePower { data.basePower = overrideBasePower }

        self.hits = 1
        // Z/Max name/power resolution intentionally simplified: upstream swaps in
        // the Z/Max move's data here. Champions never uses them; when exposed
        // later this is the hook point (see ShowdownPort-NOTES.md).
        if !(useMax && data.maxMoveBasePower != nil) && !(useZ && (data.zMoveBasePower ?? 0) > 0) {
            if let mh = data.multihit, !mh.isEmpty {
                if data.multiaccuracy == true && mh.count == 1 {
                    self.hits = hits ?? mh[0]
                } else if mh.count == 1 {
                    self.hits = mh[0]
                } else if let hits {
                    self.hits = hits
                } else {
                    self.hits = (ability == "Skill Link") ? mh[1] : mh[0] + 1
                }
            }
            self.timesUsedWithMetronome = timesUsedWithMetronome
        }

        self.gen = gen.num
        self.name = data.name
        self.ability = ability
        self.item = item
        self.useZ = useZ
        self.useMax = useMax
        self.bp = data.basePower

        // Typeless-damage moves (Struggle; gen1-4 Future Sight/Doom Desire).
        let did = data.id
        let typeless = ((gen.num == 0 || gen.num >= 2) && did == "struggle")
            || ((gen.num > 0 && gen.num <= 4) && (did == "futuresight" || did == "doomdesire"))
        self.type = typeless ? .typeless : data.type
        self.category = data.category
            ?? ((gen.num > 0 && gen.num < 4) ? (SPECIAL_TYPES.contains(data.type) ? .special : .physical) : .status)

        let stat = self.category == .special ? "spa" : "atk"
        if let b = data.selfBoosts?[stat], b < 0 { self.dropsStats = abs(b) }

        self.timesUsed = timesUsed ?? 1
        self.secondaries = data.secondaries ?? false
        self.target = data.target ?? "any"
        self.recoil = data.recoil
        self.hasCrashDamage = data.hasCrashDamage ?? false
        self.mindBlownRecoil = data.mindBlownRecoil ?? false
        self.struggleRecoil = data.struggleRecoil ?? false
        self.isCrit = isCrit || (data.willCrit ?? false)
            || (gen.num == 1 && ["crabhammer", "razorleaf", "slash", "karatechop"].contains(did))
        self.isStellarFirstUse = isStellarFirstUse
        self.drain = data.drain
        self.flags = data.flags ?? [:]
        self.priority = data.priority ?? 0
        self.ignoreDefensive = data.ignoreDefensive ?? false
        self.overrideOffensiveStat = data.overrideOffensiveStat
        self.overrideDefensiveStat = data.overrideDefensiveStat
        self.overrideOffensivePokemon = data.overrideOffensivePokemon
        self.overrideDefensivePokemon = data.overrideDefensivePokemon
        self.breaksProtect = data.breaksProtect ?? false
        self.isZ = data.isZ ?? false
        self.isMax = data.isMax ?? false
        self.multiaccuracy = data.multiaccuracy ?? false

        if self.bp == 0 && ["return", "frustration", "pikapapow", "veeveevolley"].contains(did) {
            self.bp = 102
        }
    }

    /// Field-by-field copy for `calculate`'s defensive clone.
    private init(clone m: ShowdownMove) {
        gen = m.gen; name = m.name; originalName = m.originalName; ability = m.ability
        item = m.item; useZ = m.useZ; useMax = m.useMax; hits = m.hits
        timesUsed = m.timesUsed; timesUsedWithMetronome = m.timesUsedWithMetronome
        bp = m.bp; type = m.type; category = m.category; flags = m.flags
        secondaries = m.secondaries; target = m.target; recoil = m.recoil
        hasCrashDamage = m.hasCrashDamage; mindBlownRecoil = m.mindBlownRecoil
        struggleRecoil = m.struggleRecoil; isCrit = m.isCrit
        isStellarFirstUse = m.isStellarFirstUse; drain = m.drain; priority = m.priority
        dropsStats = m.dropsStats; ignoreDefensive = m.ignoreDefensive
        overrideOffensiveStat = m.overrideOffensiveStat
        overrideDefensiveStat = m.overrideDefensiveStat
        overrideOffensivePokemon = m.overrideOffensivePokemon
        overrideDefensivePokemon = m.overrideDefensivePokemon
        breaksProtect = m.breaksProtect; isZ = m.isZ; isMax = m.isMax
        multiaccuracy = m.multiaccuracy
    }

    func clone() -> ShowdownMove { ShowdownMove(clone: self) }

    func named(_ names: String...) -> Bool { names.contains(name) }
    func hasType(_ types: ShowdownType?...) -> Bool { types.contains(type) }
    func hasFlag(_ flag: String) -> Bool { (flags[flag] ?? 0) != 0 }
}

// MARK: - Pokemon (pokemon.ts)

/// Reference type: `check*`/`computeFinalStats` mutate boosts/stats/types in place.
final class ShowdownPokemon {
    var gen: Int
    var name: String
    var species: ShowdownSpecies
    var types: [ShowdownType]
    var weightkg: Double
    var level: Int
    var gender: String?
    var ability: String?
    var abilityOn: Bool
    var isDynamaxed: Bool
    var dynamaxLevel: Int?
    var alliesFainted: Int?
    var boostedStat: String?
    var item: String?
    /// Item that was removed by `checkItem` (Klutz/Magic Room); read by Knock Off.
    var disabledItem: String?
    var teraType: ShowdownType?
    var nature: String
    var ivs: ShowdownStats
    var evs: ShowdownStats
    var boosts: ShowdownStats
    var rawStats: ShowdownStats
    var stats: ShowdownStats
    var originalCurHP: Int
    var status: ShowdownStatus
    var toxicCounter: Int
    var moves: [String]

    init(_ gen: ShowdownGeneration, _ name: String, species: ShowdownSpecies,
         level: Int? = nil, ability: String? = nil, abilityOn: Bool = false,
         isDynamaxed: Bool = false, dynamaxLevel: Int? = nil, alliesFainted: Int? = nil,
         boostedStat: String? = nil, item: String? = nil, teraType: ShowdownType? = nil,
         gender: String? = nil, nature: String? = nil,
         ivs: ShowdownStats? = nil, evs: ShowdownStats? = nil, boosts: ShowdownStats = ShowdownStats(),
         curHP: Int? = nil, status: ShowdownStatus = .none, toxicCounter: Int = 0,
         moves: [String] = []) {
        self.species = species
        self.gen = gen.num
        self.name = name
        self.types = species.types
        self.level = gen.num == 0 ? 50 : (level ?? 100)
        self.gender = gender ?? species.gender ?? "M"
        self.ability = ability ?? species.abilities.first
        self.abilityOn = abilityOn
        self.isDynamaxed = isDynamaxed
        self.dynamaxLevel = isDynamaxed ? (dynamaxLevel ?? 10) : nil
        self.weightkg = isDynamaxed ? 0 : species.weightkg
        self.alliesFainted = alliesFainted
        self.boostedStat = boostedStat
        self.teraType = teraType
        self.item = item
        self.nature = nature ?? "Serious"
        // Champions (gen 0) forces IV=31 handling; EVs default 0 for gen0/gen3+.
        let defaultIV = 31
        let defaultEV = (gen.num == 0 || gen.num >= 3) ? 0 : 252
        self.ivs = gen.num == 0 ? ShowdownStats(hp: 31, atk: 31, def: 31, spa: 31, spd: 31, spe: 31)
                                : (ivs ?? ShowdownStats(hp: defaultIV, atk: defaultIV, def: defaultIV, spa: defaultIV, spd: defaultIV, spe: defaultIV))
        self.evs = evs ?? ShowdownStats(hp: defaultEV, atk: defaultEV, def: defaultEV, spa: defaultEV, spd: defaultEV, spe: defaultEV)
        self.boosts = boosts

        var raw = ShowdownStats()
        for stat in ShowdownStat.allCases {
            raw[stat] = ShowdownStatsCalc.calcStat(
                gen: gen.num, stat: stat, base: species.baseStats[stat],
                iv: self.ivs[stat], ev: self.evs[stat], level: self.level, nature: self.nature)
        }
        self.rawStats = raw
        self.stats = raw

        if let curHP, curHP <= raw.hp { self.originalCurHP = curHP } else { self.originalCurHP = raw.hp }
        self.status = status
        self.toxicCounter = toxicCounter
        self.moves = moves
    }

    /// Field-by-field copy for `calculate`'s defensive clone and Parental Bond's
    /// child (every stored property is a value type, so this is a deep copy).
    private init(clone p: ShowdownPokemon) {
        gen = p.gen; name = p.name; species = p.species; types = p.types
        weightkg = p.weightkg; level = p.level; gender = p.gender
        ability = p.ability; abilityOn = p.abilityOn; isDynamaxed = p.isDynamaxed
        dynamaxLevel = p.dynamaxLevel; alliesFainted = p.alliesFainted
        boostedStat = p.boostedStat; item = p.item; disabledItem = p.disabledItem
        teraType = p.teraType; nature = p.nature; ivs = p.ivs; evs = p.evs
        boosts = p.boosts; rawStats = p.rawStats; stats = p.stats
        originalCurHP = p.originalCurHP; status = p.status
        toxicCounter = p.toxicCounter; moves = p.moves
    }

    func clone() -> ShowdownPokemon { ShowdownPokemon(clone: self) }

    func maxHP(original: Bool = false) -> Int {
        if !original, isDynamaxed, species.baseStats.hp != 1, let dl = dynamaxLevel {
            return Int(floor(Double(rawStats.hp * (150 + 5 * dl)) / 100.0))
        }
        return rawStats.hp
    }

    func curHP(original: Bool = false) -> Int {
        if !original, isDynamaxed, species.baseStats.hp != 1, let dl = dynamaxLevel {
            return Int(ceil(Double(originalCurHP * (150 + 5 * dl)) / 100.0))
        }
        return originalCurHP
    }

    func named(_ names: String...) -> Bool { names.contains(name) }
    func hasAbility(_ abilities: String...) -> Bool { ability.map { abilities.contains($0) } ?? false }
    func hasItem(_ items: String...) -> Bool { item.map { items.contains($0) } ?? false }
    func hasStatus(_ statuses: ShowdownStatus...) -> Bool { status != .none && statuses.contains(status) }

    func hasType(_ query: ShowdownType...) -> Bool {
        for t in query {
            if let tera = teraType, tera != .stellar {
                if tera == t { return true }
            } else if types.contains(t) {
                return true
            }
        }
        return false
    }

    /// Ignores Tera type.
    func hasOriginalType(_ query: ShowdownType...) -> Bool { query.contains { types.contains($0) } }

    /// Auto-forme (mega via held "ite" stone, orbs, Relic Song, Dragon Ascent).
    static func getForme(_ gen: ShowdownGeneration, _ speciesName: String,
                         item: String? = nil, moveName: String? = nil) -> String {
        guard let species = gen.species(toID(speciesName)), let formes = species.otherFormes else {
            return speciesName
        }
        var i = 0
        if let item, (item.contains("ite") && !item.contains("ite Y"))
            || (speciesName == "Groudon" && item == "Red Orb")
            || (speciesName == "Kyogre" && item == "Blue Orb")
            || (moveName == "Relic Song" && speciesName == "Meloetta")
            || (speciesName == "Rayquaza" && moveName == "Dragon Ascent") {
            i = 1
        } else if let item, item.contains("ite Y") {
            i = 2
        } else if moveName == "Relic Song" && speciesName == "Meloetta" {
            i = 1
        } else if speciesName == "Rayquaza" && moveName == "Dragon Ascent" {
            i = 1
        }
        return i != 0 ? (formes.indices.contains(i - 1) ? formes[i - 1] : species.name) : species.name
    }
}
