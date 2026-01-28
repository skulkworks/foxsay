import Foundation
import MLXLLM
import MLXLMCommon

/// Manages AI models for text transformation
@MainActor
public class AIModelManager: ObservableObject {
    public static let shared = AIModelManager()

    // MARK: - UserDefaults Keys

    private static let downloadedModelsKey = "aiDownloadedModelIds"
    private static let selectedModelIdKey = "aiSelectedModelId"

    // MARK: - Published Properties

    /// IDs of downloaded models
    @Published public private(set) var downloadedModelIds: Set<String> = []

    /// Currently selected model ID
    @Published public var selectedModelId: String? {
        didSet {
            UserDefaults.standard.set(selectedModelId, forKey: Self.selectedModelIdKey)
            // Unload current model when selection changes
            if selectedModelId != oldValue {
                unload()
            }
        }
    }

    /// Download state
    @Published public private(set) var isDownloading = false
    @Published public private(set) var downloadProgress: Double = 0
    @Published public private(set) var downloadError: String?
    @Published public private(set) var downloadingModelId: String?

    /// Model loading state
    @Published public private(set) var isPreloading = false
    @Published public private(set) var isModelLoaded = false

    /// The currently loaded model container
    private var loadedModel: ModelContainer?
    private var loadedModelId: String?

    // MARK: - Computed Properties

    /// Get the available models from the registry
    public var availableModels: [AIModel] {
        AIModel.registry
    }

    /// Whether the selected model is ready (downloaded)
    public var isModelReady: Bool {
        guard let selectedId = selectedModelId else { return false }
        return downloadedModelIds.contains(selectedId)
    }

    /// Get the currently selected model
    public var selectedModel: AIModel? {
        guard let id = selectedModelId else { return nil }
        return AIModel.model(withId: id)
    }

    // MARK: - Initialization

    private init() {
        // Load downloaded model IDs from UserDefaults
        if let data = UserDefaults.standard.data(forKey: Self.downloadedModelsKey),
           let ids = try? JSONDecoder().decode(Set<String>.self, from: data) {
            downloadedModelIds = ids
        }

        // Load selected model ID
        selectedModelId = UserDefaults.standard.string(forKey: Self.selectedModelIdKey)

        // Validate downloaded models still exist on disk
        Task {
            await validateDownloadedModels()
            // Preload selected model if available
            if isModelReady {
                try? await preload()
            }
        }
    }

    // MARK: - Model Management

    /// Check if a specific model is downloaded
    public func isDownloaded(_ modelId: String) -> Bool {
        downloadedModelIds.contains(modelId)
    }

    /// Check if model files exist on disk
    public nonisolated func modelExistsOnDisk(_ model: AIModel) -> Bool {
        guard let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return false
        }

        // Model path derived from HuggingFace ID
        // mlx-swift-lm stores models in ~/Library/Caches/models/{org}/{model-name}/
        let parts = model.huggingFaceId.split(separator: "/")
        guard parts.count == 2 else { return false }

        let modelPath = cachesDir
            .appendingPathComponent("models")
            .appendingPathComponent(String(parts[0]))
            .appendingPathComponent(String(parts[1]))

        let configPath = modelPath.appendingPathComponent("config.json")
        return FileManager.default.fileExists(atPath: configPath.path)
    }

    /// Validate that downloaded models still exist on disk
    private func validateDownloadedModels() async {
        var validIds = Set<String>()
        for id in downloadedModelIds {
            if let model = AIModel.model(withId: id), modelExistsOnDisk(model) {
                validIds.insert(id)
            }
        }

        if validIds != downloadedModelIds {
            downloadedModelIds = validIds
            saveDownloadedModelIds()
        }
    }

    /// Download a model
    public func downloadModel(_ model: AIModel) async throws {
        guard !isDownloading else { return }
        guard !downloadedModelIds.contains(model.id) else { return }

        isDownloading = true
        downloadProgress = 0
        downloadError = nil
        downloadingModelId = model.id

        print("FoxSay: Starting AI model download: \(model.huggingFaceId)")

        do {
            // Simulated progress task for visual feedback
            let progressTask = Task {
                for i in 1...80 {
                    try Task.checkCancellation()
                    try await Task.sleep(for: .milliseconds(200))
                    await MainActor.run {
                        if self.downloadProgress < Double(i) / 100.0 {
                            self.downloadProgress = Double(i) / 100.0
                        }
                    }
                }
            }

            // Load the model - this downloads it if not cached
            let container = try await loadModelContainer(id: model.huggingFaceId) { progress in
                Task { @MainActor in
                    let fraction = progress.fractionCompleted
                    if fraction > self.downloadProgress {
                        self.downloadProgress = fraction
                    }
                }
            }

            progressTask.cancel()
            downloadProgress = 0.95

            // Store the loaded model if this is the selected model
            if selectedModelId == model.id {
                loadedModel = container
                loadedModelId = model.id
                isModelLoaded = true
            }

            downloadProgress = 1.0
            isDownloading = false
            downloadingModelId = nil

            // Mark as downloaded
            downloadedModelIds.insert(model.id)
            saveDownloadedModelIds()

            print("FoxSay: AI model download complete: \(model.name)")
        } catch {
            isDownloading = false
            downloadingModelId = nil
            downloadError = error.localizedDescription
            print("FoxSay: AI model download failed: \(error)")
            throw error
        }
    }

    /// Delete a downloaded model
    public func deleteModel(_ model: AIModel) {
        guard downloadedModelIds.contains(model.id) else { return }

        // Unload if this is the currently loaded model
        if loadedModelId == model.id {
            unload()
        }

        // Remove from disk
        if let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
            let parts = model.huggingFaceId.split(separator: "/")
            if parts.count == 2 {
                let modelPath = cachesDir
                    .appendingPathComponent("models")
                    .appendingPathComponent(String(parts[0]))
                    .appendingPathComponent(String(parts[1]))

                try? FileManager.default.removeItem(at: modelPath)
            }
        }

        // Update state
        downloadedModelIds.remove(model.id)
        saveDownloadedModelIds()

        // Clear selection if this was the selected model
        if selectedModelId == model.id {
            selectedModelId = nil
        }

        print("FoxSay: AI model deleted: \(model.name)")
    }

    /// Select a model
    public func selectModel(_ model: AIModel) {
        selectedModelId = model.id
    }

    /// Preload the selected model into memory
    public func preload() async throws {
        guard loadedModel == nil else { return }
        guard let model = selectedModel else {
            throw AIModelError.noModelSelected
        }
        guard downloadedModelIds.contains(model.id) else {
            throw AIModelError.modelNotDownloaded
        }

        isPreloading = true
        print("FoxSay: Preloading AI model: \(model.name)")

        do {
            let startTime = CFAbsoluteTimeGetCurrent()
            loadedModel = try await loadModelContainer(id: model.huggingFaceId)
            loadedModelId = model.id
            let loadTime = CFAbsoluteTimeGetCurrent() - startTime

            print("FoxSay: AI model preloaded in \(String(format: "%.2f", loadTime))s")

            isPreloading = false
            isModelLoaded = true
        } catch {
            isPreloading = false
            print("FoxSay: AI model preload failed: \(error)")
            throw error
        }
    }

    /// Get the loaded model container for inference
    public func getModel() async throws -> ModelContainer {
        if let model = loadedModel, loadedModelId == selectedModelId {
            return model
        }

        // Try to load if downloaded
        if isModelReady {
            try await preload()
            if let model = loadedModel {
                return model
            }
        }

        throw AIModelError.modelNotDownloaded
    }

    /// Unload the model from memory
    public func unload() {
        loadedModel = nil
        loadedModelId = nil
        isModelLoaded = false
    }

    /// Deactivate the current model (unload but keep downloaded)
    public func deactivateModel() {
        unload()
        selectedModelId = nil
        print("FoxSay: AI model deactivated")
    }

    /// Cancel ongoing download
    public func cancelDownload() {
        // Note: The actual download cancellation would need task management
        isDownloading = false
        downloadingModelId = nil
        downloadProgress = 0
    }

    // MARK: - Persistence

    private func saveDownloadedModelIds() {
        if let data = try? JSONEncoder().encode(downloadedModelIds) {
            UserDefaults.standard.set(data, forKey: Self.downloadedModelsKey)
        }
    }
}

// MARK: - Errors

public enum AIModelError: Error, LocalizedError {
    case noModelSelected
    case modelNotDownloaded
    case inferenceFailed(String)
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case .noModelSelected:
            return "No AI model selected"
        case .modelNotDownloaded:
            return "AI model not downloaded"
        case .inferenceFailed(let message):
            return "AI inference failed: \(message)"
        case .invalidResponse:
            return "Invalid response from AI model"
        }
    }
}
