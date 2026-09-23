//
//  PokiiModelDownloader.swift
//  PKReference
//
//  Manages the ~5 GB Pokii model download. Resumable, SHA-verified,
//  versioned storage so multiple model versions can coexist briefly during
//  app updates. Reports progress for the Settings UI.
//
//  The model is stored in Application Support (excluded from iCloud backup
//  to avoid eating users' cloud quota with a 5 GB file).
//

import Foundation
import CryptoKit
import Combine

@MainActor
public final class PokiiModelDownloader: NSObject, ObservableObject {
    public static let shared = PokiiModelDownloader()

    // MARK: Configuration

    /// Where the per-file manifest lives. The manifest is the source of
    /// truth for which files to download and what their checksums must be.
    /// Pinned to a specific commit so README/doc edits on `main` can't
    /// change the bytes served to clients.
    public static let manifestURL = URL(string:
        "https://huggingface.co/rra013/pokii-mlx-q4-3b/resolve/" +
        "d420861f4a834cfa18a1aca0fcde5f155ab22109/manifest.json")!

    /// Base URL for file downloads. Filenames from the manifest are
    /// appended to this base. Same commit pin as the manifest.
    public static let fileBaseURL = URL(string:
        "https://huggingface.co/rra013/pokii-mlx-q4-3b/resolve/" +
        "d420861f4a834cfa18a1aca0fcde5f155ab22109/")!

    // MARK: Published state

    @Published public private(set) var status: Status = .idle
    @Published public private(set) var progress: Progress = .zero

    public enum Status: Equatable {
        case idle
        case fetchingManifest
        case downloading(currentFile: String, fileIndex: Int, totalFiles: Int)
        case verifying(file: String)
        case completed
        case failed(String)
        case cancelled
    }

    public struct Progress: Equatable {
        public var bytesDownloaded: Int64 = 0
        public var bytesTotal: Int64 = 0
        public var fraction: Double {
            bytesTotal > 0 ? Double(bytesDownloaded) / Double(bytesTotal) : 0
        }
        public static let zero = Progress()
    }

    // MARK: Internal

    private var currentTask: Task<Void, Never>?
    private var urlSessionConfig: URLSessionConfiguration {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 60
        c.timeoutIntervalForResource = 60 * 60 * 4  // generous for 5 GB
        c.allowsCellularAccess = false  // wifi-only by default; configurable
        c.waitsForConnectivity = true
        return c
    }

    // MARK: - Storage layout

    /// Application Support directory, marked excluded from iCloud backup.
    private static var rootDirectory: URL {
        let url = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        )[0].appendingPathComponent("PokiiModel", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: url, withIntermediateDirectories: true)
        // Exclude from iCloud backup
        var u = url
        var rv = URLResourceValues()
        rv.isExcludedFromBackup = true
        try? u.setResourceValues(rv)
        return url
    }

    /// Per-version subdirectory. Lets new versions land alongside old ones
    /// during an in-progress migration.
    public func modelDirectory(version: String) -> URL {
        Self.rootDirectory.appendingPathComponent(version, isDirectory: true)
    }

    /// Returns true if every file in the saved manifest matches its hash on
    /// disk. Cheap (only checks file existence + size; full hash check only
    /// happens during install).
    /// Files that live in the HF repo but aren't needed for on-device
    /// inference. Excluding them from manifest enforcement means editing
    /// the model card (README) or license never invalidates installs.
    private static func isMetadataFile(_ name: String) -> Bool {
        let lower = name.lowercased()
        if lower.hasSuffix(".md") { return true }
        if lower == ".gitattributes" { return true }
        if lower == "license" || lower.hasPrefix("license.") { return true }
        return false
    }

    public func isModelInstalled(version: String) -> Bool {
        let dir = modelDirectory(version: version)
        let manifestPath = dir.appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: manifestPath),
              let manifest = try? JSONDecoder().decode(Manifest.self, from: data)
        else { return false }
        // Same validation as a fresh download, so a tampered on-disk manifest
        // can't point this check outside the model directory.
        guard ModelFileSafety.validate(manifest.files) == nil else { return false }
        for file in manifest.files where !Self.isMetadataFile(file.name) {
            guard let path = ModelFileSafety.destination(for: file.name, in: dir),
                  let attrs = try? FileManager.default.attributesOfItem(
                    atPath: path.path),
                  let size = attrs[.size] as? Int64,
                  size == file.size
            else { return false }
        }
        return true
    }

    /// Delete every model version directory other than `currentVersion`.
    /// Called once at engine init so a freshly-updated app reclaims the
    /// ~4.5 GB occupied by a previous version's model without prompting.
    public func pruneOldVersions(keeping currentVersion: String) {
        let root = Self.rootDirectory
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isDirectoryKey]
        ) else { return }
        for entry in entries {
            let isDir = (try? entry.resourceValues(forKeys: [.isDirectoryKey])
                .isDirectory) ?? false
            guard isDir, entry.lastPathComponent != currentVersion else { continue }
            try? FileManager.default.removeItem(at: entry)
        }
    }

    public func diskUsage(version: String) -> Int64 {
        let dir = modelDirectory(version: version)
        guard let enumerator = FileManager.default.enumerator(
            at: dir, includingPropertiesForKeys: [.fileSizeKey]
        ) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            if let size = try? url.resourceValues(forKeys: [.fileSizeKey])
                .fileSize {
                total += Int64(size)
            }
        }
        return total
    }

    // MARK: - Public actions

    /// Start the download. No-op if already downloading.
    public func startDownload(version: String, allowCellular: Bool = false) {
        guard currentTask == nil else { return }
        let task = Task { [weak self] in
            guard let self = self else { return }
            await self.runDownload(version: version, allowCellular: allowCellular)
            await MainActor.run { self.currentTask = nil }
        }
        self.currentTask = task
    }

    public func cancelDownload() {
        currentTask?.cancel()
        currentTask = nil
        status = .cancelled
    }

    /// Delete a previously-installed model version. Use to reclaim space
    /// after a new version is installed.
    public func deleteModel(version: String) throws {
        let dir = modelDirectory(version: version)
        try FileManager.default.removeItem(at: dir)
        if case .completed = status { status = .idle }
    }

    // MARK: - Download driver

    private func runDownload(version: String, allowCellular: Bool) async {
        status = .fetchingManifest
        progress = .zero

        let config = urlSessionConfig
        config.allowsCellularAccess = allowCellular
        let session = URLSession(configuration: config)

        // 1. Fetch manifest
        let manifest: Manifest
        do {
            let (data, response) = try await session.data(from: Self.manifestURL)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else {
                throw DownloadError.manifestFetchFailed(
                    "HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
            }
            manifest = try JSONDecoder().decode(Manifest.self, from: data)
        } catch {
            status = .failed("Manifest fetch failed: \(error.localizedDescription)")
            return
        }

        // Reject the whole manifest before touching disk if any entry could
        // escape the model directory, collide with our own bookkeeping files,
        // or carry a malformed checksum.
        if let problem = ModelFileSafety.validate(manifest.files) {
            status = .failed("Manifest rejected: \(problem)")
            return
        }

        let dir = modelDirectory(version: version)
        try? FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true)

        // Drop metadata files (README, LICENSE, .gitattributes) so that
        // editing the model card on HF never invalidates an install.
        let essentialFiles = manifest.files.filter {
            !Self.isMetadataFile($0.name)
        }
        let totalBytes = essentialFiles.reduce(0) { $0 + $1.size }
        progress = Progress(bytesDownloaded: 0, bytesTotal: totalBytes)

        // 2. Download each file (skip if already valid)
        for (idx, file) in essentialFiles.enumerated() {
            if Task.isCancelled {
                status = .cancelled
                return
            }
            // Validated above, so this can't be nil; guarded anyway rather
            // than force-unwrapped.
            guard let destURL = ModelFileSafety.destination(for: file.name, in: dir) else {
                status = .failed("Manifest rejected: unsafe file name \(file.name)")
                return
            }
            if ModelFileSafety.canSkip(file, at: destURL, in: dir) {
                progress.bytesDownloaded += file.size
                continue
            }
            status = .downloading(
                currentFile: file.name,
                fileIndex: idx, totalFiles: essentialFiles.count
            )
            do {
                try await downloadFile(
                    file, to: destURL, session: session, basePriorBytes: progress.bytesDownloaded
                )
            } catch is CancellationError {
                status = .cancelled
                return
            } catch {
                status = .failed(
                    "Download of \(file.name) failed: " +
                    error.localizedDescription
                )
                return
            }

            // 3. Verify SHA
            status = .verifying(file: file.name)
            do {
                let actual = try await sha256OfFile(at: destURL)
                guard actual == file.sha256.lowercased() else {
                    try? FileManager.default.removeItem(at: destURL)
                    ModelFileSafety.forgetVerified(file.name, in: dir)
                    throw DownloadError.checksumMismatch(
                        file: file.name, expected: file.sha256, actual: actual)
                }
                ModelFileSafety.recordVerified(file.name, sha256: actual, in: dir)
            } catch {
                status = .failed("Checksum failed for \(file.name): " +
                                 error.localizedDescription)
                return
            }
        }

        // 4. Persist manifest so isModelInstalled() succeeds
        let manifestPath = dir.appendingPathComponent("manifest.json")
        do {
            let data = try JSONEncoder().encode(manifest)
            try data.write(to: manifestPath, options: .atomic)
        } catch {
            status = .failed("Failed to save manifest: \(error.localizedDescription)")
            return
        }

        status = .completed
    }

    private func downloadFile(
        _ file: ManifestFile,
        to destURL: URL,
        session: URLSession,
        basePriorBytes: Int64
    ) async throws {
        // `file.name` was validated as a safe relative path, so it can't
        // climb out of the pinned commit's directory on the server either.
        let url = Self.fileBaseURL.appendingPathComponent(file.name)
        var request = URLRequest(url: url)
        try FileManager.default.createDirectory(
            at: destURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        // Resume support: if a partial file exists, send a Range header
        var partialSize: Int64 = 0
        if let attrs = try? FileManager.default.attributesOfItem(
                atPath: destURL.path),
           let s = attrs[.size] as? Int64 {
            partialSize = s
        }
        if partialSize > file.size {
            // Longer than the manifest says: not a resumable partial (e.g. a
            // server that ignored Range and re-sent the whole body). Start over.
            try FileManager.default.removeItem(at: destURL)
            partialSize = 0
        }
        if partialSize > 0 && partialSize < file.size {
            request.addValue("bytes=\(partialSize)-", forHTTPHeaderField: "Range")
        } else if partialSize == file.size {
            // Complete on disk but unverified; the caller hashes it next.
            return
        }

        let delegate = DownloadDelegate(
            destURL: destURL,
            initialBytes: partialSize,
            totalBytes: file.size,
            basePriorBytes: basePriorBytes
        ) { [weak self] downloaded in
            guard let self = self else { return }
            Task { @MainActor in
                self.progress.bytesDownloaded = basePriorBytes + downloaded
            }
        }
        let delegatedSession = URLSession(
            configuration: session.configuration,
            delegate: delegate, delegateQueue: nil
        )
        let task = delegatedSession.downloadTask(with: request)
        delegate.task = task
        try await delegate.run(task)
    }

    private func sha256OfFile(at url: URL) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            var hasher = SHA256()
            while autoreleasepool(invoking: {
                if let chunk = try? handle.read(upToCount: 1 << 20),
                   !chunk.isEmpty {
                    hasher.update(data: chunk)
                    return true
                }
                return false
            }) {}
            return hasher.finalize().map { String(format: "%02x", $0) }.joined()
        }.value
    }
}

// MARK: - Manifest types

nonisolated struct Manifest: Codable {
    let version: String
    let files: [ManifestFile]
}

nonisolated struct ManifestFile: Codable, Equatable {
    let name: String
    let size: Int64
    let sha256: String
}

// MARK: - File safety

/// Checks that keep manifest data from steering writes, plus the record of
/// which files have actually been hashed.
///
/// Manifest names are network data used as path components, both on disk and
/// in the download URL. The manifest is fetched over HTTPS from a pinned
/// commit, so a bad entry takes a bad or compromised manifest. It's still
/// cheap to make that a refused download rather than a write outside the
/// model directory.
///
/// `nonisolated` and free of the downloader's state so tests can call it
/// directly.
nonisolated enum ModelFileSafety {

    /// Files the downloader writes itself. A manifest entry with one of these
    /// names would be overwritten by, or overwrite, the bookkeeping.
    static let reservedNames: Set<String> = ["manifest.json", "verified.json"]

    /// A relative path made only of ordinary components: letters, digits,
    /// `.`, `_` and `-`, separated by single `/`. No `.` or `..`
    /// components, no leading or trailing slash, no backslashes, no empty
    /// components.
    static func isSafeRelativePath(_ name: String) -> Bool {
        guard !name.isEmpty, name.count <= 255 else { return false }
        let components = name.split(separator: "/", omittingEmptySubsequences: false)
        return components.allSatisfy { component in
            !component.isEmpty && component != "." && component != ".."
                && component.allSatisfy { ch in
                    ch.isASCII && (ch.isLetter || ch.isNumber || ch == "." || ch == "_" || ch == "-")
                }
        }
    }

    /// Where `name` lives inside `dir`, or nil when it isn't a safe relative
    /// path or would resolve outside `dir`. The containment check is belt
    /// and braces on top of `isSafeRelativePath`.
    static func destination(for name: String, in dir: URL) -> URL? {
        guard isSafeRelativePath(name) else { return nil }
        let base = dir.standardizedFileURL
        let candidate = base.appendingPathComponent(name).standardizedFileURL
        let basePath = base.path.hasSuffix("/") ? base.path : base.path + "/"
        return candidate.path.hasPrefix(basePath) ? candidate : nil
    }

    static func isValidSHA256(_ value: String) -> Bool {
        value.count == 64 && value.allSatisfy { $0.isHexDigit }
    }

    /// First problem with a manifest's file list, or nil when every entry is
    /// usable.
    static func validate(_ files: [ManifestFile]) -> String? {
        var seen = Set<String>()
        for file in files {
            guard isSafeRelativePath(file.name) else { return "unsafe file name \"\(file.name)\"" }
            guard !reservedNames.contains(file.name.lowercased()) else {
                return "reserved file name \"\(file.name)\""
            }
            guard seen.insert(file.name.lowercased()).inserted else {
                return "duplicate file name \"\(file.name)\""
            }
            guard file.size >= 0 else { return "negative size for \(file.name)" }
            guard isValidSHA256(file.sha256) else { return "malformed checksum for \(file.name)" }
        }
        return nil
    }

    // MARK: Verification record

    /// True when a file already on disk can be skipped: the right size AND
    /// hashed-and-matched by an earlier run, per the verification record.
    ///
    /// Size alone isn't enough. If the app is killed after a download lands
    /// but before its SHA check finishes, the file has the right size and was
    /// never verified; trusting size would install it unchecked. Without a
    /// record the downloader falls through to the download step, which sees
    /// the file is complete and goes straight to verification.
    static func canSkip(_ file: ManifestFile, at url: URL, in dir: URL) -> Bool {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int64,
              size == file.size
        else { return false }
        return verifiedHash(of: file.name, in: dir) == file.sha256.lowercased()
    }

    private static func recordURL(in dir: URL) -> URL {
        dir.appendingPathComponent("verified.json")
    }

    private static func loadRecord(in dir: URL) -> [String: String] {
        guard let data = try? Data(contentsOf: recordURL(in: dir)),
              let record = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return record
    }

    private static func saveRecord(_ record: [String: String], in dir: URL) {
        guard let data = try? JSONEncoder().encode(record) else { return }
        try? data.write(to: recordURL(in: dir), options: .atomic)
    }

    /// The hash an earlier run computed and matched for `name`, lowercased.
    static func verifiedHash(of name: String, in dir: URL) -> String? {
        loadRecord(in: dir)[name]
    }

    static func recordVerified(_ name: String, sha256: String, in dir: URL) {
        var record = loadRecord(in: dir)
        record[name] = sha256.lowercased()
        saveRecord(record, in: dir)
    }

    static func forgetVerified(_ name: String, in dir: URL) {
        var record = loadRecord(in: dir)
        guard record.removeValue(forKey: name) != nil else { return }
        saveRecord(record, in: dir)
    }
}

private enum DownloadError: Error, LocalizedError {
    case manifestFetchFailed(String)
    case checksumMismatch(file: String, expected: String, actual: String)

    var errorDescription: String? {
        switch self {
        case .manifestFetchFailed(let s):
            return "Manifest fetch failed: \(s)"
        case .checksumMismatch(let f, let exp, let act):
            return "Checksum mismatch for \(f). " +
                   "Expected \(exp.prefix(12))…, got \(act.prefix(12))…"
        }
    }
}

// MARK: - URLSession delegate (resume + progress)

private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
    let destURL: URL
    let initialBytes: Int64
    let totalBytes: Int64
    let basePriorBytes: Int64
    let onProgress: (Int64) -> Void
    var task: URLSessionDownloadTask?
    private var continuation: CheckedContinuation<Void, Error>?

    init(destURL: URL, initialBytes: Int64, totalBytes: Int64,
         basePriorBytes: Int64, onProgress: @escaping (Int64) -> Void) {
        self.destURL = destURL
        self.initialBytes = initialBytes
        self.totalBytes = totalBytes
        self.basePriorBytes = basePriorBytes
        self.onProgress = onProgress
    }

    func run(_ task: URLSessionDownloadTask) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            self.continuation = cont
            task.resume()
        }
    }

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        onProgress(initialBytes + totalBytesWritten)
    }

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        do {
            if initialBytes > 0 {
                // Append the new range bytes to the existing partial file
                let fh = try FileHandle(forWritingTo: destURL)
                try fh.seekToEnd()
                let data = try Data(contentsOf: location)
                try fh.write(contentsOf: data)
                try fh.close()
            } else {
                if FileManager.default.fileExists(atPath: destURL.path) {
                    try FileManager.default.removeItem(at: destURL)
                }
                try FileManager.default.moveItem(at: location, to: destURL)
            }
            continuation?.resume()
            continuation = nil
        } catch {
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }

    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        if let error = error, continuation != nil {
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }
}
