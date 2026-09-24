//
//  LimitlessTeamImport.swift
//  PKDex
//
//  Turns Limitless tournament decklists into saved spreads and teams. Used
//  by the Tournaments tab's save buttons, and by Team Search.
//
//  Limitless names rarely match the Pokedex. Its display names are
//  "Hisuian Arcanine" and "Indeedee ♀" where PKMNStats has "Arcanine-Hisui"
//  and "Indeedee-Female", and it uses the bare "Maushold" where every row
//  is a form. `LimitlessSpeciesResolver` maps those. Everything after the
//  species goes through the paste importer (`PasteImporter` and
//  `TeamPasteImport.plan`), so tournament saves and paste imports resolve
//  moves, items and natures the same way and get the same unique spread
//  names.
//

import Foundation

// MARK: - Tournament Species Aliases

/// Limitless tournament reports list several form-changing Pokemon under names
/// that don't match the local PKMNStats row exactly:
///   - Shared base name across forms: "Aegislash" → "Aegislash-Shield"/"-Blade"
///   - Canonical English name vs Showdown form: "Eternal Flower Floette" or
///     "Floette" (Champions context) → "Floette-Eternal"
/// This helper expands a Limitless name to a prioritized candidate list so the
/// downloader can find the canonical row. **Aliases take priority over the raw
/// name** because for some species (notably Floette) the raw name resolves to
/// the wrong row — regular Floette and Floette-Eternal are both in the Pokedex
/// but Champions reports always mean the Eternal Flower form.
///
/// Regional forms, gendered forms and default forms don't need entries here;
/// `LimitlessSpeciesResolver` handles them by rule. That includes
/// Basculegion: Limitless labels the female form "Basculegion ♀" (slug
/// "basculegion-f"), so a plain "Basculegion" is the male default form.
nonisolated enum TournamentSpeciesAlias {
    /// Maps a base species name (or canonical English name) to one or more
    /// canonical row names, in priority order. The first hit wins; the raw name
    /// is appended last as a fallback. Keep entries to genuinely ambiguous form
    /// names — anything stored under its own name already round-trips fine.
    static let table: [String: [String]] = [
        "Aegislash":              ["Aegislash-Shield", "Aegislash-Blade"],
        "Floette":                ["Floette-Eternal"],
        "Eternal Flower Floette": ["Floette-Eternal"],
        "Floette-Eternal":        ["Floette-Eternal"],
        "Wishiwashi":             ["Wishiwashi-Solo", "Wishiwashi-School"],
        "Mimikyu":                ["Mimikyu-Disguised", "Mimikyu"],
        "Minior":                 ["Minior-Meteor", "Minior-Red-Meteor"],
        "Morpeko":                ["Morpeko-Full-Belly", "Morpeko"],
        "Eiscue":                 ["Eiscue-Ice", "Eiscue-Noice"],
        "Zacian":                 ["Zacian-Crowned", "Zacian-Hero"],
        "Zamazenta":              ["Zamazenta-Crowned", "Zamazenta-Hero"],
        // The resolver's word rule would pick Kantonian Tauros for this one:
        // the Combat Breed's row name has words the display name lacks.
        "Paldean Tauros":         ["Tauros-Paldea-Combat-Breed"],
    ]

    /// Returns the lookup order for a Limitless name: aliases first (so we
    /// prefer the canonical form-specific row), raw name last as a fallback.
    /// Case-insensitive on the key side. The raw name is always included — if
    /// no alias entry exists, it's the only candidate.
    static func candidates(for rawName: String) -> [String] {
        var result: [String] = []
        for (key, aliases) in table where key.lowercased() == rawName.lowercased() {
            result.append(contentsOf: aliases)
        }
        // Always include the raw name as a final fallback, deduped.
        if !result.contains(where: { $0.lowercased() == rawName.lowercased() }) {
            result.append(rawName)
        }
        return result
    }
}

// MARK: - Species resolver

/// Maps a Limitless species name, and its slug when there is one, to a
/// Pokedex row name. Works on names alone, so it runs on any actor. Tries,
/// in order:
///
/// 1. `TournamentSpeciesAlias` candidates, then the slug ("arcanine-hisui"),
///    then the name, each matched exactly or by word set.
/// 2. The most specific row whose words all appear in the name or slug.
///    Regional adjectives count as region words ("Hisuian" → "hisui") and
///    ♀/♂ or a lone f/m count as "female"/"male". So "Paldean Tauros Blaze
///    Breed" finds Tauros-Paldea-Blaze-Breed, and "Shadow Rider Calyrex"
///    finds Calyrex-Shadow rather than Calyrex.
/// 3. The species' default form, when the name contains its first word and
///    no other species starts with that word. "Maushold" →
///    Maushold-Family-Of-Four, "Indeedee" → Indeedee-Male. This also catches
///    forms the Pokedex doesn't store because they only differ cosmetically:
///    "Low Key Toxtricity" → Toxtricity-Amped.
nonisolated struct LimitlessSpeciesResolver: Sendable {

    struct Entry: Sendable {
        let name: String
        /// PokeAPI's default form for the species (`PKMNStats.isForm` false).
        let isDefaultForm: Bool
    }

    private struct Row: Sendable {
        let name: String
        let words: Set<String>
        let firstWord: String?
        let isDefaultForm: Bool
    }

    private let byID: [ShowdownID: String]
    private let byWordKey: [String: String]
    private let rows: [Row]

    init(_ entries: [Entry]) {
        var byID: [ShowdownID: String] = [:]
        var byWordKey: [String: String] = [:]
        var rows: [Row] = []
        for entry in entries {
            let words = Self.words(entry.name)
            guard !words.isEmpty else { continue }
            // First writer wins, as in `NameIndex`.
            let id = toID(Self.fold(entry.name))
            if byID[id] == nil { byID[id] = entry.name }
            let key = Self.wordKey(words)
            if byWordKey[key] == nil { byWordKey[key] = entry.name }
            rows.append(Row(name: entry.name, words: Set(words),
                            firstWord: words.first, isDefaultForm: entry.isDefaultForm))
        }
        self.byID = byID
        self.byWordKey = byWordKey
        self.rows = rows
    }

    /// The Pokedex row name for a Limitless member, or nil.
    func resolve(name: String, slug: String? = nil) -> String? {
        // 1. Aliases, the slug, the name: exact, then by word set.
        var candidates = TournamentSpeciesAlias.candidates(for: name)
        if let slug, !slug.isEmpty {
            // Just before the name, which is always last: after the aliases,
            // so the slug "floette" can't beat the alias Floette-Eternal.
            candidates.insert(slug, at: candidates.count - 1)
        }
        for candidate in candidates {
            if let hit = byID[toID(Self.fold(candidate))] { return hit }
            if let hit = byWordKey[Self.wordKey(Self.words(candidate))] { return hit }
        }

        var available = Set(Self.words(name))
        if let slug { available.formUnion(Self.words(slug)) }
        guard !available.isEmpty else { return nil }

        // 2. The row with the most words, all of them present. Ties go to
        //    the default form, then to the first row.
        var best: Row?
        for row in rows where row.words.isSubset(of: available) {
            guard let current = best else { best = row; continue }
            if row.words.count > current.words.count
                || (row.words.count == current.words.count
                    && row.isDefaultForm && !current.isDefaultForm) {
                best = row
            }
        }
        if let best { return best.name }

        // 3. The default form of a species the name mentions, only when
        //    exactly one fits: a first word shared across species ("iron",
        //    "tapu", "mr") says nothing about which one.
        let defaults = rows.filter { row in
            row.isDefaultForm && row.firstWord.map(available.contains) == true
        }
        return defaults.count == 1 ? defaults[0].name : nil
    }

    // MARK: Words

    /// Regional adjectives as the region words PokeAPI and Limitless use in
    /// form names ("Hisuian" → "hisui"). Team Search's query parser uses the
    /// same map.
    static let regionWords: [String: String] = [
        "alolan": "alola", "galarian": "galar", "hisuian": "hisui", "paldean": "paldea",
    ]

    private static let wordSubstitutions: [String: String] =
        regionWords.merging(["f": "female", "m": "male"]) { region, _ in region }

    /// Lowercased ASCII words, accents folded, regional adjectives and
    /// gender marks normalized.
    static func words(_ name: String) -> [String] {
        fold(name)
            .replacingOccurrences(of: "♀", with: " female ")
            .replacingOccurrences(of: "♂", with: " male ")
            .split(whereSeparator: { !($0.isASCII && ($0.isLetter || $0.isNumber)) })
            .map { wordSubstitutions[String($0)] ?? String($0) }
    }

    private static func fold(_ name: String) -> String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).lowercased()
    }

    private static func wordKey(_ words: [String]) -> String {
        words.sorted().joined(separator: "|")
    }
}

// MARK: - Importer

/// A save that was refused: one line per name that didn't resolve, in the
/// "no match found for …" format the Tournaments alert shows.
nonisolated struct LimitlessUnmatchedNames: Error, Equatable {
    let lines: [String]
}

/// Resolves Limitless decklist members against the Pokedex and plans what a
/// save creates, without inserting anything. Build it once per screen: it
/// indexes the whole Pokedex and move list.
@MainActor
struct LimitlessTeamImporter {

    private let pasteImporter: PasteImporter
    private let species: LimitlessSpeciesResolver
    private let statsByName: [String: PKMNStats]

    init(allPokemon: [PKMNStats], allMoves: [MoveData]) {
        // No validator: nothing here shows legality, and building one parses
        // ~600 KB of JSON.
        pasteImporter = PasteImporter(allPokemon: allPokemon, allMoves: allMoves,
                                      validator: nil, targetScale: .champions)
        species = LimitlessSpeciesResolver(allPokemon.map {
            LimitlessSpeciesResolver.Entry(name: $0.name, isDefaultForm: !$0.isForm)
        })
        statsByName = Dictionary(allPokemon.map { ($0.name, $0) },
                                 uniquingKeysWith: { first, _ in first })
    }

    // MARK: Resolution

    /// The Pokedex row a member resolves to, or nil.
    func pokemon(for member: LimitlessStanding.TeamMember) -> PKMNStats? {
        species.resolve(name: member.name, slug: member.limitlessID)
            .flatMap { statsByName[$0] }
    }

    /// The species' own spelling of the ability ("psychic-surge") when it has
    /// it, else a hyphenated guess, so the engine's ability handlers (keyed
    /// on "stance-change"-style IDs) still find it.
    private func ability(_ displayName: String?, on stats: PKMNStats?) -> String? {
        guard let displayName, !displayName.isEmpty else { return nil }
        if let hit = stats?.allAbilities.first(where: { toID($0) == toID(displayName) }) {
            return hit
        }
        return displayName.lowercased().replacingOccurrences(of: " ", with: "-")
    }

    /// A member as a paste set, for the paste importer. The species is the
    /// resolved row name, so the importer's own lookup can't pick another
    /// form. Level 50, Champions stat points.
    ///
    /// Limitless doesn't publish stat points. With `predictStats`, the
    /// on-device predictor fills them in, and fills the nature only when
    /// Limitless didn't send one.
    func pasteSet(for member: LimitlessStanding.TeamMember,
                  predictStats: Bool) -> ShowdownPasteSet {
        let stats = pokemon(for: member)
        var set = ShowdownPasteSet(species: stats?.name ?? member.name)
        set.item = member.item
        set.ability = ability(member.ability, on: stats)
        set.nature = member.nature
        set.level = PasteImporter.defaultLevel
        set.teraType = member.tera
        set.moves = member.attacks ?? []
        set.evScale = .champions
        if predictStats, let prediction = StatNaturePredictor.shared.predict(
            name: member.name, item: member.item, ability: member.ability,
            moves: member.attacks ?? [], role: nil   // Limitless doesn't expose role
        ) {
            let points = prediction.statPoints
            set.evs = ShowdownStats(hp: points.hp, atk: points.atk, def: points.def,
                                    spa: points.spa, spd: points.spd, spe: points.spe)
            if set.nature == nil { set.nature = prediction.natureName }
        }
        return set
    }

    /// The paste importer's view of the members, one slot per member in order.
    func preview(_ members: [LimitlessStanding.TeamMember],
                 predictStats: Bool) -> ImportPreview {
        var parsed = ParsedPaste()
        parsed.sets = members.map { pasteSet(for: $0, predictStats: predictStats) }
        parsed.detectedScale = .champions
        return pasteImporter.preview(parsed)
    }

    /// "no match found for X" per unresolved species and "no match found for
    /// move X on Y" per unresolved move, in member order, using Limitless's
    /// spelling so the names can go straight into the alias table.
    static func unmatchedLines(_ preview: ImportPreview,
                               members: [LimitlessStanding.TeamMember]) -> [String] {
        var lines: [String] = []
        for (slot, member) in zip(preview.slots, members) {
            for issue in slot.issues {
                switch issue {
                case .speciesUnresolved:
                    lines.append("no match found for \(member.name)")
                case .moveUnresolved(_, let raw, _):
                    lines.append("no match found for move \(raw) on \(member.name)")
                default:
                    break
                }
            }
        }
        return lines
    }

    // MARK: Plans

    /// What "Save Full Team" creates. Every species and move must resolve,
    /// or nothing is saved: a team missing a member or a move is easy to
    /// miss later. Spreads are named "<team> · <species>". An empty decklist
    /// fails with no lines.
    func planTeam(_ members: [LimitlessStanding.TeamMember], teamName: String,
                  taken: Set<String>, predictStats: Bool)
        -> Result<TeamImportPlan, LimitlessUnmatchedNames>
    {
        let preview = preview(members, predictStats: predictStats)
        let lines = Self.unmatchedLines(preview, members: members)
        guard lines.isEmpty,
              let plan = TeamPasteImport.plan(preview: preview, importer: pasteImporter,
                                              teamName: teamName, taken: taken)
        else { return .failure(LimitlessUnmatchedNames(lines: lines)) }
        return .success(plan)
    }

    /// The spread one member's save button creates, named after its species
    /// (numbered when taken). Same all-or-nothing rule as `planTeam`.
    func planSpread(_ member: LimitlessStanding.TeamMember, taken: Set<String>,
                    predictStats: Bool) -> Result<SavedSpread, LimitlessUnmatchedNames> {
        let preview = preview([member], predictStats: predictStats)
        let lines = Self.unmatchedLines(preview, members: [member])
        guard lines.isEmpty, let slot = preview.slots.first,
              let spread = pasteImporter.savedSpread(
                for: slot, name: TeamPasteImport.uniqueName(slot.displayName, taken: taken))
        else { return .failure(LimitlessUnmatchedNames(lines: lines)) }
        return .success(spread)
    }
}
