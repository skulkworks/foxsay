import Foundation

/// Manages transcription models and model downloads
@MainActor
public class ModelManager: ObservableObject {
    public static let shared = ModelManager()

    @Published public private(set) var currentModelType: ModelType
    @Published public private(set) var isDownloading = false
    @Published public private(set) var downloadProgress: Double = 0
    @Published public private(set) var downloadError: String?
    @Published public private(set) var isModelReady = false
    @Published public private(set) var isPreloading = false
    @Published public private(set) var isModelLoaded = false

    private var models: [ModelType: any TranscriptionEngine] = [:]
    private var downloadTask: Task<Void, Error>?

    private init() {
        // Read from both old and new keys for backward compatibility
        let savedModel = UserDefaults.standard.string(forKey: "selectedModel")
            ?? UserDefaults.standard.string(forKey: "selectedEngine")
            ?? "parakeet"
        currentModelType = ModelType(rawValue: savedModel) ?? .parakeetV2

        // Initialize available models
        // Whisper variants
        models[.whisperTiny] = WhisperKitEngine(modelType: .whisperTiny)
        models[.whisperBase] = WhisperKitEngine(modelType: .whisperBase)
        models[.whisperSmall] = WhisperKitEngine(modelType: .whisperSmall)
        models[.whisperLargeTurbo] = WhisperKitEngine(modelType: .whisperLargeTurbo)
        models[.whisperKit] = models[.whisperBase]  // Legacy alias points to base

        // Parakeet variants
        models[.parakeetV2] = ParakeetEngine(version: .v2)
        models[.parakeetV3] = ParakeetEngine(version: .v3)

        // Check initial model state and preload if ready
        Task {
            await refreshModelReadyState()
            if isModelReady {
                await preloadCurrentModel()
            }
        }
    }

    /// Get the currently selected model
    public var currentModel: (any TranscriptionEngine)? {
        models[currentModelType]
    }

    /// Select a different model
    public func selectModel(_ type: ModelType) async {
        currentModelType = type
        UserDefaults.standard.set(type.rawValue, forKey: "selectedModel")
        isModelLoaded = false  // Reset - new model needs preloading
        await refreshModelReadyState()
        if isModelReady {
            await preloadCurrentModel()
        }
    }

    // MARK: - Backward Compatibility

    /// Alias for currentModelType (backward compatibility)
    public var currentEngineType: ModelType { currentModelType }

    /// Alias for currentModel (backward compatibility)
    public var currentEngine: (any TranscriptionEngine)? { currentModel }

    /// Alias for isModelLoaded (backward compatibility)
    public var isEngineReady: Bool { isModelLoaded }

    /// Select engine (backward compatibility)
    public func selectEngine(_ type: ModelType) async {
        await selectModel(type)
    }

    /// Refresh the model ready state
    public func refreshModelReadyState() async {
        guard let model = currentModel else {
            isModelReady = false
            isModelLoaded = false
            return
        }
        isModelReady = await model.isModelDownloaded
    }

    /// Preload the current model into memory
    public func preloadCurrentModel() async {
        guard let model = currentModel else { return }
        guard isModelReady else { return }
        guard !isModelLoaded else { return }  // Already preloaded

        isPreloading = true
        print("VoiceFox: Starting model preload...")

        do {
            try await model.preload()
            isModelLoaded = true
            print("VoiceFox: Model preload complete")
        } catch {
            print("VoiceFox: Model preload failed: \(error)")
            // Non-fatal - will load on first use
        }

        isPreloading = false
    }

    // Backward compatibility alias
    public func preloadCurrentEngine() async {
        await preloadCurrentModel()
    }

    /// Download the model for the current selection
    public func downloadCurrentModel() async throws {
        guard let model = currentModel else {
            throw TranscriptionError.engineNotAvailable
        }

        isDownloading = true
        downloadProgress = 0
        downloadError = nil

        do {
            // Start progress polling task
            let progressTask = Task {
                while !Task.isCancelled {
                    let progress = await model.downloadProgress
                    await MainActor.run {
                        self.downloadProgress = progress
                    }
                    try await Task.sleep(nanoseconds: 100_000_000)  // 100ms
                }
            }

            // Download the model
            try await model.downloadModel()

            // Cancel progress polling
            progressTask.cancel()

            // Update final state
            downloadProgress = 1.0
            isDownloading = false
            await refreshModelReadyState()

            // Preload the model after download
            await preloadCurrentModel()
        } catch {
            isDownloading = false
            downloadError = error.localizedDescription
            throw error
        }
    }

    /// Cancel ongoing download
    public func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        isDownloading = false
    }

    /// Transcribe audio using the current model
    public func transcribe(audioBuffer: [Float]) async throws -> TranscriptionResult {
        guard let model = currentModel else {
            throw TranscriptionError.engineNotAvailable
        }

        guard await model.isModelDownloaded else {
            throw TranscriptionError.modelNotDownloaded
        }

        let startTime = CFAbsoluteTimeGetCurrent()
        let result = try await model.transcribe(audioBuffer: audioBuffer)
        let processingTime = CFAbsoluteTimeGetCurrent() - startTime

        return TranscriptionResult(
            text: result.text,
            confidence: result.confidence,
            processingTime: processingTime,
            wasDevCorrected: result.wasDevCorrected,
            originalText: result.originalText
        )
    }

    /// Cancel ongoing transcription
    public func cancelTranscription() async {
        await currentModel?.cancel()
    }

    /// Clean up resources
    public func cleanup() async {
        cancelDownload()
        await cancelTranscription()
    }

    /// Get model directory path (nonisolated for use in actors)
    public nonisolated static var modelsDirectory: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        return appSupport.appendingPathComponent("VoiceFox/Models", isDirectory: true)
    }
}

/// Type alias for backward compatibility
public typealias EngineManager = ModelManager
