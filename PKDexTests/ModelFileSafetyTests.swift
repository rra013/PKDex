//
//  ModelFileSafetyTests.swift
//  PKDexTests
//
//  Covers the model downloader's defences against manifest data: path
//  validation (manifest names become file paths and URL components),
//  manifest-wide checks, and the verification record that stops a
//  right-sized but never-hashed file from being skipped on resume.
//
//  Filesystem tests run in a fresh temporary directory per test.
//

import Testing
import Foundation
@testable import PKDex

@Suite("Model Download — File Safety")
struct ModelFileSafetyTests {

    private static let goodSHA = String(repeating: "a", count: 64)

    private static func file(_ name: String, size: Int64 = 10,
                             sha: String = goodSHA) -> ManifestFile {
        ManifestFile(name: name, size: size, sha256: sha)
    }

    private static func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ModelFileSafetyTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Names

    /// Every file in the real pinned manifest (3b-v3), plus a nested path.
    @Test("Real manifest names are accepted", arguments: [
        "README.md", "chat_template.jinja", "config.json", "generation_config.json",
        "model.safetensors", "model.safetensors.index.json", "tokenizer.json",
        "tokenizer_config.json", ".gitattributes", "LICENSE", "sub/dir/weights.bin",
    ])
    func acceptsSafeNames(name: String) {
        #expect(ModelFileSafety.isSafeRelativePath(name))
    }

    @Test("Unsafe names are rejected", arguments: [
        "", "..", ".", "../escape", "a/../../escape", "/etc/passwd", "a//b", "a/",
        "a\\b", "..\\escape", "name with space.json", "tëst.json", "x\u{0}y",
        String(repeating: "a", count: 256),
    ])
    func rejectsUnsafeNames(name: String) {
        #expect(!ModelFileSafety.isSafeRelativePath(name))
    }

    @Test("Destination stays inside the directory")
    func destinationContainment() throws {
        let dir = try Self.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let inside = try #require(ModelFileSafety.destination(for: "sub/config.json", in: dir))
        #expect(inside.path.hasPrefix(dir.standardizedFileURL.path + "/"))
        #expect(ModelFileSafety.destination(for: "../outside.json", in: dir) == nil)
        #expect(ModelFileSafety.destination(for: "/etc/passwd", in: dir) == nil)
    }

    // MARK: - Manifest

    @Test("A well-formed manifest passes")
    func validManifest() {
        #expect(ModelFileSafety.validate([Self.file("config.json"),
                                          Self.file("model.safetensors")]) == nil)
    }

    @Test("Bad manifests are rejected with a reason", arguments: [
        [ManifestFile(name: "../x", size: 1, sha256: String(repeating: "a", count: 64))],
        [ManifestFile(name: "manifest.json", size: 1, sha256: String(repeating: "a", count: 64))],
        [ManifestFile(name: "Verified.JSON", size: 1, sha256: String(repeating: "a", count: 64))],
        [ManifestFile(name: "a.json", size: 1, sha256: String(repeating: "a", count: 64)),
         ManifestFile(name: "A.json", size: 1, sha256: String(repeating: "b", count: 64))],
        [ManifestFile(name: "a.json", size: -1, sha256: String(repeating: "a", count: 64))],
        [ManifestFile(name: "a.json", size: 1, sha256: "abc123")],
        [ManifestFile(name: "a.json", size: 1, sha256: String(repeating: "g", count: 64))],
    ])
    func invalidManifests(files: [ManifestFile]) {
        #expect(ModelFileSafety.validate(files) != nil)
    }

    // MARK: - Verification record and skipping

    @Test("A right-sized file is not skipped until it's been verified")
    func unverifiedFileIsNotSkipped() throws {
        let dir = try Self.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let entry = Self.file("model.safetensors", size: 4)
        let url = dir.appendingPathComponent(entry.name)
        try Data([1, 2, 3, 4]).write(to: url)

        // Right size, never hashed: the killed-before-verify case.
        #expect(!ModelFileSafety.canSkip(entry, at: url, in: dir))

        ModelFileSafety.recordVerified(entry.name, sha256: entry.sha256.uppercased(), in: dir)
        #expect(ModelFileSafety.canSkip(entry, at: url, in: dir),
                "recorded hashes compare case-insensitively")

        ModelFileSafety.forgetVerified(entry.name, in: dir)
        #expect(!ModelFileSafety.canSkip(entry, at: url, in: dir))
    }

    @Test("A verified file is re-checked when the manifest's hash or size changes")
    func staleRecordIsNotTrusted() throws {
        let dir = try Self.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let entry = Self.file("model.safetensors", size: 4)
        let url = dir.appendingPathComponent(entry.name)
        try Data([1, 2, 3, 4]).write(to: url)
        ModelFileSafety.recordVerified(entry.name, sha256: entry.sha256, in: dir)

        let newHash = ManifestFile(name: entry.name, size: 4,
                                   sha256: String(repeating: "b", count: 64))
        #expect(!ModelFileSafety.canSkip(newHash, at: url, in: dir))

        let newSize = ManifestFile(name: entry.name, size: 5, sha256: entry.sha256)
        #expect(!ModelFileSafety.canSkip(newSize, at: url, in: dir))
    }

    @Test("A missing file is never skipped, even with a record")
    func missingFile() throws {
        let dir = try Self.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let entry = Self.file("config.json")
        ModelFileSafety.recordVerified(entry.name, sha256: entry.sha256, in: dir)
        #expect(!ModelFileSafety.canSkip(entry, at: dir.appendingPathComponent(entry.name), in: dir))
    }
}
