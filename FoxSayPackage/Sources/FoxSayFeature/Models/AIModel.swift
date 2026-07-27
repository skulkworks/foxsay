import Foundation

/// A local LLM available for AI-powered text transformation.
///
/// Models run on-device via MLX and are downloaded from HuggingFace on demand.
/// All entries in the registry use 4-bit quantized weights.
public struct AIModel: Identifiable, Equatable, Sendable {
    /// Stable identifier persisted in UserDefaults (do not change for existing models)
    public let id: String

    /// Display name shown in the UI
    public let name: String

    /// Short description shown on the model card
    public let description: String

    /// HuggingFace repo id ("org/model-name") used by mlx-swift-lm for download and caching
    public let huggingFaceId: String

    /// Approximate download size in bytes
    public let sizeBytes: Int

    /// Capability tags used for filtering and badges ("general", "coding", "creative")
    public let capabilities: [String]

    /// Whether the model gets a "Recommended" badge
    public let isRecommended: Bool

    public init(
        id: String,
        name: String,
        description: String,
        huggingFaceId: String,
        sizeBytes: Int,
        capabilities: [String] = ["general"],
        isRecommended: Bool = false
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.huggingFaceId = huggingFaceId
        self.sizeBytes = sizeBytes
        self.capabilities = capabilities
        self.isRecommended = isRecommended
    }

    /// Human-readable download size ("880 MB", "1.8 GB")
    public var formattedSize: String {
        let gigabytes = Double(sizeBytes) / 1_000_000_000
        if gigabytes >= 1 {
            return String(format: "%.1f GB", gigabytes)
        }
        return String(format: "%.0f MB", Double(sizeBytes) / 1_000_000)
    }

    /// Look up a model by its stable id
    public static func model(withId id: String) -> AIModel? {
        registry.first { $0.id == id }
    }

    /// All models available for download, newest generations first
    public static let registry: [AIModel] = [
        // MARK: - Current generation (2025-2026)

        AIModel(
            id: "qwen3.5-2b",
            name: "Qwen 3.5 2B",
            description: "Newest Qwen generation. Top quality for its size, 200+ languages.",
            huggingFaceId: "mlx-community/Qwen3.5-2B-4bit",
            sizeBytes: 1_750_000_000,
            capabilities: ["general"],
            isRecommended: true
        ),
        AIModel(
            id: "qwen3-4b-instruct-2507",
            name: "Qwen 3 4B Instruct (2507)",
            description: "Updated instruction model. Excellent quality, no reasoning overhead.",
            huggingFaceId: "mlx-community/Qwen3-4B-Instruct-2507-4bit",
            sizeBytes: 2_280_000_000,
            capabilities: ["general"]
        ),
        AIModel(
            id: "qwen3-1.7b",
            name: "Qwen 3 1.7B",
            description: "Fast current-generation model. Solid quality for quick corrections.",
            huggingFaceId: "mlx-community/Qwen3-1.7B-4bit",
            sizeBytes: 980_000_000,
            capabilities: ["general"]
        ),
        AIModel(
            id: "gemma-3-1b-instruct",
            name: "Gemma 3 1B (QAT)",
            description: "Google's smallest Gemma 3. Very fast, quantization-aware trained.",
            huggingFaceId: "mlx-community/gemma-3-1b-it-qat-4bit",
            sizeBytes: 770_000_000,
            capabilities: ["general"]
        ),
        AIModel(
            id: "gemma-4-e2b-instruct",
            name: "Gemma 4 E2B",
            description: "Google's newest edge model. Great quality, needs more memory.",
            huggingFaceId: "mlx-community/gemma-4-e2b-it-4bit",
            sizeBytes: 3_580_000_000,
            capabilities: ["general", "creative"]
        ),
        AIModel(
            id: "lfm2-1.2b",
            name: "LFM2 1.2B",
            description: "Liquid AI's on-device model. Extremely fast responses.",
            huggingFaceId: "mlx-community/LFM2-1.2B-4bit",
            sizeBytes: 660_000_000,
            capabilities: ["general"]
        ),
        AIModel(
            id: "llama-3.2-1b-instruct",
            name: "Llama 3.2 1B Instruct",
            description: "Meta's tiny model. Fastest Llama for quick corrections.",
            huggingFaceId: "mlx-community/Llama-3.2-1B-Instruct-4bit",
            sizeBytes: 710_000_000,
            capabilities: ["general"]
        ),

        // MARK: - Previous generation

        AIModel(
            id: "gemma-2-2b-instruct",
            name: "Gemma 2 2B Instruct",
            description: "Google's compact model. Fast and memory efficient.",
            huggingFaceId: "mlx-community/gemma-2-2b-it-4bit",
            sizeBytes: 1_490_000_000,
            capabilities: ["general"]
        ),
        AIModel(
            id: "qwen-coder-1.5b-instruct",
            name: "Qwen 2.5 Coder 1.5B",
            description: "Fast, instruction-following model. Best for precise text tasks.",
            huggingFaceId: "mlx-community/Qwen2.5-Coder-1.5B-Instruct-4bit",
            sizeBytes: 880_000_000,
            capabilities: ["coding"]
        ),
        AIModel(
            id: "qwen-1.5b-instruct",
            name: "Qwen 2.5 1.5B Instruct",
            description: "Fast, general-purpose model. Great for quick corrections.",
            huggingFaceId: "mlx-community/Qwen2.5-1.5B-Instruct-4bit",
            sizeBytes: 880_000_000,
            capabilities: ["general"]
        ),
        AIModel(
            id: "qwen-coder-3b-instruct",
            name: "Qwen 2.5 Coder 3B",
            description: "Larger coder model. Better instruction following.",
            huggingFaceId: "mlx-community/Qwen2.5-Coder-3B-Instruct-4bit",
            sizeBytes: 1_750_000_000,
            capabilities: ["coding"]
        ),
        AIModel(
            id: "qwen-3b-instruct",
            name: "Qwen 2.5 3B Instruct",
            description: "Balanced performance and quality for most use cases.",
            huggingFaceId: "mlx-community/Qwen2.5-3B-Instruct-4bit",
            sizeBytes: 1_750_000_000,
            capabilities: ["general"]
        ),
        AIModel(
            id: "llama-3.2-3b-instruct",
            name: "Llama 3.2 3B Instruct",
            description: "Meta's latest small model. Good general performance.",
            huggingFaceId: "mlx-community/Llama-3.2-3B-Instruct-4bit",
            sizeBytes: 1_820_000_000,
            capabilities: ["general"]
        ),
        AIModel(
            id: "phi-4-mini",
            name: "Phi 4 Mini (3.8B)",
            description: "Microsoft's latest small model. Excellent reasoning.",
            huggingFaceId: "mlx-community/phi-4-mini-instruct-4bit",
            sizeBytes: 2_180_000_000,
            capabilities: ["general", "coding"]
        ),
        AIModel(
            id: "mistral-nemo-12b",
            name: "Mistral NeMo 12B",
            description: "High quality model. Best results, requires more memory.",
            huggingFaceId: "mlx-community/Mistral-Nemo-Instruct-2407-4bit",
            sizeBytes: 6_910_000_000,
            capabilities: ["general", "creative"]
        ),
    ]
}
