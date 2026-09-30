//
//  SearchReading.swift
//  PKReference
//
//  Reads what someone typed or said to the app's search: the Pokémon, forms
//  and moves it names, in order, and the investment words beside each
//  Pokémon. "mega gardevoir hyper voice vs max investment rillaboom" is
//  Mega Gardevoir, Hyper Voice and Rillaboom, with full investment on
//  Rillaboom, so the search can open the damage calc on that matchup.
//  Names match as `IntentNames` keys, so case, accents, spaces and
//  punctuation don't matter.
//

import Foundation

nonisolated struct SearchReading: Equatable {
    enum Kind: Equatable {
        case pokemon
        case move
    }

    /// A name found in the text: what it names, and which words it spans.
    struct Span: Equatable {
        let kind: Kind
        let id: Int
        let words: Range<Int>
    }

    /// The names found, in the order they appear.
    let spans: [Span]
    /// The investment said for each Pokémon found, by its span's position
    /// in `spans`.
    let investments: [Int: IntentNames.Investment]

    var pokemon: [Span] { spans.filter { $0.kind == .pokemon } }
    var moves: [Span] { spans.filter { $0.kind == .move } }

    /// The investment said for a Pokémon found, if any.
    func investment(of span: Span) -> IntentNames.Investment? {
        spans.firstIndex(of: span).flatMap { investments[$0] }
    }

    /// The longest name a run of words spells. Pokémon and move names run
    /// to four words ("Tauros Paldea Combat Breed").
    static let longestName = 4

    /// Reads `text` against Pokémon and moves keyed by `IntentNames.key`.
    /// At each word the longest name starting there wins; a Pokémon wins a
    /// tie. Words between names are left for the investments: the words
    /// before a Pokémon, and before a move that follows it, are that
    /// Pokémon's; the words after the last name are the last Pokémon's.
    init(_ text: String, pokemon: [String: Int], moves: [String: Int]) {
        // Apostrophes and hyphens stay inside names ("Farfetch'd",
        // "U-turn"), and "+" inside "252+", which says the nature.
        let words = text.split(whereSeparator: { !$0.isLetter && !$0.isNumber && !"'-+".contains($0) })
            .map(String.init)
        let keys = words.map(IntentNames.key)

        var spans: [Span] = []
        var index = 0
        while index < keys.count {
            var best: Span?
            for length in stride(from: min(Self.longestName, keys.count - index), through: 1, by: -1) {
                let key = keys[index..<index + length].joined()
                if let id = pokemon[key] {
                    best = Span(kind: .pokemon, id: id, words: index..<index + length)
                } else if let id = moves[key] {
                    best = Span(kind: .move, id: id, words: index..<index + length)
                }
                if best != nil { break }
            }
            if let best {
                spans.append(best)
                index = best.words.upperBound
            } else {
                index += 1
            }
        }
        self.spans = spans

        // Each gap between names goes to a Pokémon, as above.
        var said: [Int: [String]] = [:]
        var previousEnd = 0
        var lastPokemon: Int?
        for (position, span) in spans.enumerated() {
            let gap = Array(words[previousEnd..<span.words.lowerBound])
            if span.kind == .pokemon {
                said[position, default: []] += gap
                lastPokemon = position
            } else if let owner = lastPokemon {
                said[owner, default: []] += gap
            }
            previousEnd = span.words.upperBound
        }
        if let owner = lastPokemon {
            said[owner, default: []] += words[previousEnd...]
        }
        investments = said.compactMapValues { IntentNames.investment(said: $0.joined(separator: " ")) }
    }
}
