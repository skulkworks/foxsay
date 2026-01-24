import Foundation

/// Manages transcription engines and model downloads
@MainActor
public class EngineManager: ObservableObject {
    public static let shared = EngineManager()

    @Published public private(set) var currentEngineType: EngineType
    @Published public private(set) var isDownloading = false
    @Published public private(set) var downloadProgress: Double = 0
    @Published public private(set) var downloadError: String?
    @Published public private(set) var isModelReady = false
    @Published public private(set) var isPreloading = false
    @Published public private(set) var isEngineReady = false

    private var engines: [EngineType: any TranscriptionEngine] = [:]
    private var downloadTask: Task<Void, Error>?

    private init() {
        let savedEngine = UserDefaults.standard.string(forKey: "selectedEngine") ?? "whisperkit"
        currentEngineType = EngineType(rawValue: savedEngine) ?? .whisperKit

        // Initialize available engines
        engines[.whisperKit] = WhisperKitEngine()
        // Parakeet engine requires additional setup

        // Check initial model state and preload if ready
        Task {
            await refreshModelReadyState()
            if isModelReady {
                await preloadCurrentEngine()
            }
        }
    }

    /// Get the currently selected engine
    public var currentEngine: (any TranscriptionEngine)? {
        engines[currentEngineType]
    }

    /// Select a different engine
    public func selectEngine(_ type: EngineType) async {
        currentEngineType = type
        UserDefaults.standard.set(type.rawValue, forKey: "selectedEngine")
        isEngineReady = false  // Reset - new engine needs preloading
        await refreshModelReadyState()
        if isModelReady {
            await preloadCurrentEngine()
        }
    }

    /// Refresh the model ready state
    public func refreshModelReadyState() async {
        guard let engine = currentEngine else {
            isModelReady = false
            isEngineReady = false
            return
        }
        isModelReady = await engine.isModelDownloaded
    }

    /// Preload the current engine's model into memory
    public func preloadCurrentEngine() async {
        guard let engine = currentEngine else { return }
        guard isModelReady else { return }
        guard !isEngineReady else { return }  // Already preloaded

        isPreloading = true
        print("VoiceFox: Starting engine preload...")

        do {
            try await engine.preload()
            isEngineReady = true
            print("VoiceFox: Engine preload complete")
        } catch {
            print("VoiceFox: Engine preload failed: \(error)")
            // Non-fatal - will load on first use
        }

        isPreloading = false
    }

    /// Download the model for the current engine
    public func downloadCurrentModel() async throws {
        guard let engine = currentEngine else {
            throw TranscriptionError.engineNotAvailable
        }

        isDownloading = true
        downloadProgress = 0
        downloadError = nil

        do {
            // Start progress polling task
            let progressTask = Task {
                while !Task.isCancelled {
                    let progress = await engine.downloadProgress
                    await MainActor.run {
                        self.downloadProgress = progress
                    }
                    try await Task.sleep(nanoseconds: 100_000_000)  // 100ms
                }
            }

            // Download the model
            try await engine.downloadModel()

            // Cancel progress polling
            progressTask.cancel()

            // Update final state
            downloadProgress = 1.0
            isDownloading = false
            await refreshModelReadyState()

            // Preload the model after download
            await preloadCurrentEngine()
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

    /// Transcribe audio using the current engine
    public func transcribe(audioBuffer: [Float]) async throws -> TranscriptionResult {
        guard let engine = currentEngine else {
            throw TranscriptionError.engineNotAvailable
        }

        guard await engine.isModelDownloaded else {
            throw TranscriptionError.modelNotDownloaded
        }

        let startTime = CFAbsoluteTimeGetCurrent()
        let result = try await engine.transcribe(audioBuffer: audioBuffer)
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
        await currentEngine?.cancel()
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
