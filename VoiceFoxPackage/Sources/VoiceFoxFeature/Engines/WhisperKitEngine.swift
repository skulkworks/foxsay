import Foundation
@preconcurrency import WhisperKit

/// WhisperKit-based transcription engine
public actor WhisperKitEngine: TranscriptionEngine {
    public nonisolated let name = "WhisperKit"
    public nonisolated let identifier = "whisperkit"
    public nonisolated let modelSize: Int64 = 150_000_000  // ~150MB for base.en

    private var whisperKit: WhisperKit?
    private var isLoading = false
    private var _downloadProgress: Double = 0
    private var isCancelled = false

    public init() {}

    public var isModelDownloaded: Bool {
        get async {
            // Check if WhisperKit model directory exists with actual model files
            // WhisperKit downloads to: downloadBase/argmaxinc/whisperkit-coreml/openai_whisper-base.en/
            let modelDir = Self.modelPath
            guard FileManager.default.fileExists(atPath: modelDir.path) else {
                return false
            }

            // Check for key model files (MelSpectrogram.mlmodelc is always present)
            let melPath = modelDir.appendingPathComponent("MelSpectrogram.mlmodelc")
            return FileManager.default.fileExists(atPath: melPath.path)
        }
    }

    public var downloadProgress: Double {
        get async {
            _downloadProgress
        }
    }

    private static var modelPath: URL {
        // WhisperKit downloads to: downloadBase/models/argmaxinc/whisperkit-coreml/openai_whisper-base.en
        EngineManager.modelsDirectory
            .appendingPathComponent("whisperkit")
            .appendingPathComponent("models")
            .appendingPathComponent("argmaxinc")
            .appendingPathComponent("whisperkit-coreml")
            .appendingPathComponent("openai_whisper-base.en")
    }

    public func downloadModel() async throws {
        guard !isLoading else { return }
        isLoading = true
        _downloadProgress = 0

        defer { isLoading = false }

        // Create models directory if needed
        let modelsDir = EngineManager.modelsDirectory
        let whisperKitDir = modelsDir.appendingPathComponent("whisperkit")

        print("VoiceFox: Creating models directory at \(modelsDir.path)")
        try FileManager.default.createDirectory(
            at: whisperKitDir, withIntermediateDirectories: true)

        // Download and initialize WhisperKit with base.en model
        do {
            _downloadProgress = 0.1
            print("VoiceFox: Starting WhisperKit download to \(whisperKitDir.path)")

            // WhisperKit handles model download automatically
            whisperKit = try await WhisperKit(
                model: "base.en",
                downloadBase: whisperKitDir,
                verbose: true  // Enable verbose logging to see what's happening
            )

            _downloadProgress = 1.0
            print("VoiceFox: WhisperKit model download complete")
            print("VoiceFox: Model path exists: \(FileManager.default.fileExists(atPath: Self.modelPath.path))")
        } catch {
            print("VoiceFox: WhisperKit download failed: \(error)")
            throw TranscriptionError.transcriptionFailed("Failed to download model: \(error.localizedDescription)")
        }
    }

    public func transcribe(audioBuffer: [Float]) async throws -> TranscriptionResult {
        // Reset cancelled flag
        isCancelled = false

        // Ensure model is loaded
        if whisperKit == nil {
            guard await isModelDownloaded else {
                throw TranscriptionError.modelNotDownloaded
            }

            // Load existing model
            let modelsDir = EngineManager.modelsDirectory
            whisperKit = try await WhisperKit(
                model: "base.en",
                downloadBase: modelsDir.appendingPathComponent("whisperkit"),
                verbose: false
            )
        }

        guard let kit = whisperKit else {
            throw TranscriptionError.engineNotAvailable
        }

        // Check for cancellation
        if isCancelled {
            throw TranscriptionError.cancelled
        }

        let startTime = CFAbsoluteTimeGetCurrent()

        // Perform transcription directly in actor context
        let results = try await kit.transcribe(audioArray: audioBuffer)

        // Check for cancellation again
        if isCancelled {
            throw TranscriptionError.cancelled
        }

        let text = results.map { $0.text }.joined(separator: " ").trimmingCharacters(
            in: .whitespacesAndNewlines)

        let processingTime = CFAbsoluteTimeGetCurrent() - startTime

        return TranscriptionResult(
            text: text,
            confidence: nil,
            processingTime: processingTime
        )
    }

    public func cancel() async {
        isCancelled = true
    }

    /// Preload the model into memory for faster first transcription
    public func preload() async throws {
        guard whisperKit == nil else {
            // Already loaded
            return
        }

        guard await isModelDownloaded else {
            throw TranscriptionError.modelNotDownloaded
        }

        print("VoiceFox: Preloading WhisperKit model...")
        let startTime = CFAbsoluteTimeGetCurrent()

        let modelsDir = EngineManager.modelsDirectory
        whisperKit = try await WhisperKit(
            model: "base.en",
            downloadBase: modelsDir.appendingPathComponent("whisperkit"),
            verbose: false
        )

        let loadTime = CFAbsoluteTimeGetCurrent() - startTime
        print("VoiceFox: WhisperKit model preloaded in \(String(format: "%.2f", loadTime))s")
    }
}
