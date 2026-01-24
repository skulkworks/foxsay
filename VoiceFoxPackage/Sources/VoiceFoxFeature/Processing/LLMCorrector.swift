import Foundation
import MLXLLM
import MLXLMCommon

/// LLM-based correction for ambiguous transcriptions
/// Uses local MLX models for context-aware spoken-to-code corrections
public actor LLMCorrector {
    public static let shared = LLMCorrector()

    /// Maximum tokens to generate for corrections
    private let maxTokens = 100

    private init() {}

    /// Check if LLM correction is available
    public var available: Bool {
        get async {
            await LLMModelManager.shared.isModelReady
        }
    }

    /// Correct text using LLM for context-aware spoken-to-code improvements
    /// - Parameters:
    ///   - text: The text to correct
    ///   - context: Optional context about what the user is doing
    /// - Returns: Corrected text
    public func correct(_ text: String, context: String? = nil) async throws -> String {
        let manager = await LLMModelManager.shared
        let container = try await manager.getModel()

        // Build the prompt for spoken-to-code correction
        let promptText = buildPrompt(text: text, context: context)

        let startTime = CFAbsoluteTimeGetCurrent()

        // Prepare the input for the model
        let userInput = UserInput(prompt: promptText)
        let input = try await container.prepare(input: userInput)

        // Generate with low temperature for deterministic output
        let parameters = GenerateParameters(
            maxTokens: maxTokens,
            temperature: 0.1
        )

        // Collect the generated text
        var generatedText = ""
        let stream = try await container.generate(input: input, parameters: parameters)

        for await generation in stream {
            switch generation {
            case .chunk(let chunk):
                generatedText += chunk
            case .info:
                break
            case .toolCall:
                break
            }
        }

        let processingTime = CFAbsoluteTimeGetCurrent() - startTime
        print("VoiceFox: LLM correction took \(String(format: "%.0f", processingTime * 1000))ms")

        // Clean up the response
        let corrected = cleanResponse(generatedText, originalText: text)

        return corrected
    }

    /// Build the prompt for spoken-to-code correction
    private func buildPrompt(text: String, context: String?) -> String {
        var prompt = """
        Convert this spoken developer text to code. Output ONLY the corrected text, nothing else.
        Rules:
        - Fix speech-to-code errors (dash dash -> --, equals equals -> ==)
        - Use proper code syntax and casing
        - Keep it concise
        - Do not add explanations or comments
        """

        if let context = context {
            prompt += "\nContext: \(context)"
        }

        prompt += "\n\nInput: \(text)\nOutput:"

        return prompt
    }

    /// Clean up the LLM response to extract just the corrected text
    private func cleanResponse(_ response: String, originalText: String) -> String {
        var cleaned = response

        // Remove common prefixes the model might add
        let prefixesToRemove = [
            "Output:",
            "Corrected:",
            "Result:",
            "Here is the corrected text:",
            "The corrected text is:",
        ]

        for prefix in prefixesToRemove {
            if cleaned.lowercased().hasPrefix(prefix.lowercased()) {
                cleaned = String(cleaned.dropFirst(prefix.count))
            }
        }

        // Remove quotes if the model wrapped the output
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        if (cleaned.hasPrefix("\"") && cleaned.hasSuffix("\"")) ||
           (cleaned.hasPrefix("'") && cleaned.hasSuffix("'")) ||
           (cleaned.hasPrefix("`") && cleaned.hasSuffix("`")) {
            cleaned = String(cleaned.dropFirst().dropLast())
        }

        // Remove markdown code blocks if present
        if cleaned.hasPrefix("```") {
            if let endIndex = cleaned.range(of: "\n") {
                cleaned = String(cleaned[endIndex.upperBound...])
            }
            if cleaned.hasSuffix("```") {
                cleaned = String(cleaned.dropLast(3))
            }
        }

        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        // If the response is empty or much longer than input, return original
        if cleaned.isEmpty || cleaned.count > originalText.count * 3 {
            return originalText
        }

        return cleaned
    }

    /// Determine if LLM correction should be applied based on heuristics
    /// - Parameter text: The transcribed text
    /// - Returns: Whether the text would benefit from LLM correction
    public func shouldApplyCorrection(_ text: String) -> Bool {
        // Skip very short or very long texts
        let wordCount = text.split(separator: " ").count
        if wordCount < 2 || wordCount > 50 {
            return false
        }

        // Heuristics for when LLM correction is likely beneficial:

        // 1. Contains spoken programming constructs that need conversion
        let spokenPatterns = [
            "dash dash",
            "equals equals",
            "not equals",
            "greater than",
            "less than",
            "open paren",
            "close paren",
            "open bracket",
            "close bracket",
            "open brace",
            "close brace",
            "arrow",
            "fat arrow",
            "pipe pipe",
            "ampersand ampersand",
            "and and",
            "or or",
        ]

        let lowercased = text.lowercased()
        for pattern in spokenPatterns {
            if lowercased.contains(pattern) {
                return true
            }
        }

        // 2. Contains words that are likely code but spelled out
        let codeIndicators = [
            "function", "const", "let", "var",
            "import", "export", "return",
            "async", "await", "class",
            "git", "npm", "pip", "cargo",
            "sudo", "chmod", "mkdir",
        ]

        for indicator in codeIndicators {
            if lowercased.contains(indicator) {
                return true
            }
        }

        // 3. Text contains unusual capitalization that might need fixing
        // (like "iphone" that should be "iPhone")
        let camelCaseWords = ["iphone", "javascript", "typescript", "github", "gitlab"]
        for word in camelCaseWords {
            if lowercased.contains(word) && !text.contains(word) {
                // Found a word that might need proper casing
                return true
            }
        }

        return false
    }
}
