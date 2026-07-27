import Foundation

/// Rich metadata for a speech-to-text model, used by the Speech Models settings UI
public struct TranscriptionModelInfo: Identifiable, Equatable, Sendable {
    /// Language coverage of a model
    public enum LanguageSupport: String, Sendable {
        case englishOnly = "English"
        case multilingual = "25 Languages"
    }

    /// Badges displayed on the model card
    public enum ModelBadge: String, Sendable {
        case recommended = "Recommended"
        case fastest = "Fastest"
        case mostAccurate = "Most Accurate"
        case multilingual = "Multilingual"
        case compact = "Compact"
    }

    /// The engine/model this metadata describes
    public let type: ModelType

    /// Display name shown in the UI
    public let displayName: String

    /// Short description shown on the model card
    public let description: String

    /// Badges displayed under the model name
    public let badges: [ModelBadge]

    /// Relative accuracy, 1-5
    public let accuracyRating: Int

    /// Relative speed, 1-5
    public let speedRating: Int

    /// Approximate download size in bytes
    public let sizeBytes: Int64

    /// Language coverage
    public let languageSupport: LanguageSupport

    public var id: String { type.rawValue }

    /// Human-readable download size ("~450 MB")
    public var formattedSize: String {
        let megabytes = Double(sizeBytes) / 1_000_000
        if megabytes >= 1000 {
            return String(format: "~%.1f GB", megabytes / 1000)
        }
        return String(format: "~%.0f MB", megabytes)
    }
}

/// Registry of all transcription models selectable in the UI
public enum ModelRegistry {
    /// All models shown in the Speech Models settings
    public static let allModels: [TranscriptionModelInfo] = [
        TranscriptionModelInfo(
            type: .parakeetV2,
            displayName: "Parakeet V2",
            description: "Optimized for English with highest recall. Best choice for English-only use cases.",
            badges: [.recommended, .fastest],
            accuracyRating: 5,
            speedRating: 5,
            sizeBytes: 450_000_000,
            languageSupport: .englishOnly
        ),
        TranscriptionModelInfo(
            type: .parakeetV3,
            displayName: "Parakeet V3",
            description: "Supports 25 European languages with excellent accuracy.",
            badges: [.multilingual],
            accuracyRating: 5,
            speedRating: 4,
            sizeBytes: 480_000_000,
            languageSupport: .multilingual
        ),
        TranscriptionModelInfo(
            type: .whisperTiny,
            displayName: "Whisper Tiny",
            description: "Fastest Whisper model. Good for quick dictation with decent accuracy.",
            badges: [.compact],
            accuracyRating: 2,
            speedRating: 5,
            sizeBytes: 39_000_000,
            languageSupport: .multilingual
        ),
        TranscriptionModelInfo(
            type: .whisperBase,
            displayName: "Whisper Base",
            description: "Balanced Whisper model. Fast and reliable for most use cases.",
            badges: [.compact],
            accuracyRating: 3,
            speedRating: 4,
            sizeBytes: 74_000_000,
            languageSupport: .multilingual
        ),
        TranscriptionModelInfo(
            type: .whisperSmall,
            displayName: "Whisper Small",
            description: "Higher accuracy Whisper model. Good balance of speed and quality.",
            badges: [],
            accuracyRating: 4,
            speedRating: 3,
            sizeBytes: 244_000_000,
            languageSupport: .multilingual
        ),
        TranscriptionModelInfo(
            type: .whisperLargeTurbo,
            displayName: "Whisper Large Turbo",
            description: "Best Whisper accuracy with speed optimizations. Excellent for complex audio.",
            badges: [.mostAccurate],
            accuracyRating: 5,
            speedRating: 2,
            sizeBytes: 809_000_000,
            languageSupport: .multilingual
        ),
    ]

    /// Look up metadata for a model type.
    /// The legacy `.whisperKit` alias maps to Whisper Base.
    public static func info(for type: ModelType) -> TranscriptionModelInfo? {
        let effectiveType: ModelType = type == .whisperKit ? .whisperBase : type
        return allModels.first { $0.type == effectiveType }
    }
}
