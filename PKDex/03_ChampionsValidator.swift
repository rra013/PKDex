//
//  ChampionsValidator.swift
//  PKReference
//
//  Swift port of pokemon-llm-training/scripts/validate_champions.py.
//
//  Validates a generated Pokemon set against Pokemon Champions Regulation
//  M-A rules. Returns a list of Violations categorized by severity:
//  legality violations (mandatory fixes) and coherence violations (the set
//  is technically legal but is contradictory, e.g. Adamant nature on a set
//  with only special moves).
//
//  Bundled with:
//    - champions-m-a.json       (legal species, items, abilities)
//    - champions-m-a-learnsets.json  (per-species legal move pools)
//
//  Place both in the app bundle and load via Bundle.main.url(forResource:).
//

import Foundation

// MARK: - Public Types

public struct Violation: Equatable {
    public let category: Category
    public let message: String

    public enum Category: String, Equatable {
        // Hard legality — the set cannot be used
        case illegalSpecies        = "illegal_species"
        case illegalItem           = "illegal_item"
        case illegalAbility        = "illegal_ability"
        case illegalMoves          = "illegal_moves"
        case illegalForm           = "illegal_form"
        case wrongMegaStone        = "wrong_mega_stone"
        case statPointsOverCap     = "stat_points_over_cap"
        case statPointsPerStatOver = "stat_points_per_stat_over"
        case statPointsMalformed   = "stat_points_malformed"
        case wrongTeamSize         = "wrong_team_size"
        case missingSpecies        = "missing_species"
        case missingLearnset       = "missing_learnset"
        case malformedMoves        = "malformed_moves"
        case wrongMoveCount        = "wrong_move_count"
        case speciesClause         = "species_clause"
        case teraNotAllowed        = "tera_not_allowed"
        case evFormatUsed          = "ev_format_used"

        // Coherence — set is legal but contradictory
        case incoherentNature      = "incoherent_nature"
        case choiceSetupConflict   = "choice_setup_conflict"
        case wastedStatPoints      = "wasted_stat_points"

        public var isLegality: Bool {
            switch self {
            case .incoherentNature, .choiceSetupConflict, .wastedStatPoints:
                return false
            default:
                return true
            }
        }
    }
}

/// The validator. Load once at app launch (it parses ~600 KB of JSON) and
/// reuse for all validation calls.
public final class ChampionsValidator {
    public let speciesWhitelist: Set<String>
    public let itemWhitelist: Set<String>
    public let abilityWhitelist: Set<String>
    public let megaStoneToSpecies: [String: String]  // "Gardevoirite" → "Gardevoir"
    public let speciesToMegaStone: [String: String]  // reverse map
    public let learnsets: [String: Set<String>]      // species → legal moves
    public let speciesAbilities: [String: Set<String>] // species → legal abilities
    public let setupMoves: Set<String>
    public let choiceItems: Set<String>
    public let scarfItem: String = "Choice Scarf"

    public static let statPointTotalCap = 66
    public static let statPointPerStatCap = 32
    public static let requiredMoveCount = 4
    public static let requiredTeamSize = 6

    // MARK: Loading

    public init?(legalityURL: URL, learnsetsURL: URL) {
        // legality JSON (scraped format): {
        //   "species_whitelist": [...],
        //   "items_whitelist": [...], "berries_whitelist": [...],
        //   "mega_stones": {"Abomasnow": "Abomasite", ...}   // species → stone
        // }
        guard let legalityData = try? Data(contentsOf: legalityURL),
              let legality = try? JSONSerialization.jsonObject(with: legalityData)
                as? [String: Any]
        else { return nil }

        guard let species = legality["species_whitelist"] as? [String],
              let items = legality["items_whitelist"] as? [String],
              let speciesToStoneRaw = legality["mega_stones"] as? [String: String]
        else { return nil }

        let berries = (legality["berries_whitelist"] as? [String]) ?? []

        self.speciesWhitelist = Set(species)
        // Items pool = legal items + berries + mega stones. Mega stones must
        // pass the per-item whitelist check before the species-match check.
        var itemSet = Set(items)
        itemSet.formUnion(berries)
        itemSet.formUnion(speciesToStoneRaw.values)
        self.itemWhitelist = itemSet

        self.speciesToMegaStone = speciesToStoneRaw
        self.megaStoneToSpecies = Dictionary(
            uniqueKeysWithValues: speciesToStoneRaw.map { ($1, $0) }
        )

        // learnsets JSON (scraped format): {
        //   "species": {
        //     "Abomasnow": {
        //       "name": ..., "abilities": [...], "moves": [...],
        //       "megas": [{"name": "Mega Abomasnow", "abilities": [...], ...}],
        //       "alternate_forms": [{"name": ..., "abilities": [...], "moves": [...]}]
        //     }, ...
        //   },
        //   "move_details": ...
        // }
        guard let learnsetData = try? Data(contentsOf: learnsetsURL),
              let learnsetRoot = try? JSONSerialization.jsonObject(
                with: learnsetData) as? [String: Any],
              let speciesEntries = learnsetRoot["species"]
                as? [String: [String: Any]]
        else { return nil }

        var learnsets: [String: Set<String>] = [:]
        var speciesAbilities: [String: Set<String>] = [:]
        var abilityUnion: Set<String> = []

        for (name, entry) in speciesEntries {
            let moves = (entry["moves"] as? [String]) ?? []
            let abilities = (entry["abilities"] as? [String]) ?? []
            learnsets[name] = Set(moves)
            speciesAbilities[name] = Set(abilities)
            abilityUnion.formUnion(abilities)

            // Mega forms inherit the base learnset but have their own
            // ability pool. Register them under the mega name as well so
            // the model can output either base or mega species safely.
            if let megas = entry["megas"] as? [[String: Any]] {
                for mega in megas {
                    guard let megaName = mega["name"] as? String else { continue }
                    let megaAbilities = (mega["abilities"] as? [String]) ?? []
                    learnsets[megaName] = Set(moves)
                    speciesAbilities[megaName] = Set(megaAbilities)
                    abilityUnion.formUnion(megaAbilities)
                }
            }
        }

        self.learnsets = learnsets
        self.speciesAbilities = speciesAbilities
        // The legality JSON only lists banned abilities (often empty), so
        // derive the whitelist from the union of every species's legal pool.
        self.abilityWhitelist = abilityUnion

        // The scraped legality file doesn't enumerate setup moves or choice
        // items. Champions M-A only legalizes Choice Scarf among choice
        // items (Band/Specs banned), so that list is one-element. Setup
        // moves are a stable competitive list — hardcoding is fine, they
        // change only when new generations ship.
        self.choiceItems = ["Choice Scarf"]
        self.setupMoves = [
            "Swords Dance", "Dragon Dance", "Nasty Plot", "Calm Mind",
            "Bulk Up", "Quiver Dance", "Shell Smash", "Geomancy",
            "Tail Glow", "Coil", "Curse", "Belly Drum", "Iron Defense",
            "Cosmic Power", "Agility", "Rock Polish", "Autotomize",
            "Growth", "Work Up", "Howl", "Hone Claws", "Charge",
            "Stockpile", "Sharpen", "Acid Armor", "Barrier", "Meditate",
            "Amnesia", "Cotton Guard", "No Retreat", "Clangorous Soul",
            "Victory Dance", "Shift Gear", "Magnet Rise", "Power-Up Punch",
        ]
    }

    /// Convenience initializer that loads from the app bundle for the
    /// currently-active regulation (`ChampionsRegulation.current`).
    public convenience init?() {
        self.init(regulation: ChampionsRegulation.current)
    }

    /// Convenience initializer that loads the JSON pair for an explicit
    /// regulation. Use this when validating against a non-current format
    /// (e.g. saved teams that were built under M-A while M-B is now active).
    /// Internal access: `ChampionsRegulation` is module-internal, so this
    /// initializer matches.
    convenience init?(regulation: ChampionsRegulation) {
        guard let lURL = Bundle.main.url(
                forResource: regulation.bundleResourceName, withExtension: "json"),
              let mURL = Bundle.main.url(
                forResource: regulation.learnsetBundleResourceName, withExtension: "json")
        else { return nil }
        self.init(legalityURL: lURL, learnsetsURL: mURL)
    }

    // MARK: Validation entry points

    /// Validate a single set. Returns all violations found.
    public func validate(set: PokemonSet) -> [Violation] {
        var v: [Violation] = []
        validateSpecies(set, into: &v)
        validateItem(set, into: &v)
        validateAbility(set, into: &v)
        validateMoves(set, into: &v)
        validateStatPoints(set, into: &v)
        validateMegaConsistency(set, into: &v)
        validateCoherence(set, into: &v)
        return v
    }

    /// Validate a six-member team. Catches team-level rules in addition to
    /// per-set rules.
    public func validate(team: [PokemonSet]) -> [Violation] {
        var v: [Violation] = []
        if team.count != Self.requiredTeamSize {
            v.append(.init(category: .wrongTeamSize,
                message: "Team has \(team.count) members, expected " +
                         "\(Self.requiredTeamSize)"))
        }
        // Species clause: no duplicate species
        var seen = Set<String>()
        for set in team {
            if seen.contains(set.species) {
                v.append(.init(category: .speciesClause,
                    message: "Duplicate species in team: \(set.species)"))
            }
            seen.insert(set.species)
        }
        for set in team {
            v.append(contentsOf: validate(set: set))
        }
        return v
    }

    // MARK: - Individual rule checks

    private func validateSpecies(_ s: PokemonSet, into v: inout [Violation]) {
        if s.species.isEmpty {
            v.append(.init(category: .missingSpecies, message: "Species is empty"))
            return
        }
        if !speciesWhitelist.contains(s.species) {
            v.append(.init(category: .illegalSpecies,
                message: "Species '\(s.species)' is not legal in Regulation M-A"))
        }
    }

    private func validateItem(_ s: PokemonSet, into v: inout [Violation]) {
        guard let item = s.item, !item.isEmpty else { return }
        if !itemWhitelist.contains(item) {
            v.append(.init(category: .illegalItem,
                message: "Item '\(item)' is not legal in Regulation M-A"))
        }
    }

    private func validateAbility(_ s: PokemonSet, into v: inout [Violation]) {
        guard !s.ability.isEmpty else {
            v.append(.init(category: .illegalAbility,
                message: "Ability is empty"))
            return
        }
        if !abilityWhitelist.contains(s.ability) {
            v.append(.init(category: .illegalAbility,
                message: "Ability '\(s.ability)' is not in the legal list"))
            return
        }
        // Species-specific check
        if let legalForSpecies = speciesAbilities[s.species],
           !legalForSpecies.contains(s.ability) {
            v.append(.init(category: .illegalAbility,
                message: "Ability '\(s.ability)' is not legal on \(s.species). " +
                         "Legal: \(legalForSpecies.sorted().joined(separator: ", "))"))
        }
    }

    private func validateMoves(_ s: PokemonSet, into v: inout [Violation]) {
        if s.moves.count != Self.requiredMoveCount {
            v.append(.init(category: .wrongMoveCount,
                message: "Has \(s.moves.count) moves, expected " +
                         "\(Self.requiredMoveCount)"))
        }
        // Empty / duplicate detection
        var seen = Set<String>()
        for move in s.moves {
            if move.isEmpty {
                v.append(.init(category: .malformedMoves,
                    message: "Move slot is empty"))
                continue
            }
            if seen.contains(move) {
                v.append(.init(category: .malformedMoves,
                    message: "Duplicate move: \(move)"))
            }
            seen.insert(move)
        }
        // Learnset check
        guard let legalMoves = learnsets[s.species] else {
            v.append(.init(category: .missingLearnset,
                message: "No learnset data for \(s.species)"))
            return
        }
        let illegal = s.moves.filter { !$0.isEmpty && !legalMoves.contains($0) }
        if !illegal.isEmpty {
            v.append(.init(category: .illegalMoves,
                message: "\(s.species) cannot learn: " +
                         illegal.joined(separator: ", ")))
        }
    }

    private func validateStatPoints(_ s: PokemonSet, into v: inout [Violation]) {
        // The training pipeline normalized "evs" → "stat_points" early. If a
        // generation slips through with the old "ev" naming, flag it.
        if s.usedEVFormat {
            v.append(.init(category: .evFormatUsed,
                message: "Set uses old 'evs' format; should be 'stat_points'"))
        }

        let sp = s.statPoints
        let total = sp.hp + sp.atk + sp.def + sp.spa + sp.spd + sp.spe
        if total > Self.statPointTotalCap {
            v.append(.init(category: .statPointsOverCap,
                message: "Stat point total is \(total), cap is " +
                         "\(Self.statPointTotalCap)"))
        }
        let allStats: [(String, Int)] = [
            ("hp", sp.hp), ("atk", sp.atk), ("def", sp.def),
            ("spa", sp.spa), ("spd", sp.spd), ("spe", sp.spe),
        ]
        for (name, value) in allStats {
            if value < 0 {
                v.append(.init(category: .statPointsMalformed,
                    message: "\(name) stat points is negative: \(value)"))
            }
            if value > Self.statPointPerStatCap {
                v.append(.init(category: .statPointsPerStatOver,
                    message: "\(name)=\(value) exceeds per-stat cap " +
                             "(\(Self.statPointPerStatCap))"))
            }
        }
    }

    private func validateMegaConsistency(_ s: PokemonSet, into v: inout [Violation]) {
        guard let item = s.item, !item.isEmpty else { return }
        guard let megaTarget = megaStoneToSpecies[item] else { return }
        // Item is a mega stone — must be held by the BASE species. The mega-form
        // name (e.g. "Charizard-Y") is what the mon transforms into mid-battle,
        // not what it's built as. Accept either the recorded mega-form species
        // OR any base species that's listed in MegaForms.all as the stone's owner.
        let normSpecies = BattleSimSeed.normalize(s.species)
        let allowedBaseKeys = Set(MegaForms.all
            .filter { $0.stone?.rawValue == item }
            .map { $0.speciesKey })
        let matchesBase = allowedBaseKeys.contains(normSpecies)
        let matchesMegaForm = (megaTarget == s.species)
        if !matchesBase && !matchesMegaForm {
            let baseDisplay = allowedBaseKeys.sorted().joined(separator: ", ")
            v.append(.init(category: .wrongMegaStone,
                message: "\(item) only works on \(baseDisplay), not \(s.species)"))
        }
    }

    private func validateCoherence(_ s: PokemonSet, into v: inout [Violation]) {
        // Determine move category balance for nature coherence check
        // (we need a move→category map; if not bundled, skip this check)
        // For coherence we use heuristics on known move-name patterns + the
        // small bundled `move_categories.json` if present.
        let categories = MoveCategories.shared
        let cats = s.moves.compactMap { categories.category(for: $0) }
        let physicalCount = cats.filter { $0 == .physical }.count
        let specialCount = cats.filter { $0 == .special }.count
        let attackingCount = physicalCount + specialCount

        // 1. Nature coherence
        if attackingCount > 0 {
            switch s.nature {
            case "Adamant", "Jolly", "Brave":
                // +Atk natures: should have at least 1 physical move
                if physicalCount == 0 && specialCount > 0 {
                    v.append(.init(category: .incoherentNature,
                        message: "Nature \(s.nature) boosts Attack but set has " +
                                 "only special moves"))
                }
            case "Modest", "Timid", "Quiet":
                if specialCount == 0 && physicalCount > 0 {
                    v.append(.init(category: .incoherentNature,
                        message: "Nature \(s.nature) boosts Sp.Atk but set has " +
                                 "only physical moves"))
                }
            default:
                break  // neutral / defensive natures don't conflict
            }
        }

        // 2. Choice item + setup move conflict
        if let item = s.item, choiceItems.contains(item) {
            let setupInSet = s.moves.filter { setupMoves.contains($0) }
            if !setupInSet.isEmpty {
                v.append(.init(category: .choiceSetupConflict,
                    message: "Choice item \(item) locks moves; can't use setup " +
                             "moves: \(setupInSet.joined(separator: ", "))"))
            }
        }

        // 3. Wasted stat points: physical attacker with high SpAtk investment
        // (and vice versa), or speed investment when paired with Trick Room
        let sp = s.statPoints
        if attackingCount > 0 {
            if physicalCount > 0 && specialCount == 0 && sp.spa > 4 {
                v.append(.init(category: .wastedStatPoints,
                    message: "Set is all-physical but has \(sp.spa) SpAtk " +
                             "stat points invested"))
            }
            if specialCount > 0 && physicalCount == 0 && sp.atk > 4 {
                v.append(.init(category: .wastedStatPoints,
                    message: "Set is all-special but has \(sp.atk) Atk stat " +
                             "points invested"))
            }
        }
        if s.moves.contains("Trick Room") && sp.spe > 4 {
            v.append(.init(category: .wastedStatPoints,
                message: "Set runs Trick Room but has \(sp.spe) Speed stat " +
                         "points invested"))
        }
    }
}

// MARK: - PokemonSet model (parses model output)

public struct PokemonSet: Equatable {
    public var species: String       // serialized as "name" in the training schema
    public var ability: String
    public var item: String?
    public var nature: String
    public var teraType: String?     // unused in Champions M-A but kept for forward-compat
    public var moves: [String]
    public var statPoints: StatPoints
    public var role: String?         // training schema includes this
    /// True if the source JSON used the old "evs" key. Flagged as a soft
    /// violation so we can detect and fix during training drift.
    public var usedEVFormat: Bool = false

    public struct StatPoints: Equatable {
        public var hp: Int, atk: Int, def: Int, spa: Int, spd: Int, spe: Int

        public static let zero = StatPoints(hp: 0, atk: 0, def: 0,
                                             spa: 0, spd: 0, spe: 0)
    }

    /// Parse a Pokemon set from the JSON the model emits. Returns nil if
    /// the JSON is fundamentally malformed (not just missing fields — those
    /// are caught by the validator).
    public static func parse(_ jsonString: String) -> PokemonSet? {
        guard let data = jsonString.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data)
                as? [String: Any]
        else { return nil }
        return parse(obj)
    }

    public static func parse(_ obj: [String: Any]) -> PokemonSet? {
        var sp = StatPoints.zero
        var usedEV = false

        // Stat points: try "stat_points" first (correct), fall back to "evs"
        if let spDict = obj["stat_points"] as? [String: Any] {
            sp = readStatPoints(spDict)
        } else if let evs = obj["evs"] as? [String: Any] {
            sp = readStatPoints(evs)
            usedEV = true
        }

        let moves = (obj["moves"] as? [String]) ?? []
        // Training schema uses "name" as the species key. Fall back to
        // "species" for forward compatibility if the schema ever changes.
        let species = (obj["name"] as? String)
                   ?? (obj["species"] as? String) ?? ""
        let ability = (obj["ability"] as? String) ?? ""
        let nature = (obj["nature"] as? String) ?? ""
        let item = obj["item"] as? String
        let tera = obj["tera_type"] as? String ?? obj["tera"] as? String
        let role = obj["role"] as? String

        return PokemonSet(
            species: species, ability: ability, item: item,
            nature: nature, teraType: tera, moves: moves,
            statPoints: sp, role: role, usedEVFormat: usedEV
        )
    }

    private static func readStatPoints(_ dict: [String: Any]) -> StatPoints {
        func read(_ key: String) -> Int {
            if let i = dict[key] as? Int { return i }
            if let d = dict[key] as? Double { return Int(d) }
            return 0
        }
        return StatPoints(
            hp: read("hp"), atk: read("atk"), def: read("def"),
            spa: read("spa"), spd: read("spd"), spe: read("spe")
        )
    }

    /// Serialize for display or for sending to the validator-feedback retry.
    public func toJSONString() -> String {
        var dict: [String: Any] = [
            "name": species,
            "ability": ability,
            "nature": nature,
            "moves": moves,
            "stat_points": [
                "hp": statPoints.hp, "atk": statPoints.atk, "def": statPoints.def,
                "spa": statPoints.spa, "spd": statPoints.spd, "spe": statPoints.spe,
            ],
        ]
        if let item = item, !item.isEmpty { dict["item"] = item }
        if let role = role, !role.isEmpty { dict["role"] = role }
        let data = (try? JSONSerialization.data(
            withJSONObject: dict, options: [.prettyPrinted, .sortedKeys])) ?? Data()
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    // MARK: - Stat Point Post-Processing
    //
    // The 4-bit quantized model has a recurring failure mode where it produces
    // a slightly over-budget SP allocation (most commonly 68 instead of 66)
    // and refuses to fix it even with explicit feedback. Rather than ship a
    // marked-invalid set to the user, we clip small overages by reducing the
    // smallest non-zero stat(s). We cap clipping at overage ≤ 8: anything
    // worse suggests real model breakdown and should surface as a real
    // violation rather than be papered over.
    //
    // Under-budget sets (total < 66) are legal — the rule is a cap. We
    // expose `unspentStatPoints` so the UI can inform users they have
    // free SP to allocate.

    /// Maximum overage we'll silently clip. Past this, leave the set alone
    /// and let the validator complain.
    public static let maxSafeClipOverage = 8

    /// Total stat-point cost across all six stats.
    public var statPointTotal: Int {
        statPoints.hp + statPoints.atk + statPoints.def +
        statPoints.spa + statPoints.spd + statPoints.spe
    }

    /// Stat points remaining under the 66-cap. Negative means over-budget.
    public var unspentStatPoints: Int {
        ChampionsValidator.statPointTotalCap - statPointTotal
    }

    /// Result of an in-place clip operation.
    public struct ClipResult: Equatable {
        public let didClip: Bool
        /// Human-readable description of what changed (or why nothing did).
        public let message: String?
        public init(didClip: Bool, message: String?) {
            self.didClip = didClip
            self.message = message
        }
    }

    /// Priority order for tie-breaking when multiple stats share the
    /// smallest value. Defensive/utility stats are cut first so that
    /// offensive stats stay intact — matters for "bulky" sets where the
    /// model often adds a spurious +2 to a non-load-bearing stat.
    public static let clipOrder: [WritableKeyPath<StatPoints, Int>] = [
        \StatPoints.hp, \StatPoints.def, \StatPoints.spd,
        \StatPoints.spe, \StatPoints.spa, \StatPoints.atk,
    ]

    private static let clipKeyNames: [WritableKeyPath<StatPoints, Int>: String] = [
        \StatPoints.hp: "hp", \StatPoints.atk: "atk", \StatPoints.def: "def",
        \StatPoints.spa: "spa", \StatPoints.spd: "spd", \StatPoints.spe: "spe",
    ]

    /// Bring the set's SP total down to the cap by reducing the smallest
    /// non-zero stat(s). Mutates `self`. Returns a `ClipResult` describing
    /// the action.
    ///
    /// Cascades through multiple stats if a single stat doesn't have enough
    /// budget to absorb the full overage. Cap at `maxSafeClipOverage`; if
    /// the overage exceeds it, leave the set alone and let the validator
    /// surface a real error.
    public mutating func clipStatPointsToCap() -> ClipResult {
        let cap = ChampionsValidator.statPointTotalCap
        let total = statPointTotal
        guard total > cap else {
            return ClipResult(didClip: false, message: nil)
        }
        let overage = total - cap
        guard overage <= Self.maxSafeClipOverage else {
            return ClipResult(didClip: false, message:
                "stat_points total is \(total), exceeds cap by \(overage) " +
                "(> \(Self.maxSafeClipOverage) max safe-clip overage); " +
                "leaving as-is")
        }

        var remaining = overage
        var actions: [String] = []
        while remaining > 0 {
            // Find smallest non-zero across all stats.
            let nonzero = Self.clipOrder.filter { statPoints[keyPath: $0] > 0 }
            guard !nonzero.isEmpty else {
                return ClipResult(didClip: !actions.isEmpty, message:
                    "clip failed: ran out of non-zero stats with " +
                    "\(remaining) SP still to cut")
            }
            let smallestValue = nonzero.map { statPoints[keyPath: $0] }.min()!
            // Among stats at smallest value, take the first in clip order.
            let target = nonzero.first { statPoints[keyPath: $0] == smallestValue }!
            let cut = min(statPoints[keyPath: target], remaining)
            let before = statPoints[keyPath: target]
            statPoints[keyPath: target] -= cut
            remaining -= cut
            let name = Self.clipKeyNames[target] ?? "?"
            actions.append("\(name) \(before)→\(statPoints[keyPath: target]) (-\(cut))")
        }
        return ClipResult(didClip: true, message:
            "stat_points clipped from \(total) to \(cap): " +
            actions.joined(separator: ", "))
    }

    /// Informational note if the set is under-budget. nil when fully
    /// allocated or over-budget (over-budget is handled by clipping or
    /// the validator). Suitable for surfacing in the UI as an info banner.
    public var statPointBudgetNote: String? {
        let unspent = unspentStatPoints
        guard unspent > 0 else { return nil }
        let cap = ChampionsValidator.statPointTotalCap
        return "stat_points total is \(statPointTotal); " +
               "\(unspent) SP unspent (cap is \(cap)). " +
               "You can distribute these freely."
    }
}

// MARK: - Move Categories

/// Loads `move_categories.json` from the bundle (a minimal map of
/// move-name → "physical"/"special"/"status") used by the coherence checks.
/// If the file isn't present, every move is treated as unknown, which
/// disables the nature-coherence and wasted-points checks but does not
/// fail the rest of validation.
public final class MoveCategories {
    public enum Category: String, Equatable {
        case physical, special, status
    }

    public static let shared = MoveCategories()
    private let map: [String: Category]

    private init() {
        guard let url = Bundle.main.url(
                forResource: "move_categories", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let raw = try? JSONSerialization.jsonObject(with: data)
                as? [String: String]
        else {
            self.map = [:]
            return
        }
        self.map = raw.compactMapValues { Category(rawValue: $0) }
    }

    public func category(for move: String) -> Category? {
        map[move]
    }
}
