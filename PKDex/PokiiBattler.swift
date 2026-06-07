//
//  PokiiBattler.swift
//  PKDex
//
//  On-device inference for the doubles-battle policy. Loads the safetensors
//  MLP shipped at pokii_battler.safetensors and runs it through the same
//  Accelerate-backed primitives PokiiLite uses for the team-builder models.
//
//  Model contract (from feature_config.json):
//    embed(N_SPECIES → 32) for 4 species slots → flatten(128) || cont(108)
//    fc1(236 → 256, ReLU) → fc2(256 → 256, ReLU)
//      ├─ action_head(256 → N_CLASSES)  → argmax(logits + mask) → action label
//      └─ mega_head(256 → 1)            → sigmoid → "mega evolve?" decision
//

import Foundation

// MARK: - Safetensors loader

/// Minimal reader for a single-file safetensors archive. The format is a
/// fixed 8-byte little-endian header length, a JSON header describing each
/// tensor's dtype / shape / byte range, and a contiguous tensor blob.
struct SafetensorsArchive {
    private let backing: Data
    private let dataStart: Int
    private let entries: [String: TensorInfo]

    struct TensorInfo {
        let dtype: String
        let shape: [Int]
        let offsetBegin: Int  // relative to dataStart
        let offsetEnd: Int
    }

    init(url: URL) throws {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        self.backing = data
        guard data.count >= 8 else {
            throw PokiiLiteError.invalidNPZ("safetensors header truncated")
        }
        var headerLen: UInt64 = 0
        _ = withUnsafeMutableBytes(of: &headerLen) { dst in
            data.copyBytes(to: dst, from: data.startIndex ..< data.startIndex + 8)
        }
        let n = Int(headerLen)
        guard data.count >= 8 + n else {
            throw PokiiLiteError.invalidNPZ("safetensors header overrun")
        }
        self.dataStart = 8 + n
        let headerRange = (data.startIndex + 8) ..< (data.startIndex + 8 + n)
        let header = data.subdata(in: headerRange)
        guard let json = try JSONSerialization.jsonObject(with: header) as? [String: Any] else {
            throw PokiiLiteError.invalidNPZ("safetensors header not a JSON object")
        }
        var parsed: [String: TensorInfo] = [:]
        for (name, value) in json {
            if name == "__metadata__" { continue }
            guard let entry = value as? [String: Any],
                  let dtype = entry["dtype"] as? String,
                  let shape = entry["shape"] as? [Int],
                  let off = entry["data_offsets"] as? [Int],
                  off.count == 2 else {
                throw PokiiLiteError.invalidNPZ("safetensors entry malformed: \(name)")
            }
            parsed[name] = TensorInfo(dtype: dtype, shape: shape,
                                      offsetBegin: off[0], offsetEnd: off[1])
        }
        self.entries = parsed
    }

    /// Returns the named tensor as a row-major Float32 NPYTensor so it plugs
    /// straight into the existing PokiiNN.linear / embed helpers.
    func loadTensor(_ name: String) throws -> NPYTensor {
        guard let info = entries[name] else {
            throw PokiiLiteError.invalidNPZ("safetensors missing tensor: \(name)")
        }
        guard info.dtype == "F32" else {
            throw PokiiLiteError.invalidNPY("safetensors only F32 supported (got \(info.dtype))")
        }
        let nElements = info.shape.reduce(1, *)
        let nBytes = nElements * MemoryLayout<Float>.size
        guard info.offsetEnd - info.offsetBegin == nBytes else {
            throw PokiiLiteError.shapeMismatch(
                "\(name): byte range \(info.offsetEnd - info.offsetBegin) ≠ shape bytes \(nBytes)")
        }
        let absStart = backing.startIndex + dataStart + info.offsetBegin
        var values = [Float](repeating: 0, count: nElements)
        _ = values.withUnsafeMutableBytes { dst in
            backing.copyBytes(to: dst, from: absStart ..< absStart + nBytes)
        }
        return NPYTensor(shape: info.shape, data: values)
    }
}

// MARK: - Battler model

/// The doubles-battle policy MLP. Loaded lazily from the app bundle on first
/// use; the model itself is tiny (~2.6 MB) and inference is sub-millisecond,
/// so we run it synchronously on the main actor when the AI controller asks
/// for a decision.
@MainActor
final class PokiiBattler {
    static let shared = PokiiBattler()

    // Loaded tensors / config — `nil` until `ensureLoaded()` succeeds.
    private var embed: NPYTensor?
    private var fc1W: NPYTensor?; private var fc1B: NPYTensor?
    private var fc2W: NPYTensor?; private var fc2B: NPYTensor?
    private var actionHeadW: NPYTensor?; private var actionHeadB: NPYTensor?
    private var megaHeadW: NPYTensor?;   private var megaHeadB: NPYTensor?

    /// Maps Showdown-style species name → species2idx (the embedding row).
    /// `<pad>` is 0, `<unk>` is 1. Names that don't appear fall back to unk.
    private(set) var species2idx: [String: Int] = [:]

    /// The full action vocabulary in classifier-output order. Index N is the
    /// label at `actionVocab[N]`. Used to decode argmax → action string.
    private(set) var actionVocab: [String] = []

    /// Species that the training data ever saw mega-evolve. The featurizer's
    /// `acting_can_mega` feature falls back to this when no held-stone signal
    /// is available; the deployment-correct gate prefers the held-stone check
    /// (and the engine already enforces "one mega per side per battle").
    private(set) var megaCapableSpecies: Set<String> = []

    /// Number of continuous features the model expects. Read from
    /// feature_config so the featurizer can't drift from the weights.
    private(set) var contDim: Int = 105
    /// Number of categorical slots (species). Always 4 in doubles.
    private(set) var nSlots: Int = 4
    /// Embedding dimension per categorical slot.
    private(set) var embDim: Int = 32
    /// Hidden width of fc1 / fc2. Read from the config so a wider/narrower
    /// retrain swaps in without a Swift change.
    private(set) var hidden: Int = 256
    /// Number of action classes (output logits).
    private(set) var nClasses: Int = 1188

    private var didLoad = false
    private(set) var loadError: String? = nil

    private init() {}

    /// Returns true if the model + config are loaded and ready to query.
    /// Safe to call repeatedly — initialization happens once.
    func ensureLoaded() -> Bool {
        if didLoad { return loadError == nil }
        didLoad = true
        do {
            try load()
            return true
        } catch {
            loadError = String(describing: error)
            print("[PokiiBattler] load failed: \(loadError ?? "?")")
            return false
        }
    }

    private func load() throws {
        guard let weightsURL = Bundle.main.url(forResource: "pokii_battler",
                                               withExtension: "safetensors") else {
            throw PokiiLiteError.missingResource("pokii_battler.safetensors")
        }
        guard let cfgURL = Bundle.main.url(forResource: "feature_config",
                                           withExtension: "json") else {
            throw PokiiLiteError.missingResource("feature_config.json")
        }

        let archive = try SafetensorsArchive(url: weightsURL)
        self.embed       = try archive.loadTensor("embed.weight")
        self.fc1W        = try archive.loadTensor("fc1.weight")
        self.fc1B        = try archive.loadTensor("fc1.bias")
        self.fc2W        = try archive.loadTensor("fc2.weight")
        self.fc2B        = try archive.loadTensor("fc2.bias")
        self.actionHeadW = try archive.loadTensor("action_head.weight")
        self.actionHeadB = try archive.loadTensor("action_head.bias")
        self.megaHeadW   = try archive.loadTensor("mega_head.weight")
        self.megaHeadB   = try archive.loadTensor("mega_head.bias")

        let cfgData = try Data(contentsOf: cfgURL)
        guard let cfg = try JSONSerialization.jsonObject(with: cfgData) as? [String: Any] else {
            throw PokiiLiteError.invalidNPZ("feature_config.json not an object")
        }
        if let model = cfg["model"] as? [String: Any] {
            if let v = model["cont_dim"]  as? Int { contDim = v }
            if let v = model["n_slots"]   as? Int { nSlots = v }
            if let v = model["emb_dim"]   as? Int { embDim = v }
            if let v = model["hidden"]    as? Int { hidden = v }
            if let v = model["n_classes"] as? Int { nClasses = v }
        }
        if let dict = cfg["species2idx"] as? [String: Int] {
            self.species2idx = dict
        }
        if let vocab = cfg["action_vocabulary"] as? [String] {
            self.actionVocab = vocab
        }
        if let mc = cfg["mega_capable_species"] as? [String] {
            self.megaCapableSpecies = Set(mc)
        }

        // Sanity-check the tensors match the config so a bad bundle fails loudly.
        guard let fc1W = fc1W, let fc1B = fc1B,
              let fc2W = fc2W, let fc2B = fc2B,
              let aW = actionHeadW, let aB = actionHeadB,
              let mW = megaHeadW,   let mB = megaHeadB else {
            throw PokiiLiteError.invalidNPZ("missing tensors after load")
        }
        let expectedIn = nSlots * embDim + contDim
        guard fc1W.shape == [hidden, expectedIn], fc1B.shape == [hidden],
              fc2W.shape == [hidden, hidden], fc2B.shape == [hidden],
              aW.shape == [nClasses, hidden], aB.shape == [nClasses],
              mW.shape == [1, hidden], mB.shape == [1] else {
            throw PokiiLiteError.shapeMismatch(
                "battler MLP shape mismatch (fc1 \(fc1W.shape), action \(aW.shape), mega \(mW.shape), hidden=\(hidden))")
        }
    }

    // MARK: Inference

    /// One decision point: action label + the mega head's sigmoid probability.
    /// `nil` is returned if the model failed to load or every action in the
    /// mask was illegal. The caller is responsible for gating mega legality
    /// (held stone + side hasn't used its mega yet).
    struct Decision {
        let label: String          // e.g. "move_Aerial_Ace" / "switch_charizard"
        let megaProbability: Float // sigmoid(mega_logit) ∈ [0, 1]
    }

    func chooseAction(xCat: [Int], xCont: [Float], mask: [Float]) -> Decision? {
        guard ensureLoaded(),
              let embed = embed,
              let fc1W = fc1W, let fc1B = fc1B,
              let fc2W = fc2W, let fc2B = fc2B,
              let aW = actionHeadW, let aB = actionHeadB,
              let mW = megaHeadW,   let mB = megaHeadB else {
            return nil
        }
        precondition(xCat.count == nSlots, "xCat must have \(nSlots) entries")
        precondition(xCont.count == contDim, "xCont must be length \(contDim)")
        precondition(mask.count == nClasses, "mask must be length \(nClasses)")

        // Build the input vector: [embed(slot0), embed(slot1), …, xCont]
        var input = [Float]()
        input.reserveCapacity(nSlots * embDim + contDim)
        for idx in xCat {
            input.append(contentsOf: PokiiNN.embed(table: embed, index: idx))
        }
        input.append(contentsOf: xCont)

        var h = PokiiNN.linear(weight: fc1W, bias: fc1B, input: input)
        PokiiNN.relu(&h)
        var h2 = PokiiNN.linear(weight: fc2W, bias: fc2B, input: h)
        PokiiNN.relu(&h2)

        // Two heads share the trunk. Each is one Linear → length-N output.
        let logits = PokiiNN.linear(weight: aW, bias: aB, input: h2)
        let megaLogits = PokiiNN.linear(weight: mW, bias: mB, input: h2)
        let megaProb: Float = 1.0 / (1.0 + expf(-megaLogits[0]))

        // Add the mask (0 for legal, -1e9 for illegal) and take the argmax.
        var best = -1
        var bestVal: Float = -.greatestFiniteMagnitude
        for i in 0..<nClasses {
            let v = logits[i] + mask[i]
            if v > bestVal { bestVal = v; best = i }
        }
        guard best >= 0, actionVocab.indices.contains(best) else { return nil }
        return Decision(label: actionVocab[best], megaProbability: megaProb)
    }
}
