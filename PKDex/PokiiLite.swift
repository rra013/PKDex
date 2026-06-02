//
//  PokiiLite.swift
//  PKDex
//
//  Tiny neural-net runtime for two compact MLPs that replace the large
//  on-device LLM:
//
//    - name_qual_weights.npz  → set predictor (name + qualifier → full set)
//    - stat_nature_model.npz  → stat-spread + nature predictor for downloaded
//                               tournament team members
//
//  This file is the shared plumbing: an `.npz` (zip-of-`.npy`) loader, the
//  matmul / embedding / ReLU primitives (Accelerate-backed), legality masks
//  derived from `champions-m-a-learnsets.json`, and the stat-renormalization
//  helper ported from the training notebook (renormalize_to_66).
//

import Foundation
import Accelerate

// MARK: - Errors

enum PokiiLiteError: Error, LocalizedError {
    case missingResource(String)
    case invalidNPZ(String)
    case invalidNPY(String)
    case shapeMismatch(String)

    var errorDescription: String? {
        switch self {
        case .missingResource(let s): return "Missing bundle resource: \(s)"
        case .invalidNPZ(let s):      return "Invalid .npz: \(s)"
        case .invalidNPY(let s):      return "Invalid .npy: \(s)"
        case .shapeMismatch(let s):   return "Tensor shape mismatch: \(s)"
        }
    }
}

// MARK: - .npy tensor

struct NPYTensor {
    let shape: [Int]
    /// Float32 row-major (C-order) values.
    let data: [Float]

    var rows: Int { shape.first ?? 0 }
    var cols: Int { shape.count >= 2 ? shape[1] : data.count }
}

enum NPYParser {
    /// Parses a numpy `.npy` blob into a row-major Float32 tensor. Only the
    /// shapes / dtypes the bundled weight files actually use are supported —
    /// anything outside that envelope throws rather than silently coercing.
    static func parse(_ bytes: Data) throws -> NPYTensor {
        // 6-byte magic + 2-byte version + 2/4-byte header length.
        guard bytes.count >= 10 else { throw PokiiLiteError.invalidNPY("too short") }
        let magic: [UInt8] = [0x93, 0x4E, 0x55, 0x4D, 0x50, 0x59]
        for i in 0..<6 where bytes[bytes.startIndex + i] != magic[i] {
            throw PokiiLiteError.invalidNPY("bad magic")
        }
        let major = bytes[bytes.startIndex + 6]
        let headerStart: Int
        let headerLen: Int
        if major == 1 {
            headerStart = 10
            headerLen = Int(readU16LE(bytes, at: 8))
        } else {
            guard bytes.count >= 12 else { throw PokiiLiteError.invalidNPY("v2 short") }
            headerStart = 12
            headerLen = Int(readU32LE(bytes, at: 8))
        }
        guard bytes.count >= headerStart + headerLen else {
            throw PokiiLiteError.invalidNPY("header overflow")
        }
        let header = bytes.subdata(in: (bytes.startIndex + headerStart) ..<
                                       (bytes.startIndex + headerStart + headerLen))
        let headerString = String(decoding: header, as: UTF8.self)
        guard headerString.contains("'<f4'") else {
            throw PokiiLiteError.invalidNPY("only float32 supported (got: \(headerString))")
        }
        let shape = try parseShape(from: headerString)
        // C-order vs Fortran-order is only meaningful for ≥2 dims — the byte
        // layout is identical for vectors and scalars. MLX writes 1-D biases
        // with fortran_order=True, so we only enforce C-order on tensors that
        // actually have a non-trivial transpose.
        if shape.count > 1 && !headerString.contains("'fortran_order': False") {
            throw PokiiLiteError.invalidNPY("only C-order supported for ≥2-D")
        }

        let nElements = shape.reduce(1, *)
        let nBytes = nElements * MemoryLayout<Float>.size
        let dataStartIdx = bytes.startIndex + headerStart + headerLen
        guard bytes.count - headerStart - headerLen >= nBytes else {
            throw PokiiLiteError.invalidNPY("data underflow: need \(nBytes), have \(bytes.count - headerStart - headerLen)")
        }
        var data = [Float](repeating: 0, count: nElements)
        _ = data.withUnsafeMutableBytes { dst in
            bytes.copyBytes(to: dst, from: dataStartIdx ..< dataStartIdx + nBytes)
        }
        return NPYTensor(shape: shape, data: data)
    }

    private static func parseShape(from header: String) throws -> [Int] {
        guard let range = header.range(of: "'shape':") else {
            throw PokiiLiteError.invalidNPY("no shape")
        }
        let after = header[range.upperBound...]
        guard let open = after.firstIndex(of: "("),
              let close = after[open...].firstIndex(of: ")") else {
            throw PokiiLiteError.invalidNPY("malformed shape")
        }
        let inside = after[after.index(after: open) ..< close]
        let dims = inside.split(separator: ",").compactMap {
            Int($0.trimmingCharacters(in: .whitespaces))
        }
        return dims
    }

    private static func readU16LE(_ d: Data, at offset: Int) -> UInt16 {
        let i = d.startIndex + offset
        return UInt16(d[i]) | (UInt16(d[i + 1]) << 8)
    }
    private static func readU32LE(_ d: Data, at offset: Int) -> UInt32 {
        let i = d.startIndex + offset
        return UInt32(d[i]) |
               (UInt32(d[i + 1]) << 8) |
               (UInt32(d[i + 2]) << 16) |
               (UInt32(d[i + 3]) << 24)
    }
}

// MARK: - .npz (zip) reader

/// Minimal reader for the stored-only zip layout numpy emits via `np.savez`.
/// Compressed-method entries are rejected rather than silently corrupting —
/// our bundled weights are always uncompressed.
struct NPZArchive {
    private let backing: Data
    private let entries: [String: (offset: Int, length: Int)]

    init(url: URL) throws {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        self.backing = data
        self.entries = try Self.parseCentralDirectory(data)
    }

    /// Parse a tensor by its name inside the archive (e.g. "name_emb.weight.npy").
    func loadTensor(_ name: String) throws -> NPYTensor {
        guard let entry = entries[name] else {
            throw PokiiLiteError.invalidNPZ("missing entry: \(name)")
        }
        let slice = backing.subdata(in: entry.offset ..< entry.offset + entry.length)
        return try NPYParser.parse(slice)
    }

    // ZIP signatures (little-endian on disk).
    private static let eocdSig:  UInt32 = 0x06054b50
    private static let cdhSig:   UInt32 = 0x02014b50
    private static let localSig: UInt32 = 0x04034b50

    private static func parseCentralDirectory(_ data: Data) throws -> [String: (Int, Int)] {
        guard data.count >= 22 else { throw PokiiLiteError.invalidNPZ("too short for EOCD") }

        // EOCD lives at the end of the file. Scan backwards from the last byte
        // it could occupy. Comment field can stretch up to 0xFFFF bytes.
        let scanStart = max(0, data.count - 22 - 0xFFFF)
        var eocdIdx: Int? = nil
        var i = data.count - 22
        while i >= scanStart {
            if readU32LE(data, at: i) == eocdSig { eocdIdx = i; break }
            i -= 1
        }
        guard let eocdOffset = eocdIdx else {
            throw PokiiLiteError.invalidNPZ("no EOCD record")
        }
        let numEntries = Int(readU16LE(data, at: eocdOffset + 10))
        let cdOffset = Int(readU32LE(data, at: eocdOffset + 16))

        var out: [String: (Int, Int)] = [:]
        out.reserveCapacity(numEntries)
        var cur = cdOffset
        for _ in 0..<numEntries {
            guard cur + 46 <= data.count,
                  readU32LE(data, at: cur) == cdhSig
            else { throw PokiiLiteError.invalidNPZ("bad central-dir entry") }
            let method = readU16LE(data, at: cur + 10)
            guard method == 0 else {
                throw PokiiLiteError.invalidNPZ("compressed entry not supported (method=\(method))")
            }
            let compressedSize = Int(readU32LE(data, at: cur + 20))
            let nameLen = Int(readU16LE(data, at: cur + 28))
            let extraLen = Int(readU16LE(data, at: cur + 30))
            let commentLen = Int(readU16LE(data, at: cur + 32))
            let localOffset = Int(readU32LE(data, at: cur + 42))
            let nameRange = (cur + 46) ..< (cur + 46 + nameLen)
            let name = String(decoding: data.subdata(in: nameRange), as: UTF8.self)
            cur += 46 + nameLen + extraLen + commentLen

            // Walk into the local header to find where the raw data starts —
            // name/extra lengths there can differ from the central-dir copy.
            guard readU32LE(data, at: localOffset) == localSig else {
                throw PokiiLiteError.invalidNPZ("bad local header for \(name)")
            }
            let localNameLen = Int(readU16LE(data, at: localOffset + 26))
            let localExtraLen = Int(readU16LE(data, at: localOffset + 28))
            let dataStart = localOffset + 30 + localNameLen + localExtraLen
            out[name] = (dataStart, compressedSize)
        }
        return out
    }

    private static func readU16LE(_ d: Data, at offset: Int) -> UInt16 {
        let i = d.startIndex + offset
        return UInt16(d[i]) | (UInt16(d[i + 1]) << 8)
    }
    private static func readU32LE(_ d: Data, at offset: Int) -> UInt32 {
        let i = d.startIndex + offset
        return UInt32(d[i]) |
               (UInt32(d[i + 1]) << 8) |
               (UInt32(d[i + 2]) << 16) |
               (UInt32(d[i + 3]) << 24)
    }
}

// MARK: - Tiny NN ops (Accelerate)

enum PokiiNN {
    /// Embedding lookup: returns a copy of row `index` (length `embedDim`)
    /// from a row-major table. Out-of-range indices are clamped to 0 so
    /// callers don't have to special-case the UNK slot when they didn't load
    /// one — the underlying tensor itself defines whether UNK exists.
    static func embed(table: NPYTensor, index: Int) -> [Float] {
        let embedDim = table.cols
        let safeIndex = max(0, min(index, table.rows - 1))
        let start = safeIndex * embedDim
        return Array(table.data[start ..< start + embedDim])
    }

    /// y = W·x + b. `weight` is (outDim, inDim) row-major as numpy writes it.
    /// Uses vDSP_mmul (matrix-vector specialization) for the multiply, then
    /// vDSP_vadd to fold in the bias. vDSP is the non-deprecated path in
    /// modern Accelerate — cblas_sgemv works but warns on iOS 16.4+.
    static func linear(weight: NPYTensor, bias: NPYTensor,
                       input: [Float]) -> [Float] {
        let outDim = weight.rows
        let inDim  = weight.cols
        precondition(input.count == inDim,
                     "linear: input \(input.count) != inDim \(inDim)")
        precondition(bias.data.count == outDim,
                     "linear: bias \(bias.data.count) != outDim \(outDim)")
        var product = [Float](repeating: 0, count: outDim)
        weight.data.withUnsafeBufferPointer { wPtr in
            input.withUnsafeBufferPointer { xPtr in
                product.withUnsafeMutableBufferPointer { pPtr in
                    // W is (outDim × inDim), x is (inDim × 1) → product is (outDim × 1).
                    vDSP_mmul(wPtr.baseAddress!, 1,
                              xPtr.baseAddress!, 1,
                              pPtr.baseAddress!, 1,
                              vDSP_Length(outDim), 1, vDSP_Length(inDim))
                }
            }
        }
        var result = bias.data
        vDSP_vadd(result, 1, product, 1, &result, 1, vDSP_Length(outDim))
        return result
    }

    /// In-place ReLU via vDSP threshold (replaces each element with max(x, 0)).
    static func relu(_ x: inout [Float]) {
        var zero: Float = 0
        let n = vDSP_Length(x.count)
        x.withUnsafeMutableBufferPointer { ptr in
            vDSP_vthr(ptr.baseAddress!, 1, &zero, ptr.baseAddress!, 1, n)
        }
    }

    /// Argmax with a multiplicative mask: indices where `mask[i] == 0` are
    /// driven to -inf so they can never win. Used to enforce legality on the
    /// ability / nature / move heads. Returns -1 if no legal class exists.
    static func maskedArgmax(_ logits: [Float], mask: [Float]) -> Int {
        precondition(logits.count == mask.count)
        var best: Int = -1
        var bestVal: Float = -.greatestFiniteMagnitude
        for i in 0..<logits.count where mask[i] > 0.5 && logits[i] > bestVal {
            bestVal = logits[i]; best = i
        }
        return best
    }

    /// Top-K indices among legal classes (mask=1). Stable on ties.
    static func maskedTopK(_ logits: [Float], mask: [Float], k: Int) -> [Int] {
        var candidates: [(Int, Float)] = []
        candidates.reserveCapacity(logits.count)
        for i in 0..<logits.count where mask[i] > 0.5 {
            candidates.append((i, logits[i]))
        }
        candidates.sort { $0.1 > $1.1 }
        return candidates.prefix(k).map { $0.0 }
    }

    /// Pure argmax — used for heads with no legality constraint (item, nature).
    static func argmax(_ logits: [Float]) -> Int {
        var best = 0
        var bestVal = logits[0]
        for i in 1..<logits.count where logits[i] > bestVal {
            bestVal = logits[i]; best = i
        }
        return best
    }
}

// MARK: - Stat normalization (ported from training notebook)

enum PokiiStatNorm {
    /// Coerce a raw stat vector into a legal Champions spread:
    ///   - each value clamped to [0, 32]
    ///   - if both Atk and Spa were predicted positive, zero the smaller
    ///     (single-attacking-stat invariant the notebook enforces)
    ///   - top up the shortfall into the smallest non-zero stat (preserves shape
    ///     instead of flattening); trim excess from the largest. Termination is
    ///     guaranteed: each loop moves the running total one step toward 66 with
    ///     no competing mutation.
    /// Order is [hp, atk, def, spa, spd, spe].
    static func renormalizeTo66(_ raw: [Int], forceSingleAttacker: Bool = true) -> [Int] {
        var s = raw.map { max(0, min(32, $0)) }
        if forceSingleAttacker, s[1] > 0, s[3] > 0 {
            // keep the larger investment, zero the loser
            let loserIdx = s[1] >= s[3] ? 3 : 1
            s[loserIdx] = 0
        }
        // Preference order for tie-breaking: hp, def, spd, spe, atk, spa.
        let order = [0, 2, 4, 5, 1, 3]
        var total = s.reduce(0, +)
        if total == 0 { s[0] = 1; total = 1 }

        while total < 66 {
            var cand = (0..<6).filter { s[$0] > 0 && s[$0] < 32 }
            if cand.isEmpty { cand = order.filter { s[$0] < 32 } }
            guard let i = cand.min(by: { lhs, rhs in
                if s[lhs] != s[rhs] { return s[lhs] < s[rhs] }
                return order.firstIndex(of: lhs)! < order.firstIndex(of: rhs)!
            }) else { break }
            s[i] += 1; total += 1
        }
        while total > 66 {
            let cand = (0..<6).filter { s[$0] > 0 }
            guard let i = cand.max(by: { s[$0] < s[$1] }) else { break }
            s[i] -= 1; total -= 1
        }
        return s
    }
}

// MARK: - Vocab helper

/// Lookup table over a sorted vocabulary, optionally with an UNK slot at
/// `len(classes_)` (the convention the stat_nature notebook uses for inputs
/// the model didn't see during training).
struct PokiiVocab {
    let classes: [String]
    private let index: [String: Int]
    let unkIndex: Int?

    init(classes: [String], hasUNK: Bool) {
        self.classes = classes
        self.index = Dictionary(uniqueKeysWithValues: classes.enumerated().map { ($1, $0) })
        self.unkIndex = hasUNK ? classes.count : nil
    }

    func index(of value: String) -> Int? {
        if let hit = index[value] { return hit }
        return unkIndex
    }

    /// Strict lookup — returns nil rather than falling back to UNK. Used for
    /// heads where decoding UNK would be a category error (e.g. "the model
    /// said class index 150 which is UNK ability — there's no name for it").
    func strictIndex(of value: String) -> Int? { index[value] }
}
