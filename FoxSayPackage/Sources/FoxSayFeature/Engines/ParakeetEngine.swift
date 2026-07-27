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
        case .tdtCtc110m: return "Parakeet TDT-CTC 110M"
        case .tdtJa: return "Parakeet Japanese"
        @unknown default: return "Parakeet"
        }
    }

    public nonisolated var identifier: String {
        switch version {
        case .v2: return "parakeet-v2"
        case .v3: return "parakeet-v3"
        case .tdtCtc110m: return "parakeet-tdt-ctc-110m"
        case .tdtJa: return "parakeet-ja"
        @unknown default: return "parakeet"
        }
    }

    public nonisolated var modelSize: Int64 {
        switch version {
        case .v2: return 450_000_000  // ~450MB for V2
        case .v3: return 480_000_000  // ~480MB for V3
        case .tdtCtc110m: return 230_000_000  // fused preprocessor+encoder, much smaller
        case .tdtJa: return 620_000_000
        @unknown default: return 480_000_000
        }
    }

    /// Short label used in log messages ("V2", "110M", ...)
    private nonisolated var versionLabel: String {
        switch version {
        case .v2: return "V2"
        case .v3: return "V3"
        case .tdtCtc110m: return "TDT-CTC 110M"
        case .tdtJa: return "Japanese"
        @unknown default: return "unknown"
        }
    }

    /// Directory FluidAudio downloads this version into, under
    /// ~/Library/Application Support/FluidAudio/Models/
    private nonisolated var modelDirectoryName: String {
        switch version {
        case .v2: return "parakeet-tdt-0.6b-v2-coreml"
        case .v3: return "parakeet-tdt-0.6b-v3-coreml"
        case .tdtCtc110m: return "parakeet-tdt-ctc-110m-coreml"
        case .tdtJa: return "parakeet-0.6b-ja-coreml"
        @unknown default: return "parakeet-tdt-0.6b-v2-coreml"
        }
    }

    /// Vocabulary file whose presence indicates a complete download. The Japanese
    /// repo ships vocab.json where the others ship parakeet_vocab.json.
    private nonisolated var vocabFileName: String {
        switch version {
        case .tdtJa: return "vocab.json"
        default: return "parakeet_vocab.json"
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
            let modelDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
                .appendingPathComponent("FluidAudio")
                .appendingPathComponent("Models")
                .appendingPathComponent(modelDirectoryName)

            guard let modelDir = modelDir else { return false }

            // Check if the vocab file exists (indicates complete download)
            let vocabPath = modelDir.appendingPathComponent(vocabFileName)
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
            try await manager.loadModels(models!)
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

        // Ensure model is loaded
        if asrManager == nil {
            guard await isModelDownloaded else {
                throw TranscriptionError.modelNotDownloaded
            }

            // Load existing model
            print("FoxSay: Loading Parakeet \(versionLabel) model...")
            models = try await AsrModels.downloadAndLoad(version: version)
            let manager = AsrManager(config: .default)
            try await manager.loadModels(models!)
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
        // FoxSay transcribes one complete utterance per call, so each transcription
        // starts from a fresh decoder state. Carrying state across calls is only
        // useful for streaming, where chunks continue a single utterance.
        // decoderLayers varies by version (tdtCtc110m uses 1, the rest use 2).
        var decoderState = try TdtDecoderState(decoderLayers: version.decoderLayers)
        let result = try await manager.transcribe(paddedBuffer, decoderState: &decoderState)

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

        print("FoxSay: Preloading Parakeet \(versionLabel) model...")
        let startTime = CFAbsoluteTimeGetCurrent()

        models = try await AsrModels.downloadAndLoad(version: version)
        let manager = AsrManager(config: .default)
        try await manager.loadModels(models!)
        asrManager = manager

        let loadTime = CFAbsoluteTimeGetCurrent() - startTime
        print("FoxSay: Parakeet \(versionLabel) model preloaded in \(String(format: "%.2f", loadTime))s")
    }
}
