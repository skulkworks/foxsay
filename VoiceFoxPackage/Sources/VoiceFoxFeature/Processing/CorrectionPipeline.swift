import Foundation

/// Orchestrates the correction pipeline for transcribed text
@MainActor
public class CorrectionPipeline: ObservableObject {
    public static let shared = CorrectionPipeline()

    private let ruleCorrector = RuleBasedCorrector()

    /// Whether to apply dev corrections
    @Published public var devCorrectionEnabled = true

    /// Whether to use LLM for ambiguous cases
    @Published public var llmCorrectionEnabled = false

    private init() {}

    /// Process transcription result through the correction pipeline
    /// - Parameters:
    ///   - result: Original transcription result
    ///   - isDevApp: Whether the frontmost app is a developer app
    /// - Returns: Corrected transcription result
    public func process(
        _ result: TranscriptionResult,
        isDevApp: Bool
    ) async -> TranscriptionResult {
        // If not a dev app or dev correction disabled, return original
        guard isDevApp && devCorrectionEnabled else {
            return result
        }

        var correctedText = result.text

        // Step 1: Apply rule-based corrections
        correctedText = ruleCorrector.correct(correctedText)

        // Step 2: Optionally apply LLM correction for ambiguous cases
        if llmCorrectionEnabled {
            let llmCorrector = LLMCorrector.shared
            let isAvailable = await llmCorrector.available
            let shouldApply = await llmCorrector.shouldApplyCorrection(correctedText)
            if isAvailable && shouldApply {
                if let llmCorrected = try? await llmCorrector.correct(correctedText) {
                    correctedText = llmCorrected
                }
            }
        }

        // Step 3: Post-processing cleanup
        correctedText = postProcess(correctedText)

        // Return corrected result if text changed
        if correctedText != result.text {
            return result.withCorrection(correctedText)
        }

        return result
    }

    /// Post-processing cleanup
    private func postProcess(_ text: String) -> String {
        var result = text

        // Remove double spaces
        while result.contains("  ") {
            result = result.replacingOccurrences(of: "  ", with: " ")
        }

        // Trim whitespace
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove spaces before punctuation in code context
        result = result.replacingOccurrences(of: " .", with: ".")
        result = result.replacingOccurrences(of: " ,", with: ",")
        result = result.replacingOccurrences(of: " ;", with: ";")
        result = result.replacingOccurrences(of: " :", with: ":")

        // Remove spaces around operators in code context
        result = result.replacingOccurrences(of: " = ", with: "=")
        result = result.replacingOccurrences(of: " == ", with: "==")
        result = result.replacingOccurrences(of: " != ", with: "!=")
        result = result.replacingOccurrences(of: " -> ", with: "->")
        result = result.replacingOccurrences(of: " => ", with: "=>")

        return result
    }

    /// Get correction statistics
    public struct CorrectionStats {
        public let originalLength: Int
        public let correctedLength: Int
        public let rulesApplied: Int
        public let llmUsed: Bool
    }
}
