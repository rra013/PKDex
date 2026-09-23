//
//  StatNaturePredictor.swift
//  PKDex
//
//  Forward pass for the small MLP that imputes the **stat spread** and
//  **nature** of a Pokemon given everything else (name, item, ability,
//  moves, role). Used by the Limitless tournament downloader so saved
//  team members come in with model-predicted stats/nature rather than
//  the placeholder zeros the API returns.
//
//  Architecture (from `predict_stats_nature.ipynb`):
//      inputs = concat(
//          name_emb(32), item_emb(16), abil_emb(16), role_emb(8),
//          move_enc(relu(Linear(336→64))), base_stats(6)
//      )                                                        → (142,)
//      shared = Linear(142→256) → ReLU → Dropout(no-op @ infer)
//             → Linear(256→128) → ReLU                          → (128,)
//      heads  = stats(6),  nature(15)
//
//  All input encoders (name/item/ability/role) include an UNK slot at the
//  end so the model gracefully handles fields we don't have or species the
//  training set never saw.
//

import Foundation

@MainActor @Observable
final class StatNaturePredictor {
    static let shared = StatNaturePredictor()

    /// Result of one prediction call.
    struct Prediction {
        let statPoints: PokemonSet.StatPoints
        let natureName: String
        /// Looks up the matching Nature record from the global natures table
        /// by case-insensitive name. Returns nil if no match (model emitted
        /// a name the local nature table doesn't know about).
        var natureRecord: Nature? {
            allNatures.first(where: { $0.name.caseInsensitiveCompare(natureName) == .orderedSame })
        }
    }

    private(set) var isReady: Bool = false
    @ObservationIgnored private var loaded: Loaded?

    private struct Loaded {
        let names: PokiiVocab        // hasUNK = true
        let items: PokiiVocab        // hasUNK = true
        let abilities: PokiiVocab    // hasUNK = true
        let roles: PokiiVocab        // hasUNK = true
        let natures: PokiiVocab
        let moves: PokiiVocab

        let nameEmb: NPYTensor
        let itemEmb: NPYTensor
        let abilEmb: NPYTensor
        let roleEmb: NPYTensor
        let moveEncW: NPYTensor;  let moveEncB: NPYTensor    // (64, 336), (64,)
        let shared0W: NPYTensor;  let shared0B: NPYTensor    // (256, 142)
        let shared3W: NPYTensor;  let shared3B: NPYTensor    // (128, 256)
        let statsW: NPYTensor;    let statsB: NPYTensor      // (6, 128)
        let natureW: NPYTensor;   let natureB: NPYTensor     // (15, 128)

        /// Per-species (model vocab) base-stat features, normalized /255.
        let baseStats: [String: [Float]]
    }

    func loadIfNeeded() throws {
        if loaded != nil { return }
        guard let weightsURL = Bundle.main.url(forResource: "stat_nature_model",
                                               withExtension: "npz") else {
            throw PokiiLiteError.missingResource("stat_nature_model.npz")
        }
        guard let vocabURL = Bundle.main.url(forResource: "stat_nature_vocab",
                                              withExtension: "json") else {
            throw PokiiLiteError.missingResource("stat_nature_vocab.json")
        }
        let npz = try NPZArchive(url: weightsURL)
        let vocabData = try Data(contentsOf: vocabURL)
        let vocab = try JSONDecoder().decode(VocabJSON.self, from: vocabData)

        let names      = PokiiVocab(classes: vocab.names,     hasUNK: true)
        let items      = PokiiVocab(classes: vocab.items,     hasUNK: true)
        let abilities  = PokiiVocab(classes: vocab.abilities, hasUNK: true)
        let roles      = PokiiVocab(classes: vocab.roles,     hasUNK: true)
        let natures    = PokiiVocab(classes: vocab.natures,   hasUNK: false)
        let moves      = PokiiVocab(classes: vocab.moves,     hasUNK: false)

        // Cache base stats for species the model knows. Anything outside the
        // model's name vocab gets zeros at predict-time (matches the notebook's
        // `base_stats(name)` which returns [0]*6 for misses).
        let store = ChampionsLearnsetStore.shared
        var baseStats: [String: [Float]] = [:]
        for species in vocab.names {
            guard let entry = store.data(for: species) else { continue }
            baseStats[species] = [Float(entry.stats.hp), Float(entry.stats.atk),
                                  Float(entry.stats.def), Float(entry.stats.spa),
                                  Float(entry.stats.spd), Float(entry.stats.spe)].map { $0 / 255.0 }
        }

        loaded = Loaded(
            names: names, items: items, abilities: abilities,
            roles: roles, natures: natures, moves: moves,
            nameEmb:  try npz.loadTensor("name_emb.weight.npy"),
            itemEmb:  try npz.loadTensor("item_emb.weight.npy"),
            abilEmb:  try npz.loadTensor("abil_emb.weight.npy"),
            roleEmb:  try npz.loadTensor("role_emb.weight.npy"),
            moveEncW: try npz.loadTensor("move_enc.layers.0.weight.npy"),
            moveEncB: try npz.loadTensor("move_enc.layers.0.bias.npy"),
            shared0W: try npz.loadTensor("shared.layers.0.weight.npy"),
            shared0B: try npz.loadTensor("shared.layers.0.bias.npy"),
            shared3W: try npz.loadTensor("shared.layers.3.weight.npy"),
            shared3B: try npz.loadTensor("shared.layers.3.bias.npy"),
            statsW:   try npz.loadTensor("stats_head.weight.npy"),
            statsB:   try npz.loadTensor("stats_head.bias.npy"),
            natureW:  try npz.loadTensor("nature_head.weight.npy"),
            natureB:  try npz.loadTensor("nature_head.bias.npy"),
            baseStats: baseStats
        )
        isReady = true
    }

    /// Predict stat spread + nature for one Pokemon. Inputs the model didn't
    /// see during training (unknown species/item/ability/role) fall back to
    /// the UNK embedding slot, so the call always succeeds once the model
    /// has been loaded.
    func predict(name: String,
                 item: String?,
                 ability: String?,
                 moves: [String],
                 role: String?) -> Prediction? {
        try? loadIfNeeded()
        guard let L = loaded else { return nil }

        let nameIdx = L.names.index(of: name)           ?? L.names.unkIndex!
        let itemIdx = item.flatMap { L.items.index(of: $0) }       ?? L.items.unkIndex!
        let abilIdx = ability.flatMap { L.abilities.index(of: $0) } ?? L.abilities.unkIndex!
        let roleIdx = role.flatMap { L.roles.index(of: $0) }       ?? L.roles.unkIndex!

        // Build multi-hot moves vector. Unknown moves are silently dropped —
        // matches `moves_multihot` in the notebook (`if j is not None: v[j]=1`).
        var moveVec = [Float](repeating: 0, count: L.moves.classes.count)
        for m in moves {
            if let i = L.moves.strictIndex(of: m) { moveVec[i] = 1 }
        }

        // move_enc: relu(Linear(336→64))
        var moveEnc = PokiiNN.linear(weight: L.moveEncW, bias: L.moveEncB, input: moveVec)
        PokiiNN.relu(&moveEnc)

        let baseStats = L.baseStats[name] ?? [Float](repeating: 0, count: 6)

        var x: [Float] = []
        x.reserveCapacity(142)
        x.append(contentsOf: PokiiNN.embed(table: L.nameEmb, index: nameIdx))
        x.append(contentsOf: PokiiNN.embed(table: L.itemEmb, index: itemIdx))
        x.append(contentsOf: PokiiNN.embed(table: L.abilEmb, index: abilIdx))
        x.append(contentsOf: PokiiNN.embed(table: L.roleEmb, index: roleIdx))
        x.append(contentsOf: moveEnc)
        x.append(contentsOf: baseStats)

        var h = PokiiNN.linear(weight: L.shared0W, bias: L.shared0B, input: x)
        PokiiNN.relu(&h)
        h     = PokiiNN.linear(weight: L.shared3W, bias: L.shared3B, input: h)
        PokiiNN.relu(&h)

        let statsLogits  = PokiiNN.linear(weight: L.statsW,  bias: L.statsB,  input: h)
        let natureLogits = PokiiNN.linear(weight: L.natureW, bias: L.natureB, input: h)

        // Stats: round → clamp → renormalize using the stat_nature notebook's
        // variant of renormalize_to_66 (no single-attacker enforcement; trims
        // from the largest stat downward; this matches the imputation path
        // used during team-attribute imputation in the notebook).
        let rawStats = statsLogits.map { Int(($0 * 32).rounded()) }
        let norm = PokiiStatNorm.renormalizeTo66Imputed(rawStats)
        let sp = PokemonSet.StatPoints(hp: norm[0], atk: norm[1], def: norm[2],
                                        spa: norm[3], spd: norm[4], spe: norm[5])

        let natureName = L.natures.classes[PokiiNN.argmax(natureLogits)]
        return Prediction(statPoints: sp, natureName: natureName)
    }

    private struct VocabJSON: Decodable {
        let names: [String]
        let items: [String]
        let abilities: [String]
        let roles: [String]
        let natures: [String]
        let moves: [String]
    }
}

// MARK: - Imputation-mode renormalize

extension PokiiStatNorm {
    /// Variant of `renormalizeTo66` ported from the stat_nature notebook's
    /// `renormalize_to_66`. Behavioral differences vs the name_qual version:
    ///   - Does NOT zero the smaller of atk/spa (imputed sets may be mixed
    ///     attackers and we don't want to clobber the model's intent).
    ///   - On overage, trims from the LARGEST stats first (descending),
    ///     taking the full overage out of one or two stats rather than
    ///     repeatedly poking the current max.
    ///   - Floor is 0 with hard cap 32 per stat, like the other variant.
    static func renormalizeTo66Imputed(_ raw: [Int]) -> [Int] {
        var s = raw.map { max(0, min(32, $0)) }
        let order = ["hp","atk","def","spa","spd","spe"]   // for tie-break order on top-up
        let orderIdx = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
        let preference = [0, 1, 2, 3, 4, 5]                // (matches list above)
        _ = orderIdx; _ = preference                       // kept for parity with notebook source

        var total = s.reduce(0, +)
        if total > 66 {
            var excess = total - 66
            // Descending order of current stat value; trim what we can.
            let descending = (0..<6).sorted { s[$0] > s[$1] }
            for i in descending where excess > 0 {
                let take = min(excess, s[i])
                s[i] -= take
                excess -= take
            }
            total = s.reduce(0, +)
        } else if total < 66 {
            var deficit = 66 - total
            // Top up the smallest non-zero non-capped stat; preference order
            // (hp, atk, def, spa, spd, spe) breaks ties.
            while deficit > 0 {
                let cand = (0..<6).filter { s[$0] > 0 && s[$0] < 32 }
                if cand.isEmpty { break }
                let i = cand.min { (a, b) in
                    if s[a] != s[b] { return s[a] < s[b] }
                    return a < b
                }!
                let add = min(deficit, 32 - s[i])
                s[i] += add
                deficit -= add
            }
        }
        return s
    }
}
