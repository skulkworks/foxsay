import Foundation

/// Information about a transcription model for display
public struct TranscriptionModelInfo: Identifiable, Sendable {
    public let id: String
    public let type: ModelType
    public let displayName: String
    public let version: String
    public let description: String
    public let accuracyRating: Int  // 1-5 dots
    public let speedRating: Int     // 1-5 dots
    public let sizeBytes: Int64
    public let languageSupport: LanguageSupport
    public let badges: [ModelBadge]

    public enum LanguageSupport: String, Sendable {
        case englishOnly = "English"
        case multilingual = "25 Languages"
        case japanese = "Japanese"
    }

    public enum ModelBadge: String, CaseIterable, Sendable {
        case recommended = "Recommended"
        case fastest = "Fastest"
        case mostAccurate = "Most Accurate"
        case multilingual = "Multilingual"
        case compact = "Compact"
    }

    /// Formatted size string (e.g., "450 MB")
    public var formattedSize: String {
        let mb = Double(sizeBytes) / 1_000_000
        if mb >= 1000 {
            return String(format: "%.1f GB", mb / 1000)
        }
        return String(format: "%.0f MB", mb)
    }
}

/// Registry of all available transcription models
public struct ModelRegistry {
    /// All available models
    public static let allModels: [TranscriptionModelInfo] = [
        // Parakeet V2 - Best for English
        TranscriptionModelInfo(
            id: "parakeet-v2",
            type: .parakeetV2,
            displayName: "Parakeet V2",
            version: "0.6B",
            description: "Optimized for English with highest recall. Best choice for English-only use cases.",
            accuracyRating: 5,
            speedRating: 5,
            sizeBytes: 450_000_000,
            languageSupport: .englishOnly,
            badges: [.recommended, .fastest]
        ),

        // Parakeet V3 - Multilingual
        TranscriptionModelInfo(
            id: "parakeet-v3",
            type: .parakeetV3,
            displayName: "Parakeet V3",
            version: "0.6B",
            description: "Supports 25 European languages with excellent accuracy.",
            accuracyRating: 5,
            speedRating: 4,
            sizeBytes: 480_000_000,
            languageSupport: .multilingual,
            badges: [.multilingual, .mostAccurate]
        ),

        // Parakeet TDT-CTC 110M - Smallest Parakeet, fused preprocessor+encoder
        TranscriptionModelInfo(
            id: "parakeet-tdt-ctc-110m",
            type: .parakeetTdtCtc110m,
            displayName: "Parakeet TDT-CTC 110M",
            version: "0.11B",
            description: "Smallest and fastest Parakeet. English-only, great for quick dictation.",
            accuracyRating: 4,
            speedRating: 5,
            sizeBytes: 230_000_000,
            languageSupport: .englishOnly,
            badges: [.compact, .fastest]
        ),

        // Parakeet Japanese - Japanese-only
        TranscriptionModelInfo(
            id: "parakeet-ja",
            type: .parakeetJa,
            displayName: "Parakeet Japanese",
            version: "0.6B",
            description: "Tuned specifically for Japanese speech, with higher accuracy than the multilingual model.",
            accuracyRating: 5,
            speedRating: 4,
            sizeBytes: 620_000_000,
            languageSupport: .japanese,
            badges: [.mostAccurate]
        ),

        // Whisper Tiny - Fastest, smallest
        TranscriptionModelInfo(
            id: "whisper-tiny",
            type: .whisperTiny,
            displayName: "Whisper Tiny",
            version: "tiny",
            description: "Fastest Whisper model. Good for quick dictation with decent accuracy.",
            accuracyRating: 2,
            speedRating: 5,
            sizeBytes: 39_000_000,
            languageSupport: .multilingual,
            badges: [.compact, .fastest]
        ),

        // Whisper Base - Good balance
        TranscriptionModelInfo(
            id: "whisper-base",
            type: .whisperBase,
            displayName: "Whisper Base",
            version: "base",
            description: "Balanced Whisper model. Fast and reliable for most use cases.",
            accuracyRating: 3,
            speedRating: 4,
            sizeBytes: 74_000_000,
            languageSupport: .multilingual,
            badges: [.compact]
        ),

        // Whisper Small - Better accuracy
        TranscriptionModelInfo(
            id: "whisper-small",
            type: .whisperSmall,
            displayName: "Whisper Small",
            version: "small",
            description: "Higher accuracy Whisper model. Good balance of speed and quality.",
            accuracyRating: 4,
            speedRating: 3,
            sizeBytes: 244_000_000,
            languageSupport: .multilingual,
            badges: [.multilingual]
        ),

        // Whisper Large V3 Turbo - Best accuracy, optimized
        TranscriptionModelInfo(
            id: "whisper-large-turbo",
            type: .whisperLargeTurbo,
            displayName: "Whisper Large Turbo",
            version: "large-v3-turbo",
            description: "Best Whisper accuracy with speed optimizations. Excellent for complex audio.",
            accuracyRating: 5,
            speedRating: 2,
            sizeBytes: 809_000_000,
            languageSupport: .multilingual,
            badges: [.mostAccurate, .multilingual]
        ),
    ]

    /// Get model info by type
    public static func info(for type: ModelType) -> TranscriptionModelInfo? {
        // Handle legacy whisperKit alias -> whisperBase
        let lookupType = type == .whisperKit ? .whisperBase : type
        return allModels.first { $0.type == lookupType }
    }

    /// Get recommended model
    public static var recommended: TranscriptionModelInfo {
        allModels.first { $0.badges.contains(.recommended) } ?? allModels[0]
    }

    /// Filter models by criteria
    public static func filter(
        languageSupport: TranscriptionModelInfo.LanguageSupport? = nil,
        badges: [TranscriptionModelInfo.ModelBadge] = []
    ) -> [TranscriptionModelInfo] {
        var result = allModels

        if let language = languageSupport {
            result = result.filter { $0.languageSupport == language }
        }

        if !badges.isEmpty {
            result = result.filter { model in
                badges.allSatisfy { model.badges.contains($0) }
            }
        }

        return result
    }
}
