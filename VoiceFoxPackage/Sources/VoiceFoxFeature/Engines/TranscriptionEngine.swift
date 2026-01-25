import Foundation

/// Protocol defining the interface for speech-to-text engines
public protocol TranscriptionEngine: Sendable {
    /// Display name of the engine
    var name: String { get }

    /// Unique identifier for the engine
    var identifier: String { get }

    /// Whether the model is downloaded and ready to use
    var isModelDownloaded: Bool { get async }

    /// Current download progress (0.0 - 1.0)
    var downloadProgress: Double { get async }

    /// Size of the model in bytes (for display purposes)
    var modelSize: Int64 { get }

    /// Download the model files
    func downloadModel() async throws

    /// Transcribe audio buffer to text
    /// - Parameter audioBuffer: Float array of audio samples at 16kHz mono
    /// - Returns: Transcription result
    func transcribe(audioBuffer: [Float]) async throws -> TranscriptionResult

    /// Cancel any ongoing transcription
    func cancel() async

    /// Preload the model into memory for faster first transcription
    func preload() async throws
}

/// Errors that can occur during transcription
public enum TranscriptionError: LocalizedError {
    case modelNotDownloaded
    case transcriptionFailed(String)
    case cancelled
    case invalidAudio
    case engineNotAvailable

    public var errorDescription: String? {
        switch self {
        case .modelNotDownloaded:
            return "Model not downloaded"
        case .transcriptionFailed(let reason):
            return "Transcription failed: \(reason)"
        case .cancelled:
            return "Transcription cancelled"
        case .invalidAudio:
            return "Invalid audio data"
        case .engineNotAvailable:
            return "Engine not available"
        }
    }
}

/// Available model types
public enum ModelType: String, CaseIterable, Identifiable, Codable, Sendable {
    // Whisper variants via WhisperKit
    case whisperTiny = "whisper-tiny"
    case whisperBase = "whisper-base"
    case whisperSmall = "whisper-small"
    case whisperLargeTurbo = "whisper-large-turbo"

    // Parakeet variants via FluidAudio
    case parakeetV2 = "parakeet"  // Keep raw value for backward compatibility
    case parakeetV3 = "parakeet-v3"

    // Legacy alias
    case whisperKit = "whisperkit"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .whisperTiny: return "Whisper Tiny"
        case .whisperBase, .whisperKit: return "Whisper Base"
        case .whisperSmall: return "Whisper Small"
        case .whisperLargeTurbo: return "Whisper Large Turbo"
        case .parakeetV2: return "Parakeet V2"
        case .parakeetV3: return "Parakeet V3"
        }
    }

    public var shortName: String {
        switch self {
        case .whisperTiny: return "Tiny"
        case .whisperBase, .whisperKit: return "Base"
        case .whisperSmall: return "Small"
        case .whisperLargeTurbo: return "Turbo"
        case .parakeetV2: return "Parakeet V2"
        case .parakeetV3: return "Parakeet V3"
        }
    }

    public var description: String {
        switch self {
        case .whisperTiny:
            return "Fastest, good for quick dictation (~39MB)"
        case .whisperBase, .whisperKit:
            return "Fast and reliable (~74MB)"
        case .whisperSmall:
            return "Good balance of speed and accuracy (~244MB)"
        case .whisperLargeTurbo:
            return "Best accuracy, optimized for speed (~809MB)"
        case .parakeetV2:
            return "English-only, highest recall (~450MB)"
        case .parakeetV3:
            return "Multilingual, 25 languages (~480MB)"
        }
    }

    public var isMultilingual: Bool {
        switch self {
        case .whisperTiny, .whisperBase, .whisperKit, .whisperSmall, .whisperLargeTurbo, .parakeetV3:
            return true
        case .parakeetV2:
            return false
        }
    }

    /// WhisperKit model name for this type
    public var whisperKitModelName: String? {
        switch self {
        case .whisperTiny: return "tiny"
        case .whisperBase, .whisperKit: return "base"
        case .whisperSmall: return "small"
        case .whisperLargeTurbo: return "large-v3-turbo"
        default: return nil
        }
    }

    /// Whether this is a Whisper-based model
    public var isWhisperModel: Bool {
        whisperKitModelName != nil
    }
}

/// Type alias for backward compatibility
public typealias EngineType = ModelType
