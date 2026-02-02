import Foundation
@preconcurrency import WhisperKit
import CoreML

/// WhisperKit-based transcription engine
public actor WhisperKitEngine: TranscriptionEngine {
    public nonisolated let name: String
    public nonisolated let identifier: String
    public nonisolated let modelSize: Int64
    public nonisolated let modelType: ModelType

    /// WhisperKit model name (e.g., "tiny", "base", "small", "large-v3-turbo")
    private let whisperModelName: String

    private var whisperKit: WhisperKit?
    private var isLoading = false
    // nonisolated so progress polling doesn't block on actor
    private nonisolated(unsafe) var _downloadProgress: Double = 0
    private var isCancelled = false

    /// Optimized compute options for Apple Silicon
    /// Uses Neural Engine for maximum performance and energy efficiency
    private var computeOptions: ModelComputeOptions {
        ModelComputeOptions(
            melCompute: .cpuAndNeuralEngine,
            audioEncoderCompute: .cpuAndNeuralEngine,
            textDecoderCompute: .cpuAndNeuralEngine,
            prefillCompute: .cpuAndNeuralEngine
        )
    }

    public init(modelType: ModelType = .whisperBase) {
        self.modelType = modelType
        self.whisperModelName = modelType.whisperKitModelName ?? "base"
        self.identifier = modelType.rawValue
        self.name = modelType.displayName

        // Set model size based on variant
        switch modelType {
        case .whisperTiny:
            self.modelSize = 39_000_000
        case .whisperBase, .whisperKit:
            self.modelSize = 74_000_000
        case .whisperSmall:
            self.modelSize = 244_000_000
        case .whisperLargeTurbo:
            self.modelSize = 809_000_000
        default:
            self.modelSize = 74_000_000
        }
    }

    public var isModelDownloaded: Bool {
        get async {
            // Check if WhisperKit model directory exists with actual model files
            let modelDir = modelPath
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

    private var modelPath: URL {
        // WhisperKit downloads to: downloadBase/models/argmaxinc/whisperkit-coreml/openai_whisper-{model}
        let modelDirName: String
        switch modelType {
        case .whisperLargeTurbo:
            modelDirName = "openai_whisper-large-v3-turbo"
        default:
            modelDirName = "openai_whisper-\(whisperModelName)"
        }

        return ModelManager.modelsDirectory
            .appendingPathComponent("whisperkit")
            .appendingPathComponent("models")
            .appendingPathComponent("argmaxinc")
            .appendingPathComponent("whisperkit-coreml")
            .appendingPathComponent(modelDirName)
    }

    private var downloadBase: URL {
        ModelManager.modelsDirectory.appendingPathComponent("whisperkit")
    }

    public func downloadModel() async throws {
        guard !isLoading else { return }
        isLoading = true
        _downloadProgress = 0

        defer { isLoading = false }

        // Create models directory if needed
        print("FoxSay: Creating models directory at \(downloadBase.path)")
        try FileManager.default.createDirectory(
            at: downloadBase, withIntermediateDirectories: true)

        // Download and initialize WhisperKit
        do {
            print("FoxSay: Starting WhisperKit download for \(whisperModelName) to \(downloadBase.path)")

            // Start a background task to animate progress while downloading
            // WhisperKit doesn't expose download progress, so we simulate it
            // Adjust duration based on model size
            let progressDuration = modelType == .whisperLargeTurbo ? 300 : (modelType == .whisperSmall ? 200 : 100)
            let progressTask = Task {
                for i in 1...80 {
                    try Task.checkCancellation()
                    try await Task.sleep(for: .milliseconds(progressDuration))
                    _downloadProgress = Double(i) / 100.0
                }
            }

            // WhisperKit handles model download automatically
            // Use optimized compute options for Apple Neural Engine acceleration
            whisperKit = try await WhisperKit(
                model: whisperModelName,
                downloadBase: downloadBase,
                computeOptions: computeOptions,
                verbose: true
            )

            // Cancel the simulated progress
            progressTask.cancel()
            _downloadProgress = 1.0

            print("FoxSay: WhisperKit \(whisperModelName) model download complete")
            print("FoxSay: Model path exists: \(FileManager.default.fileExists(atPath: modelPath.path))")
        } catch {
            print("FoxSay: WhisperKit download failed: \(error)")
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

            // Load existing model with optimized compute options
            whisperKit = try await WhisperKit(
                model: whisperModelName,
                downloadBase: downloadBase,
                computeOptions: computeOptions,
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

        print("FoxSay: Preloading WhisperKit \(whisperModelName) model...")
        let startTime = CFAbsoluteTimeGetCurrent()

        // Load with optimized compute options for Apple Neural Engine
        whisperKit = try await WhisperKit(
            model: whisperModelName,
            downloadBase: downloadBase,
            computeOptions: computeOptions,
            verbose: false
        )

        let loadTime = CFAbsoluteTimeGetCurrent() - startTime
        print("FoxSay: WhisperKit \(whisperModelName) model preloaded in \(String(format: "%.2f", loadTime))s")
    }
}
