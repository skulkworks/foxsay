import Foundation
import MLXLLM
import MLXLMCommon

/// Manages the LLM model for text correction
@MainActor
public class LLMModelManager: ObservableObject {
    public static let shared = LLMModelManager()

    /// The HuggingFace model ID for the code correction model
    public static nonisolated let modelId = "mlx-community/Qwen2.5-Coder-1.5B-Instruct-4bit"

    /// Approximate model size for display
    public static let modelSizeMB = 900

    /// Default system prompt for LLM correction
    /// Use {input} as placeholder for the text to correct
    public static let defaultPrompt = """
        Convert spoken punctuation to symbols. Be minimal - output only the converted text.
        IMPORTANT: Preserve any existing markdown formatting (*, **, `) exactly as-is.

        Rules: hash=#, dash=-, dot=., equals=, colon=:, semicolon=;
        open paren=(, close paren=), open bracket=[, close bracket=]
        greater than=>, less than=<, plus=+
        "dash dash"=--, "equals equals"==, "not equals"=!=, "plus equals"=+=

        Examples:
        "hash hello" -> # hello
        "hash hash hello" -> ## hello
        "const x equals 5" -> const x = 5
        "if x equals equals y" -> if x == y
        "function hello open paren close paren" -> function hello()
        "hello world" -> hello world
        "text *with italic* here" -> text *with italic* here
        "this is **bold** text" -> this is **bold** text
        "use `code` inline" -> use `code` inline

        Input: {input}
        Output:
        """

    /// UserDefaults key for custom prompt
    private static let customPromptKey = "llmCustomPrompt"

    /// The current prompt (custom or default)
    @Published public var customPrompt: String {
        didSet {
            UserDefaults.standard.set(customPrompt, forKey: Self.customPromptKey)
        }
    }

    /// Whether a custom prompt is being used
    public var isUsingCustomPrompt: Bool {
        customPrompt != Self.defaultPrompt
    }

    @Published public private(set) var isDownloading = false
    @Published public private(set) var downloadProgress: Double = 0
    @Published public private(set) var isModelReady = false
    @Published public private(set) var downloadError: String?
    @Published public private(set) var isPreloading = false
    @Published public private(set) var isLoaded = false

    /// Whether LLM correction is enabled (reads from UserDefaults)
    public var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: "llmCorrectionEnabled")
    }

    private var loadedModel: ModelContainer?
    private var downloadTask: Task<Void, Error>?

    private init() {
        // Load custom prompt from UserDefaults or use default
        self.customPrompt = UserDefaults.standard.string(forKey: Self.customPromptKey) ?? Self.defaultPrompt

        print("VoiceFox: LLMModelManager initializing...")

        // Check if model is already downloaded and preload if LLM correction is enabled
        Task {
            await checkModelStatus()
            let llmEnabled = UserDefaults.standard.bool(forKey: "llmCorrectionEnabled")
            if isModelReady && llmEnabled {
                print("VoiceFox: LLM model already downloaded and enabled, preloading...")
                try? await preload()
            }
        }
    }

    /// Reset the prompt to default
    public func resetPromptToDefault() {
        customPrompt = Self.defaultPrompt
    }

    /// Build the final prompt with input text substituted
    public func buildPrompt(for inputText: String) -> String {
        customPrompt.replacingOccurrences(of: "{input}", with: inputText)
    }

    /// Check if the model files exist locally
    public func checkModelStatus() async {
        let downloaded = isModelDownloaded()
        isModelReady = downloaded
        print("VoiceFox: LLM model status check - downloaded: \(downloaded), ready: \(isModelReady)")
    }

    /// Check if model is downloaded by looking for model files
    public nonisolated func isModelDownloaded() -> Bool {
        // mlx-swift-lm stores models in ~/Library/Caches/models/{org}/{model-name}/
        // e.g., ~/Library/Caches/models/mlx-community/Qwen2.5-Coder-0.5B-Instruct-4bit/

        guard let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return false
        }

        // Model path derived from model ID
        let modelName = Self.modelId.replacingOccurrences(of: "mlx-community/", with: "")
        let modelPath = cachesDir
            .appendingPathComponent("models")
            .appendingPathComponent("mlx-community")
            .appendingPathComponent(modelName)

        // Check for config.json as indicator of complete model download
        let configPath = modelPath.appendingPathComponent("config.json")
        let modelExists = FileManager.default.fileExists(atPath: configPath.path)

        if modelExists {
            print("VoiceFox: LLM model found at \(modelPath.path)")
        }

        return modelExists
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
            isLoaded = true

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
            isLoaded = true
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
        isLoaded = false
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
