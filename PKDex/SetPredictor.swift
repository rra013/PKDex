//
//  SetPredictor.swift
//  PKDex
//
//  Forward pass + UI for the small "name + qualifier → full set" MLP that
//  replaces the on-device LLM single-set builder.
//
//  Model architecture (from `name_qual_full_set_trainer.ipynb`):
//      input  : name_emb(32) || qual_emb(8) || base_stats(6)   →  (46,)
//      shared : Linear(46→256) → ReLU → Linear(256→128) → ReLU →  (128,)
//      heads  : item(139), ability(135), nature(15), stats(6), moves(336)
//
//  Decoding mirrors the notebook's `predict_set`:
//      - ability head argmaxed only over legal abilities (per-species mask)
//      - moves head top-4 only over legal moves (per-species mask)
//      - item / nature: plain argmax
//      - stats: round(stats * 32), then renormalize_to_66 (single-attacker
//        invariant + sum exactly 66)
//

import SwiftUI

// MARK: - Engine

@MainActor @Observable
final class SetPredictor {
    static let shared = SetPredictor()

    /// One of the six qualifiers the model was trained on (alphabetical).
    enum Qualifier: String, CaseIterable, Identifiable {
        case competitive      = "Competitive"
        case defensive        = "Defensive"
        case offensive        = "Offensive"
        case setup            = "Setup"
        case slowAttacker     = "Slow Attacker"
        case trickRoomSetter  = "Trick Room Setter"
        var id: String { rawValue }
    }

    // Loaded lazily on first use so the bundle isn't touched at app launch.
    private(set) var isReady: Bool = false
    @ObservationIgnored private var loaded: Loaded?

    private struct Loaded {
        let names: PokiiVocab
        let qualifiers: PokiiVocab
        let items: PokiiVocab
        let abilities: PokiiVocab
        let natures: PokiiVocab
        let moves: PokiiVocab
        // Weights
        let nameEmb: NPYTensor
        let qualEmb: NPYTensor
        let shared0W: NPYTensor; let shared0B: NPYTensor   // (256, 46), (256,)
        let shared2W: NPYTensor; let shared2B: NPYTensor   // (128, 256), (128,)
        let itemW: NPYTensor;    let itemB: NPYTensor      // (139, 128)
        let abilityW: NPYTensor; let abilityB: NPYTensor   // (135, 128)
        let natureW: NPYTensor;  let natureB: NPYTensor    // (15, 128)
        let statsW: NPYTensor;   let statsB: NPYTensor     // (6, 128)
        let movesW: NPYTensor;   let movesB: NPYTensor     // (336, 128)
        // Per-species cached features
        let baseStats: [String: [Float]]      // length 6, divided by 255
        let moveMask: [String: [Float]]       // length 336, 1.0 where move is legal
        let abilityMask: [String: [Float]]    // length 135
    }

    /// Sorted list of species the model knows about. Use this to populate the
    /// picker — anything outside this list can't be encoded.
    var knownSpecies: [String] { loaded?.names.classes ?? [] }

    /// Map a local Pokedex name onto the model's species vocab when possible.
    /// Tries an exact case-insensitive match first; if that misses, strips
    /// regional/form suffixes (e.g. "Aegislash-Shield" → "Aegislash") and
    /// retries — the model is trained on base species names per the Champions
    /// learnset JSON, so form-specific PKMNStats rows need this collapse to
    /// resolve. Returns nil if nothing matches.
    func canonicalModelSpecies(for localName: String) -> String? {
        guard let names = loaded?.names.classes, !names.isEmpty else { return nil }
        let target = localName.lowercased()
        if let hit = names.first(where: { $0.lowercased() == target }) {
            return hit
        }
        if let dash = localName.firstIndex(of: "-") {
            let base = String(localName[..<dash]).lowercased()
            if let hit = names.first(where: { $0.lowercased() == base }) {
                return hit
            }
        }
        return nil
    }

    /// Lazy load. Safe to call repeatedly; only does the work once.
    func loadIfNeeded() throws {
        if loaded != nil { return }
        guard let weightsURL = Bundle.main.url(forResource: "name_qual_weights",
                                               withExtension: "npz") else {
            throw PokiiLiteError.missingResource("name_qual_weights.npz")
        }
        guard let vocabURL = Bundle.main.url(forResource: "name_qual_vocab",
                                              withExtension: "json") else {
            throw PokiiLiteError.missingResource("name_qual_vocab.json")
        }
        let npz = try NPZArchive(url: weightsURL)
        let vocabData = try Data(contentsOf: vocabURL)
        let vocab = try JSONDecoder().decode(VocabJSON.self, from: vocabData)

        let names      = PokiiVocab(classes: vocab.names,      hasUNK: false)
        let quals      = PokiiVocab(classes: vocab.qualifiers, hasUNK: false)
        let items      = PokiiVocab(classes: vocab.items,      hasUNK: false)
        let abilities  = PokiiVocab(classes: vocab.abilities,  hasUNK: false)
        let natures    = PokiiVocab(classes: vocab.natures,    hasUNK: false)
        let moves      = PokiiVocab(classes: vocab.moves,      hasUNK: false)

        // Per-species feature derivation walks the learnset JSON the same
        // way the notebook does: union base + alternate forms (+ megas for
        // abilities). Pulled from ChampionsLearnsetStore so the bundled file
        // is only parsed once across the app.
        let store = ChampionsLearnsetStore.shared
        var baseStats: [String: [Float]] = [:]
        var moveMask: [String: [Float]] = [:]
        var abilityMask: [String: [Float]] = [:]
        for species in vocab.names {
            guard let entry = store.data(for: species) else {
                // Without base stats we can still embed by name, but the stat
                // input would be zeros — that mismatches training. Bail loudly
                // so the missing species is obvious during dev.
                throw PokiiLiteError.invalidNPY("learnset missing species \(species)")
            }
            baseStats[species] = [Float(entry.stats.hp), Float(entry.stats.atk),
                                  Float(entry.stats.def), Float(entry.stats.spa),
                                  Float(entry.stats.spd), Float(entry.stats.spe)].map { $0 / 255.0 }

            // Move union: base + alternate_forms (megas don't add moves)
            var legalMoves = Set(entry.moves)
            for f in entry.alternateForms { legalMoves.formUnion(f.moves ?? []) }
            var mvec = [Float](repeating: 0, count: vocab.moves.count)
            for m in legalMoves {
                if let i = moves.strictIndex(of: m) { mvec[i] = 1 }
            }
            moveMask[species] = mvec

            // Ability union: base + alternate_forms + megas
            var legalAbils = Set(entry.abilities)
            for f in entry.alternateForms { legalAbils.formUnion(f.abilities) }
            for m in entry.megas          { legalAbils.formUnion(m.abilities) }
            var avec = [Float](repeating: 0, count: vocab.abilities.count)
            for a in legalAbils {
                if let i = abilities.strictIndex(of: a) { avec[i] = 1 }
            }
            abilityMask[species] = avec
        }

        loaded = Loaded(
            names: names, qualifiers: quals, items: items,
            abilities: abilities, natures: natures, moves: moves,
            nameEmb:  try npz.loadTensor("name_emb.weight.npy"),
            qualEmb:  try npz.loadTensor("qual_emb.weight.npy"),
            shared0W: try npz.loadTensor("shared.layers.0.weight.npy"),
            shared0B: try npz.loadTensor("shared.layers.0.bias.npy"),
            shared2W: try npz.loadTensor("shared.layers.2.weight.npy"),
            shared2B: try npz.loadTensor("shared.layers.2.bias.npy"),
            itemW:    try npz.loadTensor("item_head.weight.npy"),
            itemB:    try npz.loadTensor("item_head.bias.npy"),
            abilityW: try npz.loadTensor("ability_head.weight.npy"),
            abilityB: try npz.loadTensor("ability_head.bias.npy"),
            natureW:  try npz.loadTensor("nature_head.weight.npy"),
            natureB:  try npz.loadTensor("nature_head.bias.npy"),
            statsW:   try npz.loadTensor("stats_head.weight.npy"),
            statsB:   try npz.loadTensor("stats_head.bias.npy"),
            movesW:   try npz.loadTensor("moves_head.weight.npy"),
            movesB:   try npz.loadTensor("moves_head.bias.npy"),
            baseStats: baseStats,
            moveMask: moveMask,
            abilityMask: abilityMask
        )
        isReady = true
    }

    /// Returns a fully-formed set, or nil if the inputs aren't representable
    /// (unknown species — out-of-vocab names can't be embedded).
    func predict(species: String, qualifier: Qualifier) -> PokemonSet? {
        try? loadIfNeeded()
        guard let L = loaded,
              let nameIdx = L.names.index(of: species),
              let qualIdx = L.qualifiers.index(of: qualifier.rawValue),
              let baseStats = L.baseStats[species],
              let mvMask    = L.moveMask[species],
              let abMask    = L.abilityMask[species]
        else { return nil }

        // x = concat(name_emb, qual_emb, base_stats)
        var x = PokiiNN.embed(table: L.nameEmb, index: nameIdx)
        x.append(contentsOf: PokiiNN.embed(table: L.qualEmb, index: qualIdx))
        x.append(contentsOf: baseStats)

        var h = PokiiNN.linear(weight: L.shared0W, bias: L.shared0B, input: x)
        PokiiNN.relu(&h)
        h     = PokiiNN.linear(weight: L.shared2W, bias: L.shared2B, input: h)
        PokiiNN.relu(&h)

        let itemLogits   = PokiiNN.linear(weight: L.itemW,    bias: L.itemB,    input: h)
        let abilLogits   = PokiiNN.linear(weight: L.abilityW, bias: L.abilityB, input: h)
        let natureLogits = PokiiNN.linear(weight: L.natureW,  bias: L.natureB,  input: h)
        let statsLogits  = PokiiNN.linear(weight: L.statsW,   bias: L.statsB,   input: h)
        let movesLogits  = PokiiNN.linear(weight: L.movesW,   bias: L.movesB,   input: h)

        // Decode heads.
        let item   = L.items.classes[PokiiNN.argmax(itemLogits)]
        let nature = L.natures.classes[PokiiNN.argmax(natureLogits)]
        let abilIdx = PokiiNN.maskedArgmax(abilLogits, mask: abMask)
        let ability = abilIdx >= 0 ? L.abilities.classes[abilIdx]
                                   : (L.abilities.classes.first ?? "")
        let topMoves = PokiiNN.maskedTopK(movesLogits, mask: mvMask, k: 4)
                       .map { L.moves.classes[$0] }

        let rawStats = statsLogits.map { Int(($0 * 32).rounded()) }
        let norm = PokiiStatNorm.renormalizeTo66(rawStats)

        let sp = PokemonSet.StatPoints(hp: norm[0], atk: norm[1], def: norm[2],
                                        spa: norm[3], spd: norm[4], spe: norm[5])
        return PokemonSet(species: species,
                          ability: ability,
                          item: item,
                          nature: nature,
                          teraType: nil,
                          moves: topMoves,
                          statPoints: sp,
                          role: qualifier.rawValue,
                          usedEVFormat: false)
    }

    // MARK: JSON shape

    private struct VocabJSON: Decodable {
        let names: [String]
        let qualifiers: [String]
        let items: [String]
        let abilities: [String]
        let natures: [String]
        let moves: [String]
    }
}

// MARK: - UI

/// Drop-in replacement for the old AIBuilderButton (single set mode). Opens
/// a much simpler sheet — name + qualifier, no free-text prompt, no retries.
///
/// `initialSpecies` is the local Pokedex name of whatever the user has already
/// picked in the parent sheet (if anything). The predictor sheet maps it onto
/// the model's species vocab via `canonicalModelSpecies` so a user who has
/// already chosen e.g. "Aegislash-Shield" lands on "Aegislash" without having
/// to retype it.
struct SetPredictorButton: View {
    var initialSpecies: String? = nil
    let onCompletion: (PokemonSet) -> Void
    @State private var showingSheet = false

    var body: some View {
        Button {
            showingSheet = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                Text("Predict Set")
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 12).padding(.vertical, 7)
            .foregroundStyle(.white)
            .background(
                LinearGradient(colors: [.purple, .pink],
                               startPoint: .topLeading,
                               endPoint: .bottomTrailing),
                in: Capsule()
            )
        }
        .sheet(isPresented: $showingSheet) {
            SetPredictorSheet(initialSpecies: initialSpecies) { set in
                onCompletion(set)
                showingSheet = false
            }
        }
    }
}

struct SetPredictorSheet: View {
    var initialSpecies: String? = nil
    let onUse: (PokemonSet) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var predictor = SetPredictor.shared
    @State private var query = ""
    @State private var selectedSpecies: String?
    @State private var qualifier: SetPredictor.Qualifier = .offensive
    @State private var result: PokemonSet?
    @State private var loadError: String?

    private var filteredSpecies: [String] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        return predictor.knownSpecies
            .filter { $0.lowercased().contains(q) }
            .prefix(15)
            .map { $0 }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Pokemon") {
                    if let species = selectedSpecies {
                        HStack {
                            Text(species).font(.headline)
                            Spacer()
                            Button {
                                selectedSpecies = nil
                                query = ""
                                result = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        TextField("Search…", text: $query)
                            .textInputAutocapitalization(.words)
                        ForEach(filteredSpecies, id: \.self) { name in
                            Button(name) {
                                selectedSpecies = name
                                query = ""
                                regenerate()
                            }
                        }
                        if predictor.knownSpecies.isEmpty {
                            Text("Loading…").foregroundStyle(.secondary)
                                .onAppear { try? predictor.loadIfNeeded() }
                        }
                    }
                }

                Section("Style") {
                    Picker("Qualifier", selection: $qualifier) {
                        ForEach(SetPredictor.Qualifier.allCases) { q in
                            Text(q.rawValue).tag(q)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: qualifier) { regenerate() }
                }

                if let result {
                    Section("Predicted Set") {
                        resultBody(result)
                    }
                } else if let loadError {
                    Section {
                        Label(loadError, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Predict Set")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Use this set") {
                        if let result { onUse(result) }
                    }
                    .disabled(result == nil)
                }
            }
            .task {
                do {
                    try predictor.loadIfNeeded()
                    if selectedSpecies == nil,
                       let initial = initialSpecies,
                       let resolved = predictor.canonicalModelSpecies(for: initial) {
                        selectedSpecies = resolved
                        regenerate()
                    }
                } catch {
                    loadError = error.localizedDescription
                }
            }
        }
    }

    @ViewBuilder
    private func resultBody(_ set: PokemonSet) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if let item = set.item, !item.isEmpty {
                    Text(item)
                        .font(.caption)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.fill.tertiary, in: Capsule())
                }
                Text(set.ability)
                    .font(.caption).foregroundStyle(.orange)
                Text(set.nature)
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
            Text(set.moves.joined(separator: " / "))
                .font(.caption.monospaced())
                .foregroundStyle(.primary)
            let sp = set.statPoints
            Text("HP \(sp.hp)  Atk \(sp.atk)  Def \(sp.def)  SpA \(sp.spa)  SpD \(sp.spd)  Spe \(sp.spe)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private func regenerate() {
        guard let species = selectedSpecies else { result = nil; return }
        result = predictor.predict(species: species, qualifier: qualifier)
    }
}
