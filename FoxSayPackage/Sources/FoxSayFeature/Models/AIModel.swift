import Foundation

/// Represents an AI model that can be downloaded and used for text transformation
public struct AIModel: Codable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let description: String
    public let huggingFaceId: String
    public let sizeBytes: Int64
    public let capabilities: [String]
    public let isRecommended: Bool

    public init(
        id: String,
        name: String,
        description: String,
        huggingFaceId: String,
        sizeBytes: Int64,
        capabilities: [String],
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

    /// Format the size for display (e.g., "900 MB", "1.8 GB")
    public var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: sizeBytes)
    }

    /// Short name for status display (e.g., "Llama 3B", "Qwen 1.5B")
    public var shortName: String {
        // Remove common suffixes and simplify
        var short = name
            .replacingOccurrences(of: " Instruct", with: "")
            .replacingOccurrences(of: " Mini", with: "")
            .replacingOccurrences(of: "2.5 ", with: "")
            .replacingOccurrences(of: "3.2 ", with: "")

        // Truncate if still too long
        if short.count > 15 {
            short = String(short.prefix(15))
        }
        return short
    }

    /// Registry of available AI models for text transformation
    public static let registry: [AIModel] = [
        // Recommended. Chosen by benchmarking the vocal-corrections prompt across the
        // sub-2GB models: this one applies corrections correctly while leaving text that
        // contains no correction completely untouched, which is the failure mode that
        // matters most for dictation.
        AIModel(
            id: "qwen-1.5b-instruct",
            name: "Qwen 2.5 1.5B Instruct",
            description: "Fast, general-purpose model. Great for quick corrections.",
            huggingFaceId: "mlx-community/Qwen2.5-1.5B-Instruct-4bit",
            sizeBytes: 900_000_000,
            capabilities: ["general", "coding"],
            isRecommended: true
        ),

        // Fast models (< 1.5GB)
        AIModel(
            id: "qwen3-1.7b",
            name: "Qwen3 1.7B",
            description: "Alibaba's latest small model. Fast, with excellent instruction following.",
            huggingFaceId: "Qwen/Qwen3-1.7B-MLX-4bit",
            sizeBytes: 914_000_000,
            capabilities: ["general", "coding"]
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
        AIModel(
            id: "gemma-3-1b-instruct",
            name: "Gemma 3 1B Instruct",
            description: "Google's latest compact model. Tiny but slower inference.",
            huggingFaceId: "mlx-community/gemma-3-1b-it-4bit",
            sizeBytes: 733_000_000,
            capabilities: ["general"]
        ),
        AIModel(
            id: "gemma-2-2b-instruct",
            name: "Gemma 2 2B Instruct",
            description: "Google's compact model. Fast and memory efficient.",
            huggingFaceId: "mlx-community/gemma-2-2b-it-4bit",
            sizeBytes: 1_400_000_000,
            capabilities: ["general"]
        ),
        AIModel(
            id: "qwen-coder-1.5b-instruct",
            name: "Qwen 2.5 Coder 1.5B",
            description: "Fast, instruction-following model. Best for precise text tasks.",
            huggingFaceId: "mlx-community/Qwen2.5-Coder-1.5B-Instruct-4bit",
            sizeBytes: 900_000_000,
            capabilities: ["coding", "general"]
        ),

        // Balanced models (1.5-2.5GB)
        AIModel(
            id: "qwen3.5-2b",
            name: "Qwen3.5 2B",
            description: "Newest Qwen generation. Top quality for its size, 200+ languages.",
            huggingFaceId: "mlx-community/Qwen3.5-2B-4bit",
            sizeBytes: 1_750_000_000,
            capabilities: ["general", "coding", "creative"]
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
            id: "qwen3-4b-instruct",
            name: "Qwen3 4B Instruct",
            description: "Alibaba's latest 4B model. Best small model quality with dual-mode reasoning.",
            huggingFaceId: "mlx-community/Qwen3-4B-Instruct-2507-4bit",
            sizeBytes: 2_260_000_000,
            capabilities: ["general", "coding", "creative"]
        ),
        AIModel(
            id: "qwen-coder-3b-instruct",
            name: "Qwen 2.5 Coder 3B",
            description: "Larger coder model. Better instruction following.",
            huggingFaceId: "mlx-community/Qwen2.5-Coder-3B-Instruct-4bit",
            sizeBytes: 1_800_000_000,
            capabilities: ["coding", "general", "creative"]
        ),
        AIModel(
            id: "qwen-3b-instruct",
            name: "Qwen 2.5 3B Instruct",
            description: "Balanced performance and quality for most use cases.",
            huggingFaceId: "mlx-community/Qwen2.5-3B-Instruct-4bit",
            sizeBytes: 1_800_000_000,
            capabilities: ["general", "coding", "creative"]
        ),
        AIModel(
            id: "llama-3.2-3b-instruct",
            name: "Llama 3.2 3B Instruct",
            description: "Meta's latest small model. Good general performance.",
            huggingFaceId: "mlx-community/Llama-3.2-3B-Instruct-4bit",
            sizeBytes: 1_900_000_000,
            capabilities: ["general", "coding"]
        ),
        AIModel(
            id: "phi-4-mini",
            name: "Phi 4 Mini (3.8B)",
            description: "Microsoft's latest small model. Excellent reasoning.",
            huggingFaceId: "mlx-community/phi-4-mini-instruct-4bit",
            sizeBytes: 2_300_000_000,
            capabilities: ["general", "coding", "creative"]
        ),

        // Larger models (> 2.5GB) - Better quality, slower
        AIModel(
            id: "mistral-nemo-12b",
            name: "Mistral NeMo 12B",
            description: "High quality model. Best results, requires more memory.",
            huggingFaceId: "mlx-community/Mistral-Nemo-Instruct-2407-4bit",
            sizeBytes: 7_000_000_000,
            capabilities: ["general", "coding", "creative"]
        ),
    ]

    /// Get an AI model by its ID
    public static func model(withId id: String) -> AIModel? {
        registry.first { $0.id == id }
    }
}
