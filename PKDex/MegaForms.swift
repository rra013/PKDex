//
//  MegaForms.swift
//  PKDex
//
//  Every Mega Evolution the app knows. The forms themselves are data, in
//  `mega_forms.json`: adding a Mega is an entry there, plus a `HeldItem`
//  case if its stone is new.
//

import Foundation

/// Static description of a Pokemon's Mega form: post-evolution stats, types, and ability.
/// HP is intentionally omitted — no canonical Mega Evolution changes HP, so the base
/// species' HP stat carries over.
nonisolated struct MegaForm: Equatable, Sendable {
    let speciesKey: String      // Normalized lowercase species name, e.g. "charizard"
    let stone: HeldItem?        // nil for a move-triggered form (Mega Rayquaza)
    let requiresMove: String?   // Normalized move name; nil unless move-triggered
    let displayName: String     // "Mega Charizard Y"
    let type1: String
    let type2: String?
    let baseAtk: Int
    let baseDef: Int
    let baseSpAtk: Int
    let baseSpDef: Int
    let baseSpeed: Int
    let ability: String         // Ability ID matching computeAbilityModifiers keys
}

nonisolated enum MegaForms {

    /// Returns the Mega form a participant is eligible to transform into, or nil if it
    /// doesn't qualify (wrong species, wrong stone, or missing the required move).
    /// Uses the same normalization as `BattleSimSeed.normalize` so PokeAPI's
    /// "charizard" matches the table's "charizard" regardless of casing/hyphens.
    static func form(forSpecies species: String,
                     heldItem: HeldItem,
                     moveNames: [String]) -> MegaForm? {
        let s = BattleSimSeed.normalize(species)

        // A form triggered by a move (Mega Rayquaza, by Dragon Ascent) needs
        // no stone, only the move.
        if let byMove = moveTriggered.first(where: { $0.speciesKey == s }) {
            let knowsMove = moveNames.contains { BattleSimSeed.normalize($0) == byMove.requiresMove }
            return knowsMove ? byMove : nil
        }

        return all.first { $0.speciesKey == s && $0.stone == heldItem }
    }

    /// Every Mega triggered by holding its stone, from `mega_forms.json`.
    static var all: [MegaForm] { table.byStone }

    /// Megas triggered by knowing a move instead of holding a stone: Mega
    /// Rayquaza, by Dragon Ascent.
    static var moveTriggered: [MegaForm] { table.byMove }

    // MARK: Loading

    /// The forms, split by trigger. Loaded once, on first use.
    private static let table: (byStone: [MegaForm], byMove: [MegaForm]) = {
        guard let url = Bundle.main.url(forResource: "mega_forms", withExtension: "json") else {
            print("[MegaForms] missing bundle resource: mega_forms.json")
            return ([], [])
        }
        do {
            let forms = try decode(Data(contentsOf: url))
            return (forms.filter { $0.stone != nil }, forms.filter { $0.stone == nil })
        } catch {
            print("[MegaForms] failed to read mega_forms.json: \(error)")
            return ([], [])
        }
    }()

    enum LoadError: Error, Equatable {
        /// A form's stone isn't a `HeldItem` case, which a new stone needs.
        case unknownStone(form: String, stone: String)
        /// A form has neither a stone nor a required move, so nothing triggers it.
        case noTrigger(form: String)
    }

    /// The forms in a `mega_forms.json` file, in file order. Strict: one
    /// bad entry fails the whole file, and `MegaFormsTests` checks the
    /// bundled one loads.
    static func decode(_ data: Data) throws -> [MegaForm] {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(MegaFormsFile.self, from: data).forms.map { entry in
            var stone: HeldItem?
            if let name = entry.stone {
                guard let item = HeldItem(rawValue: name) else {
                    throw LoadError.unknownStone(form: entry.displayName, stone: name)
                }
                stone = item
            } else if entry.requiresMove == nil {
                throw LoadError.noTrigger(form: entry.displayName)
            }
            return MegaForm(speciesKey: entry.speciesKey, stone: stone,
                            requiresMove: entry.requiresMove, displayName: entry.displayName,
                            type1: entry.type1, type2: entry.type2,
                            baseAtk: entry.baseStats.atk, baseDef: entry.baseStats.def,
                            baseSpAtk: entry.baseStats.spa, baseSpDef: entry.baseStats.spd,
                            baseSpeed: entry.baseStats.spe, ability: entry.ability)
        }
    }
}

/// `mega_forms.json` as written; see its `about` field. `origin` and the
/// file's notes are for people and aren't read.
nonisolated private struct MegaFormsFile: Decodable, Sendable {
    let forms: [Entry]

    struct Entry: Decodable, Sendable {
        let speciesKey: String
        let displayName: String
        let stone: String?
        let requiresMove: String?
        let type1: String
        let type2: String?
        let baseStats: BaseStats
        let ability: String
    }

    struct BaseStats: Decodable, Sendable {
        let atk: Int, def: Int, spa: Int, spd: Int, spe: Int
    }
}
