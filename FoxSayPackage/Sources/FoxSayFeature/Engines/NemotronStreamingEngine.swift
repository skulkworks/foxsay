import FluidAudio
import Foundation

/// Nemotron 3.5 Streaming Multilingual 0.6B via FluidAudio (CoreML/ANE).
///
/// Unlike the Parakeet engines, this one transcribes while the user is still
/// talking: audio goes in as it is captured and a running transcript comes back
/// roughly twice a second. FoxSay uses that for live text in the overlay and for
/// typing into the target app as you speak.
///
/// Two constants below are deliberate rather than configurable for now:
///
/// - **560 ms chunks.** The lowest-latency tier. Measured against the 2240 ms
///   tier on the same speech it produced identical text while updating four
///   times as often. FluidAudio warns that punctuation thins out at this tier on
///   long continuous sessions; a dictation hold is short by nature.
/// - **The `latin` variant.** A vocab-pruned ship covering en/es/fr/it/pt/de,
///   about 590 MB. The full `multilingual` ship is ~640 MB and covers 100+
///   languages; it is what to switch to if this ever gets a language picker.
public actor NemotronStreamingEngine: TranscriptionEngine, StreamingTranscriptionEngine {

    private static let chunkMs = 560
    private static let languageCode = "en-US"

    public nonisolated let name = "Nemotron Streaming"
    public nonisolated let identifier = "nemotron-streaming"
    public nonisolated let modelSize: Int64 = 590_000_000

    private var manager: StreamingNemotronMultilingualAsrManager?
    private var streamActive = false
    private var streamStart: Date?

    private let progress = ModelDownloadProgress()
    private let modelsRootOverride: URL?

    public init(modelsRoot: URL? = nil) {
        self.modelsRootOverride = modelsRoot
    }

    // MARK: - Model location

    private nonisolated var modelsRoot: URL? {
        if let modelsRootOverride { return modelsRootOverride }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("FluidAudio")
            .appendingPathComponent("Models")
    }

    /// FluidAudio lays this repo out as `<language group>/<tier>ms/`, so the
    /// download lands in a subdirectory rather than at the repo root.
    private nonisolated var variantDirectory: URL? {
        let group = StreamingNemotronMultilingualAsrManager.languageDirectory(for: Self.languageCode)
        return modelsRoot?
            .appendingPathComponent("nemotron-multilingual")
            .appendingPathComponent(group)
            .appendingPathComponent("\(Self.chunkMs)ms")
    }

    public var isModelDownloaded: Bool {
        get async {
            guard let dir = variantDirectory else { return false }
            // metadata.json carries the prompt dictionary the manager refuses to
            // load without, so its presence is the honest "is this usable" check.
            let metadata = dir.appendingPathComponent("metadata.json")
            return FileManager.default.fileExists(atPath: metadata.path)
        }
    }

    public var downloadProgress: Double {
        get async { progress.value }
    }

    // MARK: - Download and load

    public func downloadModel() async throws {
        progress.reset()
        print("FoxSay: Starting Nemotron streaming model download via FluidAudio...")

        do {
            let dir = try await StreamingNemotronMultilingualAsrManager.downloadVariant(
                languageCode: Self.languageCode,
                chunkMs: Self.chunkMs,
                progressHandler: { [progress] update in
                    // Downloading is the long pole; loading the models afterwards
                    // gets the last sliver of the bar.
                    progress.advance(to: update.fractionCompleted * 0.9)
                }
            )

            print("FoxSay: Nemotron streaming model downloaded, initializing...")
            try await load(from: dir)
            progress.advance(to: 1.0)
            print("FoxSay: Nemotron streaming model download complete")
        } catch {
            if Task.isCancelled {
                print("FoxSay: Nemotron streaming download cancelled")
                throw CancellationError()
            }
            print("FoxSay: Nemotron streaming download failed: \(error)")
            throw TranscriptionError.transcriptionFailed(
                "Failed to download the Nemotron streaming model: \(error.localizedDescription)")
        }
    }

    public func preload() async throws {
        guard manager == nil else { return }
        guard await isModelDownloaded, let dir = variantDirectory else {
            throw TranscriptionError.modelNotDownloaded
        }

        print("FoxSay: Preloading Nemotron streaming model...")
        let start = Date()
        try await load(from: dir)
        print(String(format: "FoxSay: Nemotron streaming model preloaded in %.2fs", Date().timeIntervalSince(start)))
    }

    private func load(from directory: URL) async throws {
        let manager = StreamingNemotronMultilingualAsrManager()
        try await manager.loadModels(from: directory)
        await manager.setLanguage(Self.languageCode)
        self.manager = manager
    }

    private func readyManager() async throws -> StreamingNemotronMultilingualAsrManager {
        if let manager { return manager }
        try await preload()
        guard let manager else { throw TranscriptionError.engineNotAvailable }
        return manager
    }

    // MARK: - Streaming

    public func startStream(onPartial: @escaping @Sendable (String) -> Void) async throws {
        let manager = try await readyManager()
        await manager.reset()
        await manager.setPartialCallback(onPartial)
        streamActive = true
        streamStart = Date()
    }

    public func appendStream(samples: [Float]) async throws {
        guard streamActive, let manager else { return }
        _ = try await manager.process(samples: samples)
    }

    public func finishStream() async throws -> TranscriptionResult {
        guard streamActive, let manager else {
            throw TranscriptionError.engineNotAvailable
        }
        streamActive = false

        let text = try await manager.finish()
        let elapsed = streamStart.map { Date().timeIntervalSince($0) } ?? 0
        streamStart = nil

        return TranscriptionResult(
            text: text.trimmingCharacters(in: .whitespacesAndNewlines),
            processingTime: elapsed
        )
    }

    public func cancelStream() async {
        streamActive = false
        streamStart = nil
        if let manager {
            await manager.reset()
        }
    }

    // MARK: - Batch fallback

    /// The whole-utterance path, for callers that have audio in hand rather than
    /// arriving — re-transcribing a history entry, or a streaming session that
    /// never got started. Feeds the buffer through the same model in one go.
    public func transcribe(audioBuffer: [Float]) async throws -> TranscriptionResult {
        let manager = try await readyManager()
        let start = Date()

        await manager.reset()
        _ = try await manager.process(samples: audioBuffer)
        let text = try await manager.finish()

        return TranscriptionResult(
            text: text.trimmingCharacters(in: .whitespacesAndNewlines),
            processingTime: Date().timeIntervalSince(start)
        )
    }

    public func cancel() async {
        await cancelStream()
    }
}
