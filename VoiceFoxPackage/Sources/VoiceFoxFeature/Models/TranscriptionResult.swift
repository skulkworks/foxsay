import Foundation

/// Result of a transcription operation
public struct TranscriptionResult: Sendable, Equatable {
    /// The transcribed text
    public let text: String

    /// Confidence score (0.0 - 1.0) if available
    public let confidence: Double?

    /// Time taken to transcribe in seconds
    public let processingTime: TimeInterval

    /// Whether the result was corrected for developer context
    public let wasDevCorrected: Bool

    /// Original text before dev corrections (if applicable)
    public let originalText: String?

    public init(
        text: String,
        confidence: Double? = nil,
        processingTime: TimeInterval = 0,
        wasDevCorrected: Bool = false,
        originalText: String? = nil
    ) {
        self.text = text
        self.confidence = confidence
        self.processingTime = processingTime
        self.wasDevCorrected = wasDevCorrected
        self.originalText = originalText
    }

    /// Create a corrected version of this result
    public func withCorrection(_ correctedText: String) -> TranscriptionResult {
        TranscriptionResult(
            text: correctedText,
            confidence: confidence,
            processingTime: processingTime,
            wasDevCorrected: true,
            originalText: text
        )
    }
}
