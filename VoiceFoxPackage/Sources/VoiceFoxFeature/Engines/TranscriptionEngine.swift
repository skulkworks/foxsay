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

/// Available engine types
public enum EngineType: String, CaseIterable, Identifiable, Codable {
    case whisperKit = "whisperkit"
    case parakeet = "parakeet"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .whisperKit: return "WhisperKit"
        case .parakeet: return "Parakeet MLX"
        }
    }

    public var description: String {
        switch self {
        case .whisperKit:
            return "OpenAI Whisper via WhisperKit - Fast and accurate"
        case .parakeet:
            return "NVIDIA Parakeet TDT via MLX - Fastest for English"
        }
    }
}
