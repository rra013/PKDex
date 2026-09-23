//
//  PromptNormalizer.swift
//  PKReference
//
//  Swift port of pokemon-llm-training/scripts/prompt_normalizer.py.
//  Rewrites user prompts into the terse style the v2 adapter was trained on,
//  which empirically gives much better adherence to qualifiers (e.g. "bulky",
//  "without trick room") because the dominant species prior has less filler
//  to fight through.
//
//  Behavior must match the Python version. The unit tests at the bottom
//  enforce parity against the same test cases used during training.
//

import Foundation

// MARK: - Public API

/// Result of normalizing a user prompt. If `wasNormalized` is false, the
/// `text` is the original input unchanged (typically because no species
/// could be extracted, e.g. team prompts or junk input).
public struct NormalizedPrompt: Equatable {
    public let text: String
    public let species: String?
    public let qualifiers: [String]
    public let exclusions: [String]
    public let wasNormalized: Bool
    public let original: String
}

/// Normalizes a user prompt against the species whitelist. Returns the
/// prompt unchanged if no whitelisted species can be extracted.
///
/// Example:
///   normalize("Please build me a mega gardevoir with max bulk! Thanks",
///             speciesWhitelist: validator.speciesWhitelist)
///   → NormalizedPrompt(text: "bulky Gardevoir", species: "Gardevoir", ...)
public func normalizePrompt(
    _ raw: String,
    speciesWhitelist: Set<String>
) -> NormalizedPrompt {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        return NormalizedPrompt(text: raw, species: nil, qualifiers: [],
                                exclusions: [], wasNormalized: false, original: raw)
    }

    guard let species = extractSpecies(trimmed, whitelist: speciesWhitelist) else {
        // No species found — pass through unchanged. This handles team
        // prompts ("build me a trick room team") and unparseable input.
        return NormalizedPrompt(text: raw, species: nil, qualifiers: [],
                                exclusions: [], wasNormalized: false, original: raw)
    }

    var constraints = parseConstraints(trimmed)

    // Sanitize captured exclusions: the negation regex can greedily absorb
    // trailing tokens like the species name ("no trick room Gardevoir"
    // → "trick room gardevoir") or a following clause ("without trick room
    // without setup" → "trick room without"). Strip those here, where we
    // know the species.
    constraints.excludeMoves = sanitizeExclusions(
        constraints.excludeMoves, species: species
    )

    let (prefix, suffix) = renderQualifierText(constraints)

    // Terse training-data style:
    //   adjective + species     → "bulky Gardevoir"
    //   species + phrase        → "Gardevoir without Trick Room"
    //   adj + species + phrase  → "bulky Gardevoir for trick room"
    //   neither                 → "Gardevoir"
    var parts: [String] = []
    if let p = prefix { parts.append(p) }
    parts.append(species)
    if let s = suffix { parts.append(s) }
    let text = parts.joined(separator: " ").trimmingCharacters(in: .whitespaces)

    let qualifiers = collectQualifiers(constraints)
    let wasNormalized = (text.lowercased() != trimmed.lowercased())

    return NormalizedPrompt(
        text: text, species: species,
        qualifiers: qualifiers, exclusions: constraints.excludeMoves,
        wasNormalized: wasNormalized, original: raw
    )
}

// MARK: - Constraints

private struct Constraints {
    var excludeMoves: [String] = []
    var excludeSetup: Bool = false
    var wantBulk: Bool = false
    var wantOffense: Bool = false
    var wantTR: Bool = false
    var wantScarf: Bool = false
}

private func parseConstraints(_ prompt: String) -> Constraints {
    let p = prompt.lowercased()
    var c = Constraints()

    // Bulk vs offense qualifiers
    let BULK_PHRASES = ["bulky", "max bulk", "tanky", "wall", "stall", "defensive"]
    let OFFENSE_PHRASES = ["offensive", "glass cannon", "all offense", "sweeper",
                           "fast", "really fast"]
    for phrase in BULK_PHRASES where p.contains(phrase) {
        c.wantBulk = true; break
    }
    for phrase in OFFENSE_PHRASES where p.contains(phrase) {
        c.wantOffense = true; break
    }

    // Choice Scarf detection — word-boundary regex to handle "scarf garchomp"
    // at the start of a prompt
    if p.range(of: #"\bscarf\b"#, options: .regularExpression) != nil {
        c.wantScarf = true
    }

    // Setup exclusion
    if p.contains("without setup") || p.contains("no setup") {
        c.excludeSetup = true
    }

    // Trick Room as a positive want — only when there's NO negation in the
    // immediate vicinity. A blanket "without" check would misfire on
    // "for trick room without setup" (the negation is on setup, not TR).
    if let tr = p.range(of: "trick room") {
        let windowStart = p.index(tr.lowerBound,
                                  offsetBy: -min(30, p.distance(from: p.startIndex, to: tr.lowerBound)))
        let window = String(p[windowStart..<tr.lowerBound])
        if window.range(of: #"\b(?:without|no|not)\b"#,
                        options: .regularExpression) == nil {
            c.wantTR = true
        }
    }

    // Negation captures. Capture at most ~3 words after the negation token
    // to avoid greedy matches eating across subsequent clauses. Stop at
    // common clause boundaries.
    let stopPattern = #"(?:[.,!?]|$| set| build| and | with | for | without | no | that )"#
    let negPatterns = [
        #"without (?:using )?((?:\w+\s?){1,3}?)"# + stopPattern,
        #"\bno ((?:\w+\s?){1,3}?)"# + stopPattern,
        #"doesn'?t (?:use|have|run) ((?:\w+\s?){1,3}?)"# + stopPattern,
    ]
    var exclude: [String] = []
    for pat in negPatterns {
        guard let regex = try? NSRegularExpression(pattern: pat) else { continue }
        let range = NSRange(p.startIndex..., in: p)
        regex.enumerateMatches(in: p, range: range) { match, _, _ in
            guard let match = match, match.numberOfRanges > 1,
                  let captured = Range(match.range(at: 1), in: p) else { return }
            let phrase = String(p[captured]).trimmingCharacters(in: .whitespaces)
            if !phrase.isEmpty {
                exclude.append(phrase)
            }
        }
    }
    c.excludeMoves = exclude

    return c
}

private func sanitizeExclusions(_ exclusions: [String], species: String) -> [String] {
    let STOP_TOKENS: Set<String> = [
        "without", "no", "with", "for", "and", "that", "please",
        "set", "build", "make"
    ]
    let speciesFirstWord = species.lowercased().split(separator: " ").first ?? ""

    var cleaned: [String] = []
    for ex in exclusions {
        let words = ex.split(separator: " ")
        var keep: [String] = []
        for w in words {
            let wClean = w.trimmingCharacters(in: CharacterSet(charactersIn: ".,!?"))
            let wLower = wClean.lowercased()
            if wLower == speciesFirstWord { break }
            if STOP_TOKENS.contains(wLower) { break }
            keep.append(wClean)
        }
        let phrase = keep.joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        if !phrase.isEmpty {
            cleaned.append(phrase)
        }
    }
    return cleaned
}

// MARK: - Species extraction

private func extractSpecies(_ prompt: String, whitelist: Set<String>) -> String? {
    let p = prompt.lowercased()
    // Strip "mega" prefix tokens so "mega gardevoir" matches "gardevoir"
    // (the validator handles mega via the held-item slot, not species name).
    let stripped = p.replacingOccurrences(
        of: #"\bmega\s+"#,
        with: "",
        options: .regularExpression
    )

    // Longest-first match. "Tapu Lele" must match before "Lele" or "Tapu"
    // would (though neither standalone is whitelisted, longer matches win
    // generally for safety).
    let sortedSpecies = whitelist.sorted { $0.count > $1.count }

    for species in sortedSpecies {
        let lowered = species.lowercased()
        // Word-boundary check. Escape regex special chars in case species
        // names ever contain hyphens, apostrophes, etc.
        let escaped = NSRegularExpression.escapedPattern(for: lowered)
        let pattern = "\\b" + escaped + "\\b"
        if stripped.range(of: pattern, options: .regularExpression) != nil {
            return species
        }
    }
    return nil
}

// MARK: - Render qualifier text

private struct QualifierTemplates {
    static let adjectives: [String: [String]] = [
        "bulky": ["bulky"],
        "offensive": ["offensive"],
        "tr_setter": ["Trick Room"],  // used as prefix in "Trick Room Gardevoir"
    ]
    static let phrases: [String: [String]] = [
        "tr_attacker": ["for trick room"],
        "scarf": ["with a Choice Scarf"],
        "exclude_setup": ["without setup moves"],
    ]
}

private func renderQualifierText(_ c: Constraints) -> (prefix: String?, suffix: String?) {
    var prefix: String? = nil
    var suffix: String? = nil

    if c.wantBulk {
        prefix = "bulky"
    } else if c.wantOffense {
        prefix = "offensive"
    }

    // Suffix priorities (only one wins; pick most specific)
    if !c.excludeMoves.isEmpty {
        let movesFmt = c.excludeMoves
            .map { titlecaseMoveName($0) }
            .joined(separator: " and ")
        suffix = "without \(movesFmt)"
    } else if c.wantScarf {
        suffix = "with a Choice Scarf"
    } else if c.wantTR {
        suffix = "for trick room"
    } else if c.excludeSetup {
        suffix = "without setup moves"
    }

    return (prefix, suffix)
}

private func titlecaseMoveName(_ name: String) -> String {
    name.split(separator: " ")
        .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
        .joined(separator: " ")
}

private func collectQualifiers(_ c: Constraints) -> [String] {
    var q: [String] = []
    if c.wantBulk { q.append("bulky") }
    if c.wantOffense { q.append("offensive") }
    if c.wantTR { q.append("trick_room") }
    if c.wantScarf { q.append("scarf") }
    if c.excludeSetup { q.append("no_setup") }
    return q
}

// MARK: - Test cases (mirror the Python parity tests)

#if DEBUG
extension NormalizedPrompt {
    /// Runs the same parity test set used in the Python normalizer. Returns
    /// nil if all pass, or a description of the first failure. Call from a
    /// debug menu or XCTest target.
    public static func runParityTests() -> String? {
        let whitelist: Set<String> = [
            "Gardevoir", "Garchomp", "Charizard", "Pelipper",
            "Kingambit", "Tapu Lele",
        ]
        let cases: [(input: String, expected: String)] = [
            // Polite verbose → terse
            ("Please make me a super special awesome bulky cool mega gardevoir set",
             "bulky Gardevoir"),
            ("Please build me a mega gardevoir with max bulk! Thanks",
             "bulky Gardevoir"),
            ("Build me a competitive Mega Gardevoir set without Trick Room",
             "Gardevoir without Trick Room"),
            ("bulky gardevoir", "bulky Gardevoir"),
            ("mega gardevoir no trick room", "Gardevoir without Trick Room"),
            ("Could you make me a really fast Garchomp?", "offensive Garchomp"),
            ("scarf garchomp", "Garchomp with a Choice Scarf"),
            ("I want a glass cannon Charizard", "offensive Charizard"),
            ("Hey can you build a Pelipper for rain?", "Pelipper"),
            ("Tapu Lele please", "Tapu Lele"),
            ("give me a charizard", "Charizard"),
            ("Build me a Gardevoir for trick room without setup",
             "Gardevoir for trick room without setup moves"),
            // Negation edge cases
            ("Gardevoir without trick room without setup",
             "Gardevoir without Trick Room"),
            ("no trick room Gardevoir", "Gardevoir without Trick Room"),
        ]

        for (input, expected) in cases {
            let result = normalizePrompt(input, speciesWhitelist: whitelist)
            if result.text != expected {
                return "FAIL: \(input.debugDescription)\n" +
                       "  expected: \(expected.debugDescription)\n" +
                       "  got:      \(result.text.debugDescription)"
            }
        }
        return nil
    }
}
#endif
