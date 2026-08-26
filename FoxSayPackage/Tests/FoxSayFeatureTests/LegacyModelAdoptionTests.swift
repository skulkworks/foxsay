import Foundation
import Testing
import FluidAudio
@testable import FoxSayFeature

/// FoxSay 1.0.x shipped FluidAudio 0.10.0, which stored each Parakeet model
/// under its full HuggingFace repository name ("…-v2-coreml"); 0.15.5, which
/// 2.0.0 shipped, strips the "-coreml". Updating therefore left the model
/// where the app no longer looks, so it reported "Not downloaded" and pulled
/// several hundred megabytes the user already had.
@Suite("Adopting a model downloaded by FoxSay 1.x")
struct LegacyModelAdoptionTests {

    /// The four compiled models plus the vocabulary that FluidAudio 0.15.5
    /// checks for before it calls a V2 download complete. Contents are never
    /// read — `AsrModels.modelsExist` only asks whether each path is there.
    private static let v2Layout = [
        "Preprocessor.mlmodelc", "Encoder.mlmodelc", "Decoder.mlmodelc",
        "JointDecision.mlmodelc", "parakeet_vocab.json",
    ]

    /// What 1.0.x downloaded for V3. The joint model was renamed to
    /// JointDecisionv3.mlmodelc in the meantime, so this layout is missing a
    /// file the current build needs and cannot be adopted.
    private static let legacyV3Layout = [
        "Preprocessor.mlmodelc", "Encoder.mlmodelc", "Decoder.mlmodelc",
        "JointDecision.mlmodelc", "parakeet_vocab.json",
    ]

    private func makeModelsRoot() throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("foxsay-adoption-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func write(_ layout: [String], into directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for entry in layout {
            try FileManager.default.createDirectory(
                at: directory.appendingPathComponent(entry), withIntermediateDirectories: true)
        }
    }

    @Test("a V2 model left by 1.x is moved into the folder 2.x looks in")
    func adoptsV2() async throws {
        let root = try makeModelsRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let legacy = root.appendingPathComponent("parakeet-tdt-0.6b-v2-coreml")
        let current = root.appendingPathComponent("parakeet-tdt-0.6b-v2")
        try write(Self.v2Layout, into: legacy)

        let engine = ParakeetEngine(version: .v2, modelsRoot: root)
        #expect(await engine.isModelDownloaded == false)

        await engine.adoptLegacyDownload()

        #expect(FileManager.default.fileExists(atPath: current.path))
        #expect(!FileManager.default.fileExists(atPath: legacy.path))
        #expect(await engine.isModelDownloaded)
    }

    @Test("a V3 model left by 1.x is put back, because its layout changed")
    func leavesIncompatibleV3Alone() async throws {
        let root = try makeModelsRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let legacy = root.appendingPathComponent("parakeet-tdt-0.6b-v3-coreml")
        let current = root.appendingPathComponent("parakeet-tdt-0.6b-v3")
        try write(Self.legacyV3Layout, into: legacy)

        let engine = ParakeetEngine(version: .v3, modelsRoot: root)
        await engine.adoptLegacyDownload()

        #expect(FileManager.default.fileExists(atPath: legacy.path))
        #expect(!FileManager.default.fileExists(atPath: current.path))
    }

    @Test("an existing download is never moved onto")
    func doesNotClobberCurrentDownload() async throws {
        let root = try makeModelsRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let legacy = root.appendingPathComponent("parakeet-tdt-0.6b-v2-coreml")
        let current = root.appendingPathComponent("parakeet-tdt-0.6b-v2")
        try write(Self.v2Layout, into: legacy)
        try write(Self.v2Layout, into: current)
        // Mark the current copy so a move over the top would be detectable.
        try Data("current".utf8).write(to: current.appendingPathComponent("marker"))

        let engine = ParakeetEngine(version: .v2, modelsRoot: root)
        await engine.adoptLegacyDownload()

        #expect(FileManager.default.fileExists(atPath: current.appendingPathComponent("marker").path))
        #expect(FileManager.default.fileExists(atPath: legacy.path))
    }

    @Test("versions that only ever existed in 2.x have nothing to adopt")
    func ignoresVersionsWithNoLegacyFolder() async throws {
        let root = try makeModelsRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let strayLegacy = root.appendingPathComponent("parakeet-tdt-ctc-110m-coreml")
        try write(Self.v2Layout, into: strayLegacy)

        let engine = ParakeetEngine(version: .tdtCtc110m, modelsRoot: root)
        await engine.adoptLegacyDownload()

        #expect(FileManager.default.fileExists(atPath: strayLegacy.path))
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("parakeet-tdt-ctc-110m").path))
    }
}
