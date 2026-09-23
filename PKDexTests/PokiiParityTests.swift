//
//  PokiiParityTests.swift
//  PKDexTests
//
//  Byte-for-byte parity check between the MLX training notebook and the
//  Swift inference path. Reads `pokii_parity_samples.json` (dumped by the
//  notebook via pokii_dump_parity_samples.py) and re-runs each sample
//  through PokiiBattler.shared.chooseAction(...). The sample provides the
//  *post-featurization* tensors (x_cat, x_cont) and the legal-action set,
//  so this suite isolates the forward pass — embedding lookup, two
//  Linears + ReLUs, action_head argmax, mega_head sigmoid — from any
//  Swift-side featurization drift. The PokiiFeaturizer tests cover that.
//
//  If the JSON isn't bundled (you haven't re-dumped after a retrain yet),
//  the suite emits a single warning and skips — it never fails for absence.
//

import Testing
import Foundation
@testable import PKDex

// MARK: - JSON shape (matches pokii_dump_parity_samples.py)

private struct ParitySample: Decodable {
    let description: String
    let test_index: Int
    let x_cat: [Int]
    let x_cont: [Float]
    let legal_indices: [Int]
    let argmax_index: Int
    let argmax_label: String
    let mega_logit: Float
    let mega_probability: Float
}

private struct ParitySampleConfig: Decodable {
    let n_classes: Int
    let n_species: Int
    let cont_dim: Int
    let n_slots: Int
    let emb_dim: Int
    let hidden: Int
}

private struct ParitySamplesFile: Decodable {
    let config: ParitySampleConfig
    let samples: [ParitySample]
}

// MARK: - Loader

@MainActor
private enum ParityFixture {
    /// Returns the loaded samples file, or `nil` if the bundle doesn't
    /// include `pokii_parity_samples.json` yet.
    static func load() -> ParitySamplesFile? {
        guard let url = Bundle.main.url(forResource: "pokii_parity_samples",
                                        withExtension: "json") else {
            return nil
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(ParitySamplesFile.self, from: data)
        } catch {
            Issue.record("Failed to decode pokii_parity_samples.json: \(error)")
            return nil
        }
    }

    /// Rebuild the additive mask the notebook used: 0.0 at legal indices,
    /// `-1e9` everywhere else. Building the mask Swift-side from the dumped
    /// `legal_indices` keeps this test focused on the forward pass — mask
    /// *construction* parity is covered by PokiiFeaturizerMaskTests.
    static func mask(legal: [Int], nClasses: Int) -> [Float] {
        var m = [Float](repeating: -1e9, count: nClasses)
        for j in legal where (0..<nClasses).contains(j) {
            m[j] = 0.0
        }
        return m
    }
}

// MARK: - Tests

@MainActor
@Suite("Pokii Battler — MLX/Swift Forward-Pass Parity")
struct PokiiBattlerParityTests {

    @Test func bundleConfigMatchesNotebookConfig() {
        guard let file = ParityFixture.load() else {
            // No fixture bundled yet — pass silently rather than failing the
            // suite. Re-run pokii_dump_parity_samples.py from the notebook
            // and add the JSON to the app target to enable this check.
            print("[Parity] pokii_parity_samples.json not bundled — skipping config check.")
            return
        }
        _ = PokiiBattler.shared.ensureLoaded()
        let m = PokiiBattler.shared
        let c = file.config
        // If the bundled model and the parity dump disagree on shape, the
        // dump came from a different training run than the current weights.
        // Catching that here is much friendlier than a logits mismatch.
        #expect(c.n_classes == m.nClasses,
                "n_classes drift: bundle=\(m.nClasses), dump=\(c.n_classes)")
        #expect(c.n_species == m.species2idx.count,
                "n_species drift: bundle=\(m.species2idx.count), dump=\(c.n_species)")
        #expect(c.cont_dim  == m.contDim,
                "cont_dim drift: bundle=\(m.contDim), dump=\(c.cont_dim)")
        #expect(c.n_slots   == m.nSlots,
                "n_slots drift: bundle=\(m.nSlots), dump=\(c.n_slots)")
        #expect(c.emb_dim   == m.embDim,
                "emb_dim drift: bundle=\(m.embDim), dump=\(c.emb_dim)")
        #expect(c.hidden    == m.hidden,
                "hidden drift: bundle=\(m.hidden), dump=\(c.hidden)")
    }

    @Test func argmaxAndMegaProbabilityMatchNotebook() {
        guard let file = ParityFixture.load() else {
            print("[Parity] pokii_parity_samples.json not bundled — skipping forward-pass check.")
            return
        }
        _ = PokiiBattler.shared.ensureLoaded()
        let m = PokiiBattler.shared
        #expect(!file.samples.isEmpty, "parity dump should contain at least one sample")

        // Per-sample tolerances: 1e-4 on probability matches the integration
        // guide's recommendation; argmax must agree exactly.
        let megaTol: Float = 1e-4

        for (i, s) in file.samples.enumerated() {
            // Each sample's contract must match the *current* model dims
            // before we even forward — otherwise we'd be feeding garbage.
            #expect(s.x_cat.count == m.nSlots,
                    "sample \(i): x_cat len \(s.x_cat.count) ≠ n_slots \(m.nSlots)")
            #expect(s.x_cont.count == m.contDim,
                    "sample \(i): x_cont len \(s.x_cont.count) ≠ cont_dim \(m.contDim)")

            let mask = ParityFixture.mask(legal: s.legal_indices, nClasses: m.nClasses)
            guard let decision = m.chooseAction(xCat: s.x_cat,
                                                xCont: s.x_cont,
                                                mask: mask) else {
                Issue.record("sample \(i) (\(s.description)): chooseAction returned nil")
                continue
            }

            // Argmax must agree exactly — even a single off-by-one one-hot
            // in the meta block shifts the top logit, so this catches the
            // exact bug class the parity test is meant to catch.
            #expect(decision.label == s.argmax_label,
                    "sample \(i) (\(s.description)): argmax label drift. swift=\(decision.label), notebook=\(s.argmax_label)")
            if let swiftIdx = m.actionVocab.firstIndex(of: decision.label) {
                #expect(swiftIdx == s.argmax_index,
                        "sample \(i): argmax index drift. swift=\(swiftIdx), notebook=\(s.argmax_index)")
            }

            // Mega head: ~1e-4 absolute tolerance is plenty given f32 and a
            // tiny network. If this fails the issue is almost always that
            // mega_head.weight/bias didn't load (or were transposed).
            let diff = abs(decision.megaProbability - s.mega_probability)
            #expect(diff < megaTol,
                    "sample \(i) (\(s.description)): mega prob drift \(diff). swift=\(decision.megaProbability), notebook=\(s.mega_probability)")
        }
    }
}
