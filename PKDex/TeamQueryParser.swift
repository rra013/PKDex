//
//  TeamQueryParser.swift
//  PKDex
//
//  Turns a team description ("Trick Room with Mega Gardevoir, no
//  Incineroar") into a `TeamQuery` the search engine can run. Deterministic:
//  it matches the longest known phrase at each position against the
//  vocabulary (species, nicknames, Mega Stones, moves, style keywords), and
//  never drops a word silently. Anything it can't place goes in
//  `unrecognized`, and typo fixes go in `corrections`, so the UI can show
//  both and the user can fix a misreading.
//
//  Rules worth knowing:
//  - A negation ("no", "without", …) applies to the next item only. It
//    carries on across "or", "nor" and commas ("without Incineroar or
//    Rillaboom" excludes both) until a contrast word ("and", "but") or a
//    word the parser doesn't know: "no Incineroar and Rillaboom" excludes
//    only Incineroar.
//  - Forms attach to the species next to them: "Hisuian Arcanine",
//    "Arcanine-H", "Indeedee ♀", "Paldean Tauros Blaze Breed".
//  - "Mega" before or after a species asks for its Mega; "Charizard Y",
//    "Mega Charizard Y" and "Charizardite Y" ask for that Mega.
//  - When the same item is mentioned twice, the later mention wins.
//
//  Runs of words it can't place ("big fire cat") can be handed to Apple
//  Intelligence, and the text parsed again with its answers in their place
//  ("no big fire cat" → "no Incineroar"), so the rules above still apply.
//

import Foundation

nonisolated struct SpeciesTerm: Hashable, Sendable {
    enum Mega: Hashable, Sendable {
        case any
        case variant(String)
    }

    let speciesID: String
    let name: String
    /// Form words the team member must have, in the order given. "male"
    /// means "not the female form".
    var formWords: [String] = []
    var mega: Mega?

    /// "Mega Charizard Y", "Arcanine (Hisui)", "Tauros (Paldea Blaze)".
    var displayName: String {
        var text = name
        if !formWords.isEmpty {
            text += " (" + formWords.map(\.capitalized).joined(separator: " ") + ")"
        }
        switch mega {
        case .any?: return "Mega " + text
        case .variant(let variant)?: return "Mega " + text + " " + variant.uppercased()
        case nil: return text
        }
    }
}

nonisolated struct MoveTerm: Hashable, Sendable {
    let id: ShowdownID
    let name: String
}

nonisolated struct TeamQuery: Equatable, Sendable {
    struct Correction: Equatable, Sendable {
        let typed: String
        let interpreted: String
    }

    var species: [SpeciesTerm] = []
    var excludedSpecies: [SpeciesTerm] = []
    var moves: [MoveTerm] = []
    var excludedMoves: [MoveTerm] = []
    var archetypes: [TeamArchetype] = []
    var excludedArchetypes: [TeamArchetype] = []
    /// Typos read as the nearest species: "incinaroar" → Incineroar.
    var corrections: [Correction] = []
    /// Words the parser couldn't place.
    var unrecognized: [String] = []

    var hasConstraints: Bool {
        !(species.isEmpty && excludedSpecies.isEmpty && moves.isEmpty
          && excludedMoves.isEmpty && archetypes.isEmpty && excludedArchetypes.isEmpty)
    }
}

nonisolated struct TeamQueryParser: Sendable {

    private enum Entity: Sendable {
        case species(SpeciesTerm)
        case move(MoveTerm)
        case archetype(TeamArchetype)
    }

    let vocabulary: TeamSearchVocabulary
    /// Phrase (words joined by spaces) → what it names.
    private let phrases: [String: Entity]
    private let longestPhrase: Int
    /// Every species' form words, plus "male": words that may lead into a
    /// species ("Hisuian Arcanine", "female Indeedee").
    private let leadingFormWords: Set<String>
    /// One-word species names and their IDs, for typo correction.
    private let fuzzyTargets: [(word: String, species: TeamSearchVocabulary.Species)]

    init(vocabulary: TeamSearchVocabulary) {
        self.vocabulary = vocabulary
        var phrases: [String: Entity] = [:]
        func add(_ text: String, _ entity: Entity) {
            let key = Self.tokens(text).filter { $0 != "," }.joined(separator: " ")
            if !key.isEmpty { phrases[key] = entity }
        }
        // Later additions win a tie: styles beat moves ("Trick Room" means
        // the style), and species beat moves.
        for (id, name) in vocabulary.queryMoves {
            add(name, .move(MoveTerm(id: id, name: name)))
        }
        for species in vocabulary.species {
            let term = SpeciesTerm(speciesID: species.id, name: species.name)
            add(species.name, .species(term))
            add(species.id, .species(term))          // "kommoo", "mrrime"
            for mega in species.megas {
                var megaTerm = term
                megaTerm.mega = mega.variant.map { .variant($0) } ?? .any
                add(mega.stoneName, .species(megaTerm))
            }
        }
        for (nickname, id) in vocabulary.nicknames {
            if let species = vocabulary.speciesByID[id] {
                add(nickname, .species(SpeciesTerm(speciesID: species.id, name: species.name)))
            }
        }
        for rule in vocabulary.archetypes {
            for keyword in rule.keywords { add(keyword, .archetype(rule.archetype)) }
        }
        self.phrases = phrases
        longestPhrase = phrases.keys.map { $0.split(separator: " ").count }.max() ?? 1
        leadingFormWords = vocabulary.species.reduce(into: ["male"]) { $0.formUnion($1.formWords) }
        fuzzyTargets = vocabulary.species.filter { $0.words.count == 1 }.map { ($0.words[0], $0) }
    }

    // MARK: Parsing

    func parse(_ text: String) -> TeamQuery {
        read(Self.tokens(text)).query
    }

    /// Parses words, noting the position of each one left unrecognized.
    private func read(_ words: [String]) -> (query: TeamQuery, unplaced: [Int]) {
        var query = TeamQuery()
        var unplaced: [Int] = []
        var index = 0
        /// A negation word is waiting for its item.
        var negate = false
        /// A connector passed the last item's negation on.
        var carried = false
        /// The last item was negated, so a connector can pass it on.
        var lastWasNegated = false
        /// Where a "mega" waiting for its species was.
        var pendingMega: Int?
        var pendingForms: [(word: String, position: Int)] = []

        func unrecognized(_ word: String, at position: Int) {
            query.unrecognized.append(word)
            unplaced.append(position)
        }

        func flushPending() {
            if let pendingMega { unrecognized("mega", at: pendingMega) }
            for form in pendingForms { unrecognized(form.word, at: form.position) }
            pendingMega = nil
            pendingForms = []
        }

        func record(_ entity: Entity) {
            switch entity {
            case .species(let term):
                query.species.removeAll { $0 == term }
                query.excludedSpecies.removeAll { $0 == term }
                if negate || carried { query.excludedSpecies.append(term) } else { query.species.append(term) }
            case .move(let term):
                query.moves.removeAll { $0 == term }
                query.excludedMoves.removeAll { $0 == term }
                if negate || carried { query.excludedMoves.append(term) } else { query.moves.append(term) }
            case .archetype(let archetype):
                query.archetypes.removeAll { $0 == archetype }
                query.excludedArchetypes.removeAll { $0 == archetype }
                if negate || carried { query.excludedArchetypes.append(archetype) } else { query.archetypes.append(archetype) }
            }
            lastWasNegated = negate || carried
            negate = false
            carried = false
        }

        /// Attaches the forms and Mega around a species, consuming the words
        /// after it, then records it.
        func recordSpecies(_ base: SpeciesTerm) {
            var term = base
            let species = vocabulary.speciesByID[term.speciesID]
            let known = species?.formWords ?? []
            func isForm(_ word: String) -> Bool {
                known.contains(word) || (word == "male" && known.contains("female"))
            }
            var forms = pendingForms.map(\.word).filter(isForm)
            for form in pendingForms where !isForm(form.word) {
                unrecognized(form.word, at: form.position)
            }
            pendingForms = []
            while index < words.count {
                let next = words[index]
                if isForm(next) {
                    forms.append(next)
                } else if vocabulary.formNoise.contains(next) && !forms.isEmpty {
                    // "Paldean Tauros Blaze *Breed*"
                } else {
                    break
                }
                index += 1
            }
            var seen = Set<String>()
            term.formWords = forms.filter { seen.insert($0).inserted }

            let megas = species?.megas ?? []
            if index < words.count, words[index] == "mega" {
                pendingMega = index
                index += 1
            }
            if term.mega == nil, index < words.count,
               megas.contains(where: { $0.variant == words[index] }) {
                term.mega = .variant(words[index])
                index += 1
            } else if let megaPosition = pendingMega, term.mega == nil {
                if megas.isEmpty { unrecognized("mega", at: megaPosition) } else { term.mega = .any }
            }
            pendingMega = nil
            record(.species(term))
        }

        while index < words.count {
            let word = words[index]
            if vocabulary.negations.contains(word) {
                negate = true
                lastWasNegated = false
                index += 1
                continue
            }
            if word == "," || vocabulary.connectors.contains(word) {
                if lastWasNegated { carried = true }
                index += 1
                continue
            }
            if word == "mega" {
                pendingMega = index
                index += 1
                continue
            }
            if let match = longestMatch(at: index, in: words) {
                let (entity, length) = match
                index += length
                if case .species(let term) = entity {
                    recordSpecies(term)
                } else {
                    flushPending()
                    record(entity)
                }
                continue
            }
            if leadingFormWords.contains(word) {
                pendingForms.append((word, index))
                index += 1
                continue
            }
            index += 1
            if vocabulary.contrastWords.contains(word) {
                carried = false
                lastWasNegated = false
                continue
            }
            if vocabulary.stopWords.contains(word) || vocabulary.formNoise.contains(word)
                || word.allSatisfy(\.isNumber) {
                continue
            }
            if let species = closestSpecies(to: word) {
                query.corrections.append(.init(typed: word, interpreted: species.name))
                recordSpecies(SpeciesTerm(speciesID: species.id, name: species.name))
                continue
            }
            unrecognized(word, at: index - 1)
            carried = false
            lastWasNegated = false
        }
        flushPending()
        return (query, unplaced)
    }

    // MARK: Unplaced phrases

    /// Runs of adjacent words the parser couldn't place, as its words:
    /// "big fire cat" in "sun, no big fire cat", "hisui fire dog" in
    /// "Hisuian fire dog".
    func unplacedPhrases(in text: String) -> [String] {
        let words = Self.tokens(text)
        return Self.runs(read(words).unplaced).map { words[$0].joined(separator: " ") }
    }

    /// Parses `text` with its unplaced phrases replaced by what they mean,
    /// keyed by phrase: with "big fire cat" meaning "Incineroar", "sun, no
    /// big fire cat" reads as "sun, no Incineroar". A meaning is used only
    /// when all of it parses as known names with no typos; otherwise the
    /// phrase stays as it was.
    func parse(_ text: String, meanings: [String: String]) -> TeamQuery {
        let words = Self.tokens(text)
        var rewritten: [String] = []
        var next = 0
        for run in Self.runs(read(words).unplaced) {
            rewritten += words[next..<run.lowerBound]
            let phrase = words[run].joined(separator: " ")
            if let meaning = meanings[phrase], readsCleanly(meaning) {
                rewritten += Self.tokens(meaning)
            } else {
                rewritten += words[run]
            }
            next = run.upperBound
        }
        rewritten += words[next...]
        return read(rewritten).query
    }

    private func readsCleanly(_ text: String) -> Bool {
        let query = parse(text)
        return query.hasConstraints && query.unrecognized.isEmpty && query.corrections.isEmpty
    }

    /// Positions grouped into runs of adjacent ones.
    private static func runs(_ positions: [Int]) -> [Range<Int>] {
        var runs: [Range<Int>] = []
        for position in Set(positions).sorted() {
            if let last = runs.last, last.upperBound == position {
                runs[runs.count - 1] = last.lowerBound..<position + 1
            } else {
                runs.append(position..<position + 1)
            }
        }
        return runs
    }

    private func longestMatch(at start: Int, in words: [String]) -> (Entity, Int)? {
        let maxLength = min(longestPhrase, words.count - start)
        guard maxLength > 0 else { return nil }
        for length in stride(from: maxLength, through: 1, by: -1) {
            let slice = words[start..<start + length]
            if slice.contains(",") { continue }
            if let entity = phrases[slice.joined(separator: " ")] { return (entity, length) }
        }
        return nil
    }

    /// The one-word species name nearest a typo: within one edit for words
    /// of 5–7 letters, two for longer words. Shorter words aren't guessed.
    private func closestSpecies(to word: String) -> TeamSearchVocabulary.Species? {
        guard word.count >= 5 else { return nil }
        let allowed = word.count >= 8 ? 2 : 1
        var best: (species: TeamSearchVocabulary.Species, distance: Int)?
        for target in fuzzyTargets where abs(target.word.count - word.count) <= allowed {
            let distance = Self.editDistance(word, target.word, cutoff: allowed)
            if distance <= allowed, best == nil || distance < best!.distance {
                best = (target.species, distance)
            }
        }
        return best?.species
    }

    // MARK: Tokens

    /// Lowercased words and commas. Accents are folded, ♀/♂ become
    /// "female"/"male", regional adjectives become region words ("Hisuian"
    /// → "hisui"), and a Showdown-style form suffix after a hyphen is
    /// spelled out ("arcanine-h" → "arcanine hisui", "indeedee-f" →
    /// "indeedee female").
    static func tokens(_ text: String) -> [String] {
        let folded = text
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .lowercased()
            .replacingOccurrences(of: "♀", with: " female ")
            .replacingOccurrences(of: "♂", with: " male ")
        var tokens: [String] = []
        var current = ""
        var afterHyphen = false
        var currentFollowsHyphen = false
        func flush() {
            guard !current.isEmpty else { return }
            if currentFollowsHyphen, let expanded = formSuffixes[current] {
                tokens.append(expanded)
            } else {
                tokens.append(LimitlessSpeciesResolver.regionWords[current] ?? current)
            }
            current = ""
        }
        for character in folded {
            if character.isASCII && (character.isLetter || character.isNumber) {
                if current.isEmpty { currentFollowsHyphen = afterHyphen }
                current.append(character)
                afterHyphen = false
            } else {
                let wordEnded = !current.isEmpty
                flush()
                afterHyphen = character == "-" && wordEnded
                if character == "," { tokens.append(",") }
            }
        }
        flush()
        return tokens
    }

    private static let formSuffixes: [String: String] = [
        "h": "hisui", "a": "alola", "g": "galar", "p": "paldea", "f": "female", "m": "male",
    ]

    /// Levenshtein distance, giving up once a row's minimum passes `cutoff`.
    private static func editDistance(_ a: String, _ b: String, cutoff: Int) -> Int {
        let x = Array(a), y = Array(b)
        if x.isEmpty { return y.count }
        if y.isEmpty { return x.count }
        var previous = Array(0...y.count)
        var current = [Int](repeating: 0, count: y.count + 1)
        for i in 1...x.count {
            current[0] = i
            var rowMin = i
            for j in 1...y.count {
                current[j] = min(previous[j] + 1, current[j - 1] + 1,
                                 previous[j - 1] + (x[i - 1] == y[j - 1] ? 0 : 1))
                rowMin = min(rowMin, current[j])
            }
            if rowMin > cutoff { return cutoff + 1 }
            swap(&previous, &current)
        }
        return previous[y.count]
    }
}
