//
//  ShowdownPaste.swift
//  PKDex
//
//  Text <-> struct layer for Pokemon Showdown "paste" format (the export
//  block you get from the Showdown teambuilder, and the format every other
//  community tool speaks).
//
//  This layer is deliberately *lossless text*: it resolves nothing against
//  the app's SwiftData rows and maps nothing onto `HeldItem` / `PKMNStats` /
//  `PokemonSet`. Names are kept exactly as written so a parse -> serialize
//  round trip is byte-stable. Resolving those names (and the legality check)
//  is the importer's job — see the bridge layer, which is the only place that
//  needs `allPokemon` / `allMoves`.
//
//  Parsing never fails as a whole. A block with one bad line still produces a
//  set plus a `PasteDiagnostic` pointing at the offending line, so importing
//  six Pokemon doesn't get thrown away because one move was misspelled.
//
//  Every type here is explicitly `nonisolated`. The module builds with
//  approachable concurrency (`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`) plus
//  `INFER_ISOLATED_CONFORMANCES`, which would otherwise make even these pure
//  value types' synthesized `Equatable` conformances main-actor-isolated and
//  unusable from a background context. This layer does no UI and touches no
//  SwiftData, so it has no business being pinned to the main actor — and the
//  damage-calc work that follows needs off-main value types for the same
//  reason. Same convention as `PokeAPIGraphQL.swift`'s GraphQL DTOs.
//

import Foundation

// MARK: - Stat scale

/// Which EV/stat-point scale a set's numbers are written in.
///
/// The mainline games (and therefore every third-party tool) use 0–252 per
/// stat / 510 total. Pokemon Champions uses 0–32 per stat / 66 total. The two
/// are distinguishable from the numbers alone in almost every real paste — see
/// `ShowdownPaste.detectScale`.
nonisolated enum StatScale: Equatable, Sendable {
    case mainline
    case champions

    var maxPerStat: Int {
        switch self {
        case .mainline:  return maxEVPerStat
        case .champions: return championsMaxEVPerStat
        }
    }

    var maxTotal: Int {
        switch self {
        case .mainline:  return maxTotalEVs
        case .champions: return championsMaxTotalEVs
        }
    }

    /// Convert a single stat value between scales.
    ///
    /// Lossy in both directions (the Champions scale has 33 points where the
    /// mainline has 64 meaningful ones), so round-tripping a converted value
    /// is not guaranteed to return the original. Import/export converts at
    /// most once, at the boundary.
    static func convert(_ value: Int, from source: StatScale, to target: StatScale) -> Int {
        guard source != target else { return value }
        switch target {
        case .mainline:
            return championsEVToMain(value)
        case .champions:
            // Inverse of `championsEVToMain`, rounded to nearest rather than
            // truncated so 252 -> 32 (not 31) and 4 -> 1 (not 0).
            return Int((Double(value) * 32.0 / 252.0).rounded())
        }
    }
}

// MARK: - Parsed set

/// One Pokemon from a paste, in the units and spelling it was written in.
nonisolated struct ShowdownPasteSet: Equatable, Sendable {
    /// Free-text nickname from the header, if the set had one.
    var nickname: String?
    /// Species exactly as written (e.g. "Urshifu-Rapid-Strike", "Mr. Mime").
    var species: String
    /// "M" / "F" / "N" from the header. Genderless sets normally omit this.
    var gender: Character?
    /// Held item exactly as written. Not mapped to `HeldItem` here.
    var item: String?
    var ability: String?
    /// Absent in the paste means "the format's default", which differs by
    /// format (100 in singles ladders, 50 in VGC), so this stays optional and
    /// the importer decides.
    var level: Int?
    var shiny: Bool = false
    var happiness: Int?
    var teraType: String?
    var nature: String?
    var evs = ShowdownStats()
    var ivs = ShowdownPasteSet.defaultIVs
    /// The scale `evs` is expressed in. Set from the paste-level detection.
    var evScale: StatScale = .mainline
    /// Up to four move names, exactly as written.
    var moves: [String] = []

    /// Unlisted IVs mean 31, not 0.
    static let defaultIVs = ShowdownStats(hp: 31, atk: 31, def: 31, spa: 31, spd: 31, spe: 31)

    init(species: String) {
        self.species = species
    }
}

// MARK: - Diagnostics

/// A problem found while parsing, anchored to a 1-based line number in the
/// original paste so the import UI can point at it.
nonisolated struct PasteDiagnostic: Equatable, Sendable {
    nonisolated enum Kind: Equatable, Sendable {
        /// Line didn't match the header, `Key: Value`, `X Nature` or `- Move` forms.
        case unrecognizedLine
        /// A stat list entry like "252 Atk" that couldn't be read.
        case malformedStatEntry(String)
        /// A stat abbreviation we don't know (not HP/Atk/Def/SpA/SpD/Spe).
        case unknownStatKey(String)
        case invalidNumber(field: String, value: String)
        /// More than four `- Move` lines; the extras are dropped.
        case tooManyMoves(kept: Int, dropped: Int)
        /// A field appeared twice in one block; the last one wins.
        case duplicateField(String)
        /// Block had no readable species in its header, so it was dropped.
        case missingSpecies
        /// EV numbers fit both scales; `detectedScale` is a guess.
        case ambiguousEVScale
    }

    /// 1-based line number within the whole paste.
    var line: Int
    /// Index into `ParsedPaste.sets`, or nil when the block was dropped.
    var setIndex: Int?
    var kind: Kind

    var message: String {
        switch kind {
        case .unrecognizedLine:
            return "Couldn't read this line."
        case .malformedStatEntry(let entry):
            return "Couldn't read \"\(entry)\" — expected a form like \"252 Atk\"."
        case .unknownStatKey(let key):
            return "Unknown stat \"\(key)\"."
        case .invalidNumber(let field, let value):
            return "\(field) must be a number, got \"\(value)\"."
        case .tooManyMoves(let kept, let dropped):
            return "Kept the first \(kept) moves and dropped \(dropped)."
        case .duplicateField(let field):
            return "\(field) appeared more than once; used the last value."
        case .missingSpecies:
            return "No species in this block, so it was skipped."
        case .ambiguousEVScale:
            return "EV numbers fit both the mainline and Champions scales."
        }
    }
}

/// Result of parsing a whole paste.
nonisolated struct ParsedPaste: Equatable, Sendable {
    var sets: [ShowdownPasteSet] = []
    var diagnostics: [PasteDiagnostic] = []
    /// Scale applied to every set's `evs`.
    var detectedScale: StatScale = .mainline
    /// True when the numbers fit both scales and `detectedScale` is a guess.
    var scaleWasAmbiguous: Bool = false

    var isEmpty: Bool { sets.isEmpty }
}

// MARK: - Parser

nonisolated enum ShowdownPaste {

    /// Parse a paste containing any number of sets.
    ///
    /// `forcedScale` overrides EV-scale detection — pass it when the user has
    /// explicitly told the UI which units they pasted.
    static func parse(_ text: String, forcedScale: StatScale? = nil) -> ParsedPaste {
        let lines = normalizedLines(text)
        var out = ParsedPaste()

        for block in blocks(in: lines) {
            let setIndex = out.sets.count
            let (parsed, blockDiagnostics) = parseBlock(block, setIndex: setIndex)
            var diagnostics = blockDiagnostics
            if let set = parsed {
                out.sets.append(set)
            } else {
                // Block dropped: the diagnostics can't point at a set.
                diagnostics = diagnostics.map {
                    var d = $0
                    d.setIndex = nil
                    return d
                }
            }
            out.diagnostics.append(contentsOf: diagnostics)
        }

        let (scale, ambiguous) = detectScale(out.sets)
        out.detectedScale = forcedScale ?? scale
        out.scaleWasAmbiguous = forcedScale == nil && ambiguous
        for i in out.sets.indices { out.sets[i].evScale = out.detectedScale }

        if out.scaleWasAmbiguous, let firstLine = lines.first?.number {
            out.diagnostics.append(
                PasteDiagnostic(line: firstLine, setIndex: nil, kind: .ambiguousEVScale))
        }
        return out
    }

    // MARK: Line plumbing

    private struct NumberedLine {
        var number: Int
        var text: String
    }

    /// Normalizes line endings and pairs every line with its 1-based number.
    private static func normalizedLines(_ text: String) -> [NumberedLine] {
        let unified = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        return unified.split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated()
            .map { NumberedLine(number: $0.offset + 1, text: String($0.element)) }
    }

    /// Groups lines into per-Pokemon blocks on blank-line boundaries, dropping
    /// Showdown's `=== [format] Folder ===` team headers.
    private static func blocks(in lines: [NumberedLine]) -> [[NumberedLine]] {
        var out: [[NumberedLine]] = []
        var current: [NumberedLine] = []
        for line in lines {
            let trimmed = line.text.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                if !current.isEmpty { out.append(current); current = [] }
                continue
            }
            // Folder/format header emitted when exporting a whole folder.
            if trimmed.hasPrefix("===") && trimmed.hasSuffix("===") { continue }
            current.append(NumberedLine(number: line.number, text: trimmed))
        }
        if !current.isEmpty { out.append(current) }
        return out
    }

    // MARK: Block parsing

    private static func parseBlock(
        _ block: [NumberedLine], setIndex: Int
    ) -> (ShowdownPasteSet?, [PasteDiagnostic]) {
        var diagnostics: [PasteDiagnostic] = []
        guard let header = block.first else { return (nil, diagnostics) }

        guard let parsedHeader = parseHeader(header.text) else {
            diagnostics.append(
                PasteDiagnostic(line: header.number, setIndex: setIndex, kind: .missingSpecies))
            return (nil, diagnostics)
        }

        var set = ShowdownPasteSet(species: parsedHeader.species)
        set.nickname = parsedHeader.nickname
        set.gender = parsedHeader.gender
        set.item = parsedHeader.item

        var sawEVs = false, sawIVs = false, sawNature = false, sawAbility = false
        var droppedMoves = 0

        for line in block.dropFirst() {
            let text = line.text

            // `- Move` (also tolerating en/em dashes, which survive some
            // copy-paste paths through chat clients and forums).
            if let moveName = moveLine(text) {
                if set.moves.count < 4 {
                    set.moves.append(moveName)
                } else {
                    droppedMoves += 1
                }
                continue
            }

            // `Adamant Nature` — no colon, so it can't collide with a field.
            if let nature = natureLine(text) {
                if sawNature {
                    diagnostics.append(PasteDiagnostic(
                        line: line.number, setIndex: setIndex, kind: .duplicateField("Nature")))
                }
                set.nature = nature
                sawNature = true
                continue
            }

            // `Key: Value`
            guard let colon = text.firstIndex(of: ":") else {
                diagnostics.append(PasteDiagnostic(
                    line: line.number, setIndex: setIndex, kind: .unrecognizedLine))
                continue
            }
            let key = toID(String(text[text.startIndex..<colon]))
            let value = String(text[text.index(after: colon)...])
                .trimmingCharacters(in: .whitespaces)

            switch key {
            case "ability":
                if sawAbility {
                    diagnostics.append(PasteDiagnostic(
                        line: line.number, setIndex: setIndex, kind: .duplicateField("Ability")))
                }
                set.ability = value.isEmpty ? nil : value
                sawAbility = true

            case "level":
                if let n = Int(value) {
                    set.level = n
                } else {
                    diagnostics.append(PasteDiagnostic(
                        line: line.number, setIndex: setIndex,
                        kind: .invalidNumber(field: "Level", value: value)))
                }

            case "shiny":
                set.shiny = isAffirmative(value)

            case "happiness":
                if let n = Int(value) {
                    set.happiness = n
                } else {
                    diagnostics.append(PasteDiagnostic(
                        line: line.number, setIndex: setIndex,
                        kind: .invalidNumber(field: "Happiness", value: value)))
                }

            case "teratype":
                set.teraType = value.isEmpty ? nil : value

            case "gender":
                set.gender = value.uppercased().first

            case "evs":
                if sawEVs {
                    diagnostics.append(PasteDiagnostic(
                        line: line.number, setIndex: setIndex, kind: .duplicateField("EVs")))
                }
                let (stats, errs) = parseStatList(value, base: ShowdownStats(),
                                                  line: line.number, setIndex: setIndex)
                set.evs = stats
                diagnostics.append(contentsOf: errs)
                sawEVs = true

            case "ivs":
                if sawIVs {
                    diagnostics.append(PasteDiagnostic(
                        line: line.number, setIndex: setIndex, kind: .duplicateField("IVs")))
                }
                let (stats, errs) = parseStatList(value, base: ShowdownPasteSet.defaultIVs,
                                                  line: line.number, setIndex: setIndex)
                set.ivs = stats
                diagnostics.append(contentsOf: errs)
                sawIVs = true

            // Emitted by Showdown for gen-8 sets. Parsed and dropped: nothing
            // downstream models Dynamax, and rejecting the line would make
            // pastes from SS formats look broken.
            case "dynamaxlevel", "gigantamax", "hiddenpowertype", "pokeball", "nickname":
                continue

            default:
                diagnostics.append(PasteDiagnostic(
                    line: line.number, setIndex: setIndex, kind: .unrecognizedLine))
            }
        }

        if droppedMoves > 0, let lastLine = block.last?.number {
            diagnostics.append(PasteDiagnostic(
                line: lastLine, setIndex: setIndex,
                kind: .tooManyMoves(kept: 4, dropped: droppedMoves)))
        }

        return (set, diagnostics)
    }

    // MARK: Header

    private struct ParsedHeader {
        var nickname: String?
        var species: String
        var gender: Character?
        var item: String?
    }

    /// `[Nickname ](Species)[ (M)][ @ Item]`, or the far more common
    /// `Species[ (M)][ @ Item]`.
    private static func parseHeader(_ line: String) -> ParsedHeader? {
        var rest = line.trimmingCharacters(in: .whitespaces)
        var item: String?

        // Item is separated by " @ ". Split on the last occurrence so an item
        // or nickname containing "@" doesn't confuse things.
        if let at = rest.range(of: " @ ", options: .backwards) {
            item = String(rest[at.upperBound...]).trimmingCharacters(in: .whitespaces)
            rest = String(rest[rest.startIndex..<at.lowerBound])
                .trimmingCharacters(in: .whitespaces)
            if item?.isEmpty == true { item = nil }
        }

        // Trailing gender marker, e.g. "(M)".
        var gender: Character?
        if rest.hasSuffix(")") {
            let candidates = ["(M)", "(F)", "(N)"]
            for marker in candidates where rest.hasSuffix(marker) {
                gender = marker.dropFirst().first
                rest = String(rest.dropLast(marker.count))
                    .trimmingCharacters(in: .whitespaces)
                break
            }
        }

        // What's left is either "Species" or "Nickname (Species)".
        var nickname: String?
        var species = rest
        if rest.hasSuffix(")"),
           let open = rest.range(of: "(", options: .backwards) {
            let inner = String(rest[rest.index(after: open.lowerBound)..<rest.index(before: rest.endIndex)])
                .trimmingCharacters(in: .whitespaces)
            let prefix = String(rest[rest.startIndex..<open.lowerBound])
                .trimmingCharacters(in: .whitespaces)
            if !inner.isEmpty {
                species = inner
                nickname = prefix.isEmpty ? nil : prefix
            }
        }

        species = species.trimmingCharacters(in: .whitespaces)
        guard !species.isEmpty else { return nil }
        return ParsedHeader(nickname: nickname, species: species, gender: gender, item: item)
    }

    // MARK: Line forms

    private static let moveBullets: [Character] = ["-", "\u{2013}", "\u{2014}"]

    private static func moveLine(_ text: String) -> String? {
        guard let first = text.first, moveBullets.contains(first) else { return nil }
        let name = String(text.dropFirst()).trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name
    }

    private static func natureLine(_ text: String) -> String? {
        guard !text.contains(":") else { return nil }
        let words = text.split(separator: " ").map(String.init)
        guard words.count == 2, toID(words[1]) == "nature" else { return nil }
        return words[0]
    }

    private static func isAffirmative(_ value: String) -> Bool {
        let id = toID(value)
        return id == "yes" || id == "true" || id == "1"
    }

    // MARK: Stat lists

    /// Stat abbreviations Showdown emits, plus the long forms and the gen-1
    /// `Spc` that older pastes carry.
    private static let statKeys: [ShowdownID: ShowdownStat] = [
        "hp": .hp, "hitpoints": .hp,
        "atk": .atk, "at": .atk, "attack": .atk,
        "def": .def, "df": .def, "defense": .def, "defence": .def,
        "spa": .spa, "spatk": .spa, "specialattack": .spa, "spc": .spa, "special": .spa,
        "spd": .spd, "spdef": .spd, "specialdefense": .spd, "specialdefence": .spd,
        "spe": .spe, "speed": .spe,
    ]

    /// Splits a stat entry into its amount and its (possibly multi-word) stat
    /// name, accepting the number on either end. Returns nil when there's no
    /// leading or trailing digit run, or nothing left for the name.
    private static func splitAmountAndKey(_ entry: String) -> (Int, String)? {
        let leadingDigits = entry.prefix { $0.isNumber }
        if !leadingDigits.isEmpty {
            let key = entry.dropFirst(leadingDigits.count)
                .trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty, let amount = Int(leadingDigits) else { return nil }
            return (amount, key)
        }

        let trailingDigits = entry.reversed().prefix { $0.isNumber }.reversed()
        if !trailingDigits.isEmpty {
            let key = entry.dropLast(trailingDigits.count)
                .trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty, let amount = Int(String(trailingDigits)) else { return nil }
            return (amount, key)
        }
        return nil
    }

    /// Parses `252 Atk / 4 HP / 252 Spe` on top of `base` (zeros for EVs, 31s
    /// for IVs), so unlisted stats keep their default.
    private static func parseStatList(
        _ value: String, base: ShowdownStats, line: Int, setIndex: Int
    ) -> (ShowdownStats, [PasteDiagnostic]) {
        var stats = base
        var diagnostics: [PasteDiagnostic] = []

        for rawEntry in value.split(separator: "/") {
            let entry = rawEntry.trimmingCharacters(in: .whitespaces)
            if entry.isEmpty { continue }

            // Canonically "252 Atk", but the key can be multiple words
            // ("252 Special Attack", "252 Sp Atk"), so split on the digit run
            // rather than on whitespace. A trailing number ("Atk 252") is
            // accepted too — it costs nothing and turns up in hand-written
            // pastes.
            guard let (amount, keyPart) = splitAmountAndKey(entry) else {
                diagnostics.append(PasteDiagnostic(
                    line: line, setIndex: setIndex, kind: .malformedStatEntry(entry)))
                continue
            }
            guard let stat = statKeys[toID(keyPart)] else {
                diagnostics.append(PasteDiagnostic(
                    line: line, setIndex: setIndex, kind: .unknownStatKey(keyPart)))
                continue
            }
            stats[stat] = amount
        }
        return (stats, diagnostics)
    }

    // MARK: Scale detection

    /// Decides whether a paste's EVs are mainline or Champions numbers.
    ///
    /// Two signals, in order of confidence:
    ///  1. Anything over the Champions caps (32 per stat / 66 total) can only
    ///     be mainline.
    ///  2. A value that isn't a multiple of 4 can only be Champions — mainline
    ///     EVs below the cap are always spent in multiples of 4, because the
    ///     stat formula divides them by 4.
    ///
    /// When neither fires (a low-investment mainline spread like `4 HP / 8 Atk`
    /// is indistinguishable from Champions points) the answer is `.mainline`,
    /// the interchange default, flagged as ambiguous so the UI can offer a
    /// toggle.
    /// Like `parse(_:)`, but an ambiguous paste resolves to `ambiguousDefault`
    /// instead of `.mainline`. `scaleWasAmbiguous` stays true, so the UI can
    /// still offer the toggle.
    ///
    /// For callers that know the context. A Champions spread written only in
    /// multiples of 4 (`32 HP / 32 Atk`) fits both scales, and reading it as
    /// mainline would silently turn 32 points into 4 when it lands on a
    /// Champions calc. Unambiguous pastes are unaffected.
    static func parse(_ text: String, ambiguousDefault: StatScale) -> ParsedPaste {
        let detected = parse(text)
        guard detected.scaleWasAmbiguous, detected.detectedScale != ambiguousDefault else {
            return detected
        }
        var resolved = parse(text, forcedScale: ambiguousDefault)
        resolved.scaleWasAmbiguous = true
        return resolved
    }

    static func detectScale(_ sets: [ShowdownPasteSet]) -> (scale: StatScale, ambiguous: Bool) {
        var sawAnyEVs = false
        var sawNonMultipleOfFour = false

        for set in sets {
            var total = 0
            for stat in ShowdownStat.allCases {
                let v = set.evs[stat]
                total += v
                if v > 0 { sawAnyEVs = true }
                if v > championsMaxEVPerStat { return (.mainline, false) }
                if v % 4 != 0 { sawNonMultipleOfFour = true }
            }
            if total > championsMaxTotalEVs { return (.mainline, false) }
        }

        if sawNonMultipleOfFour { return (.champions, false) }
        // No EVs anywhere: the scale genuinely doesn't matter.
        return (.mainline, sawAnyEVs)
    }
}

// MARK: - Serialization

extension ShowdownPasteSet {

    /// Renders this set in Showdown's canonical field order, so a paste that
    /// came from Showdown round-trips byte-for-byte.
    ///
    /// Pass `scale` to convert the EV numbers on the way out; the default
    /// emits them in the scale they're already in.
    nonisolated func showdownText(scale: StatScale? = nil) -> String {
        let target = scale ?? evScale
        var lines: [String] = []

        // Header
        var header = ""
        if let nickname { header += "\(nickname) (\(species))" } else { header += species }
        if let gender { header += " (\(gender))" }
        if let item, !item.isEmpty { header += " @ \(item)" }
        lines.append(header)

        if let ability { lines.append("Ability: \(ability)") }
        if let level { lines.append("Level: \(level)") }
        if shiny { lines.append("Shiny: Yes") }
        if let happiness { lines.append("Happiness: \(happiness)") }
        if let teraType { lines.append("Tera Type: \(teraType)") }

        let outEVs = Self.scaled(evs, from: evScale, to: target)
        if let evLine = Self.statLine(outEVs, label: "EVs", omitting: 0) {
            lines.append(evLine)
        }
        if let nature { lines.append("\(nature) Nature") }
        // IVs are always mainline 0–31 regardless of the EV scale.
        if let ivLine = Self.statLine(ivs, label: "IVs", omitting: 31) {
            lines.append(ivLine)
        }
        for move in moves { lines.append("- \(move)") }

        return lines.joined(separator: "\n")
    }

    nonisolated private static func scaled(
        _ stats: ShowdownStats, from source: StatScale, to target: StatScale
    ) -> ShowdownStats {
        guard source != target else { return stats }
        var out = ShowdownStats()
        for stat in ShowdownStat.allCases {
            out[stat] = StatScale.convert(stats[stat], from: source, to: target)
        }
        return out
    }

    /// `EVs: 252 Atk / 4 Def / 252 Spe`, or nil when every value is the
    /// default and Showdown would omit the line entirely.
    nonisolated private static func statLine(
        _ stats: ShowdownStats, label: String, omitting defaultValue: Int
    ) -> String? {
        let order: [(ShowdownStat, String)] = [
            (.hp, "HP"), (.atk, "Atk"), (.def, "Def"),
            (.spa, "SpA"), (.spd, "SpD"), (.spe, "Spe"),
        ]
        let parts = order.compactMap { stat, name -> String? in
            let v = stats[stat]
            return v == defaultValue ? nil : "\(v) \(name)"
        }
        guard !parts.isEmpty else { return nil }
        return "\(label): \(parts.joined(separator: " / "))"
    }
}

extension Collection<ShowdownPasteSet> {

    /// Renders a team as a paste: sets separated by a blank line, which is
    /// what Showdown's importer expects.
    nonisolated func showdownText(scale: StatScale? = nil) -> String {
        map { $0.showdownText(scale: scale) }.joined(separator: "\n\n")
    }
}
