import Foundation
import FluidAudio

/// Parakeet TDT engine via FluidAudio (CoreML/ANE)
/// This engine provides extremely fast transcription using NVIDIA's Parakeet model
/// accelerated by Apple's Neural Engine.
public actor ParakeetEngine: TranscriptionEngine {
    /// The model version this engine uses
    public let version: AsrModelVersion

    public nonisolated var name: String {
        switch version {
        case .v2: return "Parakeet V2"
        case .v3: return "Parakeet V3"
        }
    }

    public nonisolated var identifier: String {
        switch version {
        case .v2: return "parakeet-v2"
        case .v3: return "parakeet-v3"
        }
    }

    public nonisolated var modelSize: Int64 {
        switch version {
        case .v2: return 450_000_000  // ~450MB for V2
        case .v3: return 480_000_000  // ~480MB for V3
        }
    }

    // Using nonisolated(unsafe) because AsrManager handles its own thread safety
    // and FluidAudio is designed to be called from any context
    private nonisolated(unsafe) var asrManager: AsrManager?
    private var models: AsrModels?
    // nonisolated so progress polling doesn't block on actor
    private nonisolated(unsafe) var _downloadProgress: Double = 0
    private var transcriptionTask: Task<TranscriptionResult, Error>?
    private var isCancelled = false

    public init(version: AsrModelVersion = .v2) {
        self.version = version
    }

    public var isModelDownloaded: Bool {
        get async {
            // FluidAudio stores models in ~/Library/Application Support/FluidAudio/Models/
            let versionSuffix = version == .v2 ? "v2" : "v3"
            let modelDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
                .appendingPathComponent("FluidAudio")
                .appendingPathComponent("Models")
                .appendingPathComponent("parakeet-tdt-0.6b-\(versionSuffix)-coreml")

            guard let modelDir = modelDir else { return false }

            // Check if the vocab file exists (indicates complete download)
            let vocabPath = modelDir.appendingPathComponent("parakeet_vocab.json")
            return FileManager.default.fileExists(atPath: vocabPath.path)
        }
    }

    public var downloadProgress: Double {
        get async {
            _downloadProgress
        }
    }

    public func downloadModel() async throws {
        _downloadProgress = 0

        let versionLabel = version == .v2 ? "V2" : "V3"
        print("FoxSay: Starting Parakeet \(versionLabel) model download via FluidAudio...")

        do {
            // Start a background task to animate progress while downloading
            // FluidAudio doesn't expose download progress, so we simulate it
            let progressTask = Task {
                // Simulate download progress over ~20 seconds
                for i in 1...80 {
                    try Task.checkCancellation()
                    try await Task.sleep(for: .milliseconds(250))
                    // Progress from 0 to 0.8 during download
                    _downloadProgress = Double(i) / 100.0
                }
            }

            // FluidAudio handles downloading and caching automatically
            models = try await AsrModels.downloadAndLoad(version: version)

            // Cancel the simulated progress
            progressTask.cancel()
            _downloadProgress = 0.85

            print("FoxSay: Parakeet \(versionLabel) models downloaded, initializing...")

            // Initialize ASR manager
            let manager = AsrManager(config: .default)
            _downloadProgress = 0.90
            try await manager.initialize(models: models!)
            asrManager = manager

            _downloadProgress = 1.0
            print("FoxSay: Parakeet \(versionLabel) model download complete")
        } catch {
            print("FoxSay: Parakeet \(versionLabel) download failed: \(error)")
            throw TranscriptionError.transcriptionFailed("Failed to download Parakeet \(versionLabel) model: \(error.localizedDescription)")
        }
    }

    public func transcribe(audioBuffer: [Float]) async throws -> TranscriptionResult {
        isCancelled = false
        let versionLabel = version == .v2 ? "V2" : "V3"

        // Ensure model is loaded
        if asrManager == nil {
            guard await isModelDownloaded else {
                throw TranscriptionError.modelNotDownloaded
            }

            // Load existing model
            print("FoxSay: Loading Parakeet \(versionLabel) model...")
            models = try await AsrModels.downloadAndLoad(version: version)
            let manager = AsrManager(config: .default)
            try await manager.initialize(models: models!)
            asrManager = manager
        }

        guard let manager = asrManager else {
            throw TranscriptionError.engineNotAvailable
        }

        if isCancelled {
            throw TranscriptionError.cancelled
        }

        let startTime = CFAbsoluteTimeGetCurrent()

        // WORKAROUND: Pad short audio to > 240,000 samples to trigger ChunkProcessor
        // which properly handles isLastChunk for trailing punctuation (question marks)
        // See: FluidAudio bug where single-chunk path doesn't set isLastChunk: true
        var paddedBuffer = audioBuffer
        if audioBuffer.count <= 240_000 {
            let targetLength = 240_001
            paddedBuffer = audioBuffer + Array(repeating: 0, count: targetLength - audioBuffer.count)
        }
        let result = try await manager.transcribe(paddedBuffer)

        if isCancelled {
            throw TranscriptionError.cancelled
        }

        let processingTime = CFAbsoluteTimeGetCurrent() - startTime

        return TranscriptionResult(
            text: result.text,
            confidence: nil,
            processingTime: processingTime
        )
    }

    public func cancel() async {
        isCancelled = true
        transcriptionTask?.cancel()
        transcriptionTask = nil
    }

    public func preload() async throws {
        guard asrManager == nil else {
            // Already loaded
            return
        }

        guard await isModelDownloaded else {
            throw TranscriptionError.modelNotDownloaded
        }

        let versionLabel = version == .v2 ? "V2" : "V3"
        print("FoxSay: Preloading Parakeet \(versionLabel) model...")
        let startTime = CFAbsoluteTimeGetCurrent()

        models = try await AsrModels.downloadAndLoad(version: version)
        let manager = AsrManager(config: .default)
        try await manager.initialize(models: models!)
        asrManager = manager

        let loadTime = CFAbsoluteTimeGetCurrent() - startTime
        print("FoxSay: Parakeet \(versionLabel) model preloaded in \(String(format: "%.2f", loadTime))s")
    }
}
