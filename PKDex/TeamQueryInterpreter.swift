//
//  TeamQueryInterpreter.swift
//  PKDex
//
//  Reads the phrases the parser couldn't place ("hisuian fire dog",
//  "slow") with Apple Intelligence's on-device model. For each phrase the
//  model names the Pokémon, move or style it means, or none. The parser
//  then reads the description again with those names in place of the
//  phrases, so a name counts only if the parser knows it, and "no big fire
//  cat" still excludes what the phrase means. The model can't add anything
//  the description doesn't mention, and what the parser already read is
//  never changed.
//
//  The on-device model is small, and its Pokémon knowledge is patchy, so
//  what it adds is marked in the UI for the user to check. It runs only
//  when the user asks. Without Apple Intelligence (an older device, turned
//  off, or still downloading), Team Search works as before.
//

import Foundation
import FoundationModels

/// Whether the on-device model can run.
nonisolated enum TeamInterpreterAvailability: Equatable, Sendable {
    case available
    /// Apple Intelligence is turned off.
    case notEnabled
    /// The model is still downloading.
    case notReady
    /// The device can't run Apple Intelligence.
    case unsupported
}

/// A failed interpretation, with a message to show.
nonisolated struct TeamInterpretationError: LocalizedError, Equatable {
    let message: String
    var errorDescription: String? { message }
}

nonisolated protocol TeamQueryInterpreting: Sendable {
    /// Checked each time, as it changes while the model downloads or the
    /// user turns Apple Intelligence on or off.
    var availability: TeamInterpreterAvailability { get }

    /// What each phrase of a description means, by phrase: a Pokémon, move
    /// or style name, or anything else when it means none of them.
    func meanings(of phrases: [String], in description: String,
                  vocabulary: TeamSearchVocabulary) async throws -> [String: String]
}

// MARK: - Adding to a query

extension TeamQuery {

    /// Adds the species, moves and styles in `other` that neither this
    /// query nor `baseline` mentions, in either direction, and returns them
    /// as a query of their own. A species counts as mentioned in any form
    /// or as a Mega, so "Charizard" typed by the user isn't joined by
    /// "Mega Charizard Y". At most six species are included.
    ///
    /// `baseline` is the text's own parse, so what the user removed from it
    /// by editing chips doesn't come back.
    mutating func add(_ other: TeamQuery, beyond baseline: TeamQuery) -> TeamQuery {
        var added = TeamQuery()
        var speciesIDs = Set((species + excludedSpecies + baseline.species
                              + baseline.excludedSpecies).map(\.speciesID))
        for term in other.species where species.count < 6 && speciesIDs.insert(term.speciesID).inserted {
            species.append(term)
            added.species.append(term)
        }
        for term in other.excludedSpecies where speciesIDs.insert(term.speciesID).inserted {
            excludedSpecies.append(term)
            added.excludedSpecies.append(term)
        }
        var moveIDs = Set((moves + excludedMoves + baseline.moves + baseline.excludedMoves).map(\.id))
        for term in other.moves where moveIDs.insert(term.id).inserted {
            moves.append(term)
            added.moves.append(term)
        }
        for term in other.excludedMoves where moveIDs.insert(term.id).inserted {
            excludedMoves.append(term)
            added.excludedMoves.append(term)
        }
        var styleIDs = Set((archetypes + excludedArchetypes + baseline.archetypes
                            + baseline.excludedArchetypes).map(\.id))
        for style in other.archetypes where styleIDs.insert(style.id).inserted {
            archetypes.append(style)
            added.archetypes.append(style)
        }
        for style in other.excludedArchetypes where styleIDs.insert(style.id).inserted {
            excludedArchetypes.append(style)
            added.excludedArchetypes.append(style)
        }
        return added
    }
}

// MARK: - Apple Intelligence

/// The interpreter backed by the system's on-device language model.
nonisolated struct AppleIntelligenceInterpreter: TeamQueryInterpreting {

    /// Phrases read per request; any more stay unrecognized.
    static let maxPhrases = 8

    var availability: TeamInterpreterAvailability {
        switch SystemLanguageModel.default.availability {
        case .available: return .available
        case .unavailable(.appleIntelligenceNotEnabled): return .notEnabled
        case .unavailable(.modelNotReady): return .notReady
        case .unavailable: return .unsupported
        }
    }

    func meanings(of phrases: [String], in description: String,
                  vocabulary: TeamSearchVocabulary) async throws -> [String: String] {
        let phrases = Array(phrases.prefix(Self.maxPhrases))
        guard !phrases.isEmpty else { return [:] }
        do {
            let session = LanguageModelSession(model: SystemLanguageModel.default,
                                               instructions: Self.instructions(vocabulary))
            let response = try await session.respond(
                to: Self.prompt(phrases, in: description),
                schema: try Self.schema(phrases),
                options: GenerationOptions(samplingMode: .greedy,
                                           maximumResponseTokens: 40 + 24 * phrases.count))
            var meanings: [String: String] = [:]
            for (number, phrase) in zip(1..., phrases) {
                if let answer = try? response.content.value(String.self, forProperty: "phrase\(number)") {
                    meanings[phrase] = Self.cleaned(answer)
                }
            }
            return meanings
        } catch {
            throw TeamInterpretationError(message: Self.message(for: error))
        }
    }

    static func instructions(_ vocabulary: TeamSearchVocabulary) -> String {
        var lines = [
            "You help search Pokémon VGC doubles teams. A description of a team has phrases the search didn't understand. For each phrase, give the official English name of the Pokémon, move or team style it refers to, or \"none\" if it refers to none.",
            "Name a Pokémon's regional form or Mega when the phrase asks for it, as in \"Hisuian Arcanine\" or \"Mega Charizard Y\".",
            "Team styles:",
        ]
        lines += vocabulary.archetypes.map { rule in
            rule.hint.map { "- \(rule.archetype.label): \($0)" } ?? "- \(rule.archetype.label)"
        }
        return lines.joined(separator: "\n")
    }

    static func prompt(_ phrases: [String], in description: String) -> String {
        (["Description: \(description)", "Phrases:"]
         + zip(1..., phrases).map { "phrase\($0): \"\($1)\"" })
            .joined(separator: "\n")
    }

    /// One string property per phrase, named by its number.
    static func schema(_ phrases: [String]) throws -> GenerationSchema {
        let properties = zip(1..., phrases).map { number, phrase in
            DynamicGenerationSchema.Property(
                name: "phrase\(number)", description: "What \"\(phrase)\" refers to",
                schema: DynamicGenerationSchema(type: String.self))
        }
        return try GenerationSchema(root: DynamicGenerationSchema(name: "Meanings", properties: properties),
                                    dependencies: [])
    }

    /// An answer's first line, without quotes, bold marks or a full stop.
    static func cleaned(_ answer: String) -> String {
        let line = answer.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        return line.trimmingCharacters(in: CharacterSet(charactersIn: "\"'*.“”").union(.whitespaces))
    }

    static func message(for error: Error) -> String {
        if #available(iOS 27.0, *), let error = error as? LanguageModelError {
            switch error {
            case .contextSizeExceeded: return tooLong
            case .rateLimited: return busy
            case .unsupportedLanguageOrLocale: return language
            default: return generic
            }
        }
        if let error = error as? LanguageModelSession.GenerationError {
            switch error {
            case .exceededContextWindowSize: return tooLong
            case .rateLimited, .concurrentRequests: return busy
            case .unsupportedLanguageOrLocale: return language
            case .assetsUnavailable: return "Apple Intelligence isn't ready yet. Try again later."
            default: return generic
            }
        }
        return generic
    }

    private static let generic = "Apple Intelligence couldn't read this description."
    private static let tooLong = "This description is too long for Apple Intelligence. Try a shorter one."
    private static let busy = "Apple Intelligence is busy. Try again in a moment."
    private static let language = "Apple Intelligence doesn't support this language yet."
}
