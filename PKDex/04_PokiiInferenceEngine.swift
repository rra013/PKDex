//
//  PokiiInferenceEngine.swift
//  PKReference
//
//  Runs the on-device Pokii model via MLX Swift. Owns the retry loop that
//  wires together the normalizer, the model, and the validator — mirroring
//  what test_prompt.py does in the training repo.
//
//  Requires the mlx-swift-examples package, added via Swift Package Manager:
//
//    https://github.com/ml-explore/mlx-swift-examples
//
//  Specifically the `MLXLLM` and `MLXLMCommon` products. In Xcode:
//    File → Add Package Dependencies → paste URL above → check MLXLLM,
//    MLXLMCommon, MLXTokenizers.
//

import Foundation
import Combine
@preconcurrency import MLX
@preconcurrency import MLXLLM
@preconcurrency import MLXLMCommon
@preconcurrency import MLXHuggingFace
// Required by the `#huggingFaceTokenizerLoader()` macro: it expands to code
// that calls `Tokenizers.AutoTokenizer.from(modelFolder:)`. Provided by
// the swift-transformers package
// (https://github.com/huggingface/swift-transformers).
import Tokenizers

// MARK: - Top-level engine

/// Singleton that loads the model once and serves generation requests.
/// Marked @MainActor for state updates; actual generation runs in detached
/// tasks so the UI never blocks.
@MainActor
public final class PokiiInferenceEngine: ObservableObject {
    public static let shared = PokiiInferenceEngine()

    // MARK: Observable state

    @Published public private(set) var state: State = .notDownloaded

    public enum State: Equatable {
        case notDownloaded
        case downloading(progress: Double)
        case downloaded
        case loading
        case ready
        case generating
        case failed(String)
    }

    // MARK: Dependencies

    private var validator: ChampionsValidator?
    private var modelContainer: ModelContainer?

    // MARK: Configuration

    /// Bumped when shipping a new adapter version. Matches the directory
    /// suffix written by PokiiModelDownloader.
    public static let modelVersion = "v2-q4"

    /// Tuning knobs for generation. Mirrors test_prompt.py defaults.
    public struct GenerationConfig: Sendable {
        public var maxTokens: Int = 384
        public var temperature: Float = 0.2
        public var topP: Float = 0.95
        /// Applied only when mode collapse is detected (this attempt's
        /// raw output is byte-identical to the previous attempt's). Held
        /// constant otherwise — uniformly raising temp to fix narrow
        /// errors degrades species/move fidelity.
        public var temperatureRetryBump: Float = 0.15
        public var maxRetries: Int = 4

        public nonisolated init() {}
    }

    /// Result of a generateSet call. Includes the final set plus any
    /// informational messages the UI should surface to the user — e.g.
    /// "the model went 2 SP over budget, we trimmed Speed to keep you
    /// at the cap" or "you have 4 unspent SP to allocate."
    public struct GenerationResult {
        public let set: PokemonSet
        /// Number of generation attempts used (1-based).
        public let attempts: Int
        /// Description of any SP clipping that was applied, or nil.
        public let clipMessage: String?
        /// Description of any unspent SP budget, or nil.
        public let budgetNote: String?
        /// Any unresolved validator violations after retries + clipping.
        /// Empty on a clean run.
        public let unresolvedViolations: [Violation]

        public var hasInfoMessages: Bool {
            clipMessage != nil || budgetNote != nil
        }
    }

    /// System prompt — must match exactly what the model was trained
    /// against. This is the SYSTEM_PROMPT_SET string from
    /// scripts/generate_dataset_champions.py in the training repo. Any
    /// drift here (extra whitespace, paraphrasing) degrades output quality
    /// because the adapter was conditioned on this specific text.
    ///
    /// Two corrections vs. the original training-time prompt:
    /// 1. "total ≤ 66" instead of "total = 66" — the rule is a cap, not
    ///    an exact requirement; saying "= 66" was causing the model to
    ///    overshoot to 68 rather than undershoot.
    /// 2. "explanation" field dropped from the schema — the trained model
    ///    produces it inconsistently, so we don't show or require it.
    public static let systemPrompt = """
    You are a competitive Pokémon team-building assistant specializing in Pokémon Champions Regulation M-A. When asked to build a single Pokémon set, respond ONLY with valid JSON in this exact format:

    {
      "name": "Pokemon Name",
      "item": "Item Name",
      "ability": "Ability Name",
      "nature": "Nature Name",
      "stat_points": {"hp": 0, "atk": 0, "def": 0, "spa": 0, "spd": 0, "spe": 0},
      "moves": ["Move 1", "Move 2", "Move 3", "Move 4"],
      "role": "Brief role description"
    }

    Champions M-A rules:
    - Stat Points (SP) replace EVs: total ≤ 66, max 32 per stat, IVs locked at 31.
    - Only Mega Evolution is available (no Tera, no Dynamax, no Z-Moves).
    - Legal items: 30 generic items (Choice Scarf, Focus Sash, Leftovers, type boosters, etc.), 28 berries, and Mega Stones. No Choice Band/Specs, Life Orb, Assault Vest, or Heavy-Duty Boots.
    - Movesets follow the Champions Pokédex (different from mainline games).
    - Mega Stones must match the holder's species.
    """

    private init() {
        refreshDownloadState()
    }

    // MARK: Download state sync (called from UI on appear)

    public func refreshDownloadState() {
        if PokiiModelDownloader.shared.isModelInstalled(version: Self.modelVersion) {
            if case .notDownloaded = state {
                state = .downloaded
            }
        } else {
            if case .ready = state { state = .notDownloaded }
            if case .downloaded = state { state = .notDownloaded }
        }
    }

    // MARK: Model loading

    /// Load the model into memory. Slow (10-20s on first call); subsequent
    /// calls return immediately. Throws if the model isn't downloaded or
    /// MLX initialization fails.
    public func load() async throws {
        if modelContainer != nil {
            state = .ready
            return
        }
        guard PokiiModelDownloader.shared.isModelInstalled(
            version: Self.modelVersion) else {
            throw EngineError.modelNotDownloaded
        }

        state = .loading

        // Load validator (cheap, ~50ms)
        if self.validator == nil {
            guard let v = ChampionsValidator() else {
                state = .failed("Failed to load validator data")
                throw EngineError.validatorLoadFailed
            }
            self.validator = v
        }

        let modelDir = PokiiModelDownloader.shared.modelDirectory(
            version: Self.modelVersion)

        do {
            // Local-directory loader. The HF tokenizer loader macro provides
            // the Tokenizers.AutoTokenizer-backed loader so the bundled
            // tokenizer.json under `modelDir` is picked up.
            let container = try await LLMModelFactory.shared.loadContainer(
                from: modelDir,
                using: #huggingFaceTokenizerLoader()
            )
            self.modelContainer = container
            state = .ready
        } catch {
            state = .failed("Model load failed: \(error.localizedDescription)")
            throw EngineError.modelLoadFailed(underlying: error)
        }
    }

    /// Free the model from memory. Useful when the user navigates away from
    /// the AI builder and you want to reclaim ~4 GB of RAM.
    public func unload() {
        modelContainer = nil
        if case .ready = state { state = .downloaded }
        if case .generating = state { state = .downloaded }
    }

    // MARK: Generation

    public enum EngineError: Error, LocalizedError {
        case modelNotDownloaded
        case modelLoadFailed(underlying: Error)
        case validatorLoadFailed
        case notReady
        case allRetriesExhausted(lastErrors: [String])
        case generationFailed(String)

        public var errorDescription: String? {
            switch self {
            case .modelNotDownloaded:
                return "Model isn't downloaded yet. " +
                       "Go to Settings → AI Builder to download it."
            case .modelLoadFailed(let err):
                return "Failed to load model: \(err.localizedDescription)"
            case .validatorLoadFailed:
                return "Failed to load validator data from app bundle."
            case .notReady:
                return "Model isn't ready. Call load() first."
            case .allRetriesExhausted(let errs):
                return "All retries failed. Last attempt: " +
                       (errs.last ?? "no detail")
            case .generationFailed(let s):
                return "Generation failed: \(s)"
            }
        }
    }

    /// Generate a single Pokemon set from a user prompt. Runs the full
    /// pipeline: normalize → generate → validate → retry (up to N) with
    /// mode-collapse-only temperature bumps and violation feedback. After
    /// retries are exhausted, applies SP clipping to recover from small
    /// over-budget allocations, then returns the result with metadata.
    ///
    /// `onProgress` fires after each attempt with the attempt number and the
    /// raw model output (mostly for debugging UIs).
    public func generateSet(
        userPrompt: String,
        config: GenerationConfig = GenerationConfig(),
        onProgress: ((Int, String) -> Void)? = nil
    ) async throws -> GenerationResult {
        guard let container = modelContainer, let validator = self.validator
        else { throw EngineError.notReady }

        state = .generating
        defer { state = .ready }

        // 1. Normalize the prompt
        let normalized = normalizePrompt(
            userPrompt, speciesWhitelist: validator.speciesWhitelist
        )

        var lastErrors: [String] = []
        var feedbackPostscript: String? = nil
        var prevRaw: String? = nil
        var bumpCount = 0
        // Track the most recent parsed set + its violations so that if we
        // exhaust retries we can still apply clipping and return something
        // useful rather than throwing.
        var lastSet: PokemonSet? = nil
        var lastViolations: [Violation] = []
        var attemptsUsed = 0

        for attempt in 0..<config.maxRetries {
            attemptsUsed = attempt + 1
            // Temp bump only fires when the previous response was a
            // byte-identical lock-in. Otherwise hold the configured temp.
            let temp = config.temperature
                     + (Float(bumpCount) * config.temperatureRetryBump)
            let userText: String = {
                if let fb = feedbackPostscript {
                    return normalized.text + "\n\n[Previous attempt had issues: " +
                           fb + " — please fix.]"
                }
                return normalized.text
            }()

            let raw = try await runGeneration(
                container: container,
                userText: userText,
                temperature: temp,
                topP: config.topP,
                maxTokens: config.maxTokens
            )
            onProgress?(attempt + 1, raw)

            // Mode-collapse detection: if this response matches the previous
            // verbatim, the feedback isn't moving the model. Bump applies to
            // the NEXT attempt's sampling.
            if let prev = prevRaw,
               raw.trimmingCharacters(in: .whitespacesAndNewlines)
                   == prev.trimmingCharacters(in: .whitespacesAndNewlines) {
                bumpCount += 1
            }
            prevRaw = raw

            // Extract JSON from the raw output (handles cases where the
            // model emits a code fence or trailing whitespace despite the
            // system prompt). The extractor is permissive — finds the first
            // balanced { ... }.
            guard let json = extractJSON(from: raw),
                  let set = PokemonSet.parse(json) else {
                lastErrors.append("Could not parse JSON from output")
                feedbackPostscript = "your previous output wasn't valid JSON"
                continue
            }

            let violations = validator.validate(set: set)
            let constraintViolations = checkPromptConstraints(
                normalized: normalized, set: set)
            let allViolations = violations + constraintViolations
            lastSet = set
            lastViolations = allViolations

            if allViolations.isEmpty {
                // Clean run — still surface a budget note if the model
                // underspent SP, since that's user-actionable info.
                return GenerationResult(
                    set: set,
                    attempts: attempt + 1,
                    clipMessage: nil,
                    budgetNote: set.statPointBudgetNote,
                    unresolvedViolations: []
                )
            }

            // Format feedback for the next retry. Keep it short — long
            // feedback dilutes the conditioning signal.
            let topThree = allViolations.prefix(3).map(\.message)
                .joined(separator: "; ")
            feedbackPostscript = topThree
            lastErrors.append(topThree)
        }

        // Retries exhausted. Try to salvage with SP clipping before failing.
        guard var set = lastSet else {
            throw EngineError.allRetriesExhausted(lastErrors: lastErrors)
        }

        let clip = set.clipStatPointsToCap()
        // Re-validate after clipping; remove any over-cap violations that
        // are now resolved. Leave other categories untouched — clipping
        // only fixes one specific failure mode.
        var remaining = lastViolations
        if clip.didClip {
            remaining = remaining.filter {
                $0.category != .statPointsOverCap
            }
        }

        return GenerationResult(
            set: set,
            attempts: attemptsUsed,
            clipMessage: clip.message,
            budgetNote: set.statPointBudgetNote,
            unresolvedViolations: remaining
        )
    }

    // MARK: - Private generation primitive

    private func runGeneration(
        container: ModelContainer,
        userText: String,
        temperature: Float,
        topP: Float,
        maxTokens: Int
    ) async throws -> String {
        let messages: [[String: any Sendable]] = [
            ["role": "system", "content": Self.systemPrompt],
            ["role": "user", "content": userText],
        ]

        let lmInput = try await container.prepare(
            input: UserInput(messages: messages)
        )

        let parameters = GenerateParameters(
            maxTokens: maxTokens,
            temperature: temperature,
            topP: topP
        )

        let stream = try await container.generate(
            input: lmInput,
            parameters: parameters
        )

        var fullOutput = ""
        for await event in stream {
            if case .chunk(let text) = event {
                fullOutput += text
            }
        }
        return fullOutput
    }

    // MARK: - JSON extraction

    /// Find the first balanced JSON object in the raw text. Handles
    /// ```json fences```, leading prose, trailing prose, and partial code
    /// blocks. Returns nil if no balanced object found.
    private func extractJSON(from raw: String) -> String? {
        // Strip code fences
        var text = raw
        if let fenceStart = text.range(of: "```json") {
            text = String(text[fenceStart.upperBound...])
        } else if let fenceStart = text.range(of: "```") {
            text = String(text[fenceStart.upperBound...])
        }
        if let fenceEnd = text.range(of: "```") {
            text = String(text[..<fenceEnd.lowerBound])
        }

        // Find first { and the matching balanced }
        guard let start = text.firstIndex(of: "{") else { return nil }
        var depth = 0
        var i = start
        while i < text.endIndex {
            let c = text[i]
            if c == "{" { depth += 1 }
            else if c == "}" {
                depth -= 1
                if depth == 0 {
                    return String(text[start...i])
                }
            }
            i = text.index(after: i)
        }
        return nil
    }

    // MARK: - Prompt constraint enforcement (extends validator violations)

    private func checkPromptConstraints(
        normalized: NormalizedPrompt,
        set: PokemonSet
    ) -> [Violation] {
        var v: [Violation] = []
        let moveNamesLower = Set(set.moves.map { $0.lowercased() })

        // User asked for no Trick Room, model included it
        if normalized.qualifiers.contains("no_setup") {
            if moveNamesLower.contains("trick room") {
                v.append(.init(category: .choiceSetupConflict,
                    message: "Prompt excluded setup moves but set has Trick Room"))
            }
        }
        // User excluded specific moves
        for exclusion in normalized.exclusions {
            if moveNamesLower.contains(exclusion.lowercased()) {
                v.append(.init(category: .illegalMoves,
                    message: "Prompt excluded \(exclusion) but set includes it"))
            }
        }
        // Bulk vs offense: heuristic on stat point distribution
        if normalized.qualifiers.contains("bulky") {
            let sp = set.statPoints
            let defensive = sp.hp + sp.def + sp.spd
            let offensive = sp.atk + sp.spa + sp.spe
            if offensive > defensive * 2 {
                v.append(.init(category: .wastedStatPoints,
                    message: "Prompt asked for bulky but stat points are " +
                             "mostly offensive (off=\(offensive) def=\(defensive))"))
            }
        }
        if normalized.qualifiers.contains("scarf") {
            if set.item != "Choice Scarf" {
                v.append(.init(category: .choiceSetupConflict,
                    message: "Prompt asked for Choice Scarf but item is " +
                             (set.item ?? "none")))
            }
        }
        return v
    }
}
