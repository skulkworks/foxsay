import Foundation
import MLXLLM
import MLXLMCommon

/// Manages the LLM model for text correction
@MainActor
public class LLMModelManager: ObservableObject {
    public static let shared = LLMModelManager()

    /// The HuggingFace model ID for the code correction model
    public static nonisolated let modelId = "mlx-community/Qwen2.5-Coder-0.5B-Instruct-4bit"

    /// Approximate model size for display
    public static let modelSizeMB = 278

    @Published public private(set) var isDownloading = false
    @Published public private(set) var downloadProgress: Double = 0
    @Published public private(set) var isModelReady = false
    @Published public private(set) var downloadError: String?
    @Published public private(set) var isPreloading = false

    private var loadedModel: ModelContainer?
    private var downloadTask: Task<Void, Error>?

    private init() {
        // Check if model is already downloaded
        Task {
            await checkModelStatus()
        }
    }

    /// Check if the model files exist locally
    public func checkModelStatus() async {
        isModelReady = isModelDownloaded()
    }

    /// Check if model is downloaded by looking for model files
    public nonisolated func isModelDownloaded() -> Bool {
        // mlx-swift-lm stores models in caches directory via Hub
        let modelName = Self.modelId.replacingOccurrences(of: "/", with: "--")

        // Check common HuggingFace Hub cache locations
        let possiblePaths = [
            // Default Hub cache location (caches directory)
            FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
                .appendingPathComponent("huggingface/hub/models--\(modelName)"),
            // Alternative cache location
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".cache/huggingface/hub/models--\(modelName)"),
        ].compactMap { $0 }

        for path in possiblePaths {
            if FileManager.default.fileExists(atPath: path.path) {
                // Check for snapshots directory which indicates complete download
                let snapshotsPath = path.appendingPathComponent("snapshots")
                if FileManager.default.fileExists(atPath: snapshotsPath.path) {
                    // Check if there's at least one snapshot with model files
                    if let snapshots = try? FileManager.default.contentsOfDirectory(atPath: snapshotsPath.path),
                       !snapshots.isEmpty {
                        let firstSnapshot = snapshotsPath.appendingPathComponent(snapshots[0])
                        // Check for config.json as indicator of complete model
                        if FileManager.default.fileExists(atPath: firstSnapshot.appendingPathComponent("config.json").path) {
                            return true
                        }
                    }
                }
            }
        }

        return false
    }

    /// Download the LLM model from HuggingFace
    public func downloadModel() async throws {
        guard !isDownloading else { return }

        isDownloading = true
        downloadProgress = 0
        downloadError = nil

        print("VoiceFox: Starting LLM model download: \(Self.modelId)")

        do {
            // Start a background task to simulate progress while downloading
            // The Hub library has progress callbacks but they're not always granular
            let progressTask = Task {
                for i in 1...80 {
                    try Task.checkCancellation()
                    try await Task.sleep(for: .milliseconds(200))
                    await MainActor.run {
                        // Only update if we haven't gotten real progress yet
                        if self.downloadProgress < Double(i) / 100.0 {
                            self.downloadProgress = Double(i) / 100.0
                        }
                    }
                }
            }

            // Load the model - this downloads it if not cached
            let container = try await loadModelContainer(id: Self.modelId) { progress in
                Task { @MainActor in
                    // Progress is a Foundation Progress object
                    let fraction = progress.fractionCompleted
                    if fraction > self.downloadProgress {
                        self.downloadProgress = fraction
                    }
                }
            }

            // Cancel simulated progress
            progressTask.cancel()
            downloadProgress = 0.95

            // Store the loaded model
            loadedModel = container

            downloadProgress = 1.0
            isDownloading = false
            isModelReady = true

            print("VoiceFox: LLM model download complete")
        } catch {
            isDownloading = false
            downloadError = error.localizedDescription
            print("VoiceFox: LLM model download failed: \(error)")
            throw error
        }
    }

    /// Preload the model into memory for fast first inference
    public func preload() async throws {
        guard loadedModel == nil else {
            // Already loaded
            return
        }

        guard isModelDownloaded() else {
            throw LLMError.modelNotDownloaded
        }

        isPreloading = true
        print("VoiceFox: Preloading LLM model...")

        do {
            let startTime = CFAbsoluteTimeGetCurrent()

            loadedModel = try await loadModelContainer(id: Self.modelId)

            let loadTime = CFAbsoluteTimeGetCurrent() - startTime
            print("VoiceFox: LLM model preloaded in \(String(format: "%.2f", loadTime))s")

            isPreloading = false
            isModelReady = true
        } catch {
            isPreloading = false
            print("VoiceFox: LLM preload failed: \(error)")
            throw error
        }
    }

    /// Get the loaded model container for inference
    public func getModel() async throws -> ModelContainer {
        if let model = loadedModel {
            return model
        }

        // Try to load if downloaded
        if isModelDownloaded() {
            try await preload()
            if let model = loadedModel {
                return model
            }
        }

        throw LLMError.modelNotDownloaded
    }

    /// Cancel ongoing download
    public func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        isDownloading = false
    }

    /// Unload the model from memory
    public func unload() {
        loadedModel = nil
    }
}

// MARK: - LLM Errors

public enum LLMError: Error, LocalizedError {
    case modelNotDownloaded
    case inferenceFailed(String)
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case .modelNotDownloaded:
            return "LLM model not downloaded"
        case .inferenceFailed(let message):
            return "LLM inference failed: \(message)"
        case .invalidResponse:
            return "Invalid response from LLM"
        }
    }
}
