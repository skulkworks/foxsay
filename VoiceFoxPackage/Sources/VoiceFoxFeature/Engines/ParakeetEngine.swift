import Foundation
import FluidAudio

/// Parakeet TDT engine via FluidAudio (CoreML/ANE)
/// This engine provides extremely fast transcription for English using NVIDIA's Parakeet model
/// accelerated by Apple's Neural Engine.
public actor ParakeetEngine: TranscriptionEngine {
    public nonisolated let name = "Parakeet"
    public nonisolated let identifier = "parakeet"
    public nonisolated let modelSize: Int64 = 450_000_000  // ~450MB for CoreML Parakeet TDT 0.6B v2

    // Using nonisolated(unsafe) because AsrManager handles its own thread safety
    // and FluidAudio is designed to be called from any context
    private nonisolated(unsafe) var asrManager: AsrManager?
    private var models: AsrModels?
    // nonisolated so progress polling doesn't block on actor
    private nonisolated(unsafe) var _downloadProgress: Double = 0
    private var transcriptionTask: Task<TranscriptionResult, Error>?
    private var isCancelled = false

    public init() {}

    public var isModelDownloaded: Bool {
        get async {
            // FluidAudio stores models in ~/Library/Application Support/FluidAudio/Models/
            let modelDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
                .appendingPathComponent("FluidAudio")
                .appendingPathComponent("Models")
                .appendingPathComponent("parakeet-tdt-0.6b-v2-coreml")

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

        print("VoiceFox: Starting Parakeet model download via FluidAudio...")

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
            // v2 is English-only with highest recall
            models = try await AsrModels.downloadAndLoad(version: .v2)

            // Cancel the simulated progress
            progressTask.cancel()
            _downloadProgress = 0.85

            print("VoiceFox: Parakeet models downloaded, initializing...")

            // Initialize ASR manager
            let manager = AsrManager(config: .default)
            _downloadProgress = 0.90
            try await manager.initialize(models: models!)
            asrManager = manager

            _downloadProgress = 1.0
            print("VoiceFox: Parakeet model download complete")
        } catch {
            print("VoiceFox: Parakeet download failed: \(error)")
            throw TranscriptionError.transcriptionFailed("Failed to download Parakeet model: \(error.localizedDescription)")
        }
    }

    public func transcribe(audioBuffer: [Float]) async throws -> TranscriptionResult {
        isCancelled = false

        // Ensure model is loaded
        if asrManager == nil {
            guard await isModelDownloaded else {
                throw TranscriptionError.modelNotDownloaded
            }

            // Load existing model
            print("VoiceFox: Loading Parakeet model...")
            models = try await AsrModels.downloadAndLoad(version: .v2)
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

        // FluidAudio expects 16kHz mono audio samples
        let result = try await manager.transcribe(audioBuffer)

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

        print("VoiceFox: Preloading Parakeet model...")
        let startTime = CFAbsoluteTimeGetCurrent()

        models = try await AsrModels.downloadAndLoad(version: .v2)
        let manager = AsrManager(config: .default)
        try await manager.initialize(models: models!)
        asrManager = manager

        let loadTime = CFAbsoluteTimeGetCurrent() - startTime
        print("VoiceFox: Parakeet model preloaded in \(String(format: "%.2f", loadTime))s")
    }
}
