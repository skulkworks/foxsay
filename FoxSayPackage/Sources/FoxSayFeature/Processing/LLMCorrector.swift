import Foundation
import MLXLLM
import MLXLMCommon
import os.log

private let llmLog = OSLog(subsystem: "com.foxsay", category: "LLM-DEBUG")

/// LLM-based text transformation using local MLX models
public actor LLMCorrector {
    public static let shared = LLMCorrector()

    /// Maximum tokens to generate
    private let maxTokens = 200

    private init() {}

    /// Check if LLM is available (model downloaded and ready)
    public var available: Bool {
        get async {
            await AIModelManager.shared.isModelReady
        }
    }

    /// Transform text using the AI model with the given prompt
    /// - Parameters:
    ///   - text: The text to transform
    ///   - prompt: The prompt template (should contain {input} placeholder)
    /// - Returns: Transformed text
    public func correct(_ text: String, prompt: String) async throws -> String {
        let manager = await AIModelManager.shared
        let container = try await manager.getModel()

        // Build the prompt with input substituted
        let promptText = prompt.replacingOccurrences(of: "{input}", with: text)

        os_log(.info, log: llmLog, ">>> PRE-LLM: %{public}@", text)

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

    /// Clean up the LLM response to extract just the corrected text
    private func cleanResponse(_ response: String, originalText: String) -> String {
        var cleaned = response

        // Stop at common end tokens (Gemma, Llama, Qwen, etc.)
        let endTokens = ["<end_of_turn>", "<|end|>", "<|eot_id|>", "</s>", "<|im_end|>", "<|endoftext|>", "<|assistant|>", "<|user|>"]
        for endToken in endTokens {
            if let range = cleaned.range(of: endToken) {
                cleaned = String(cleaned[..<range.lowerBound])
            }
        }

        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove markdown code blocks (```language ... ```)
        // Handle both ```python\ncode\n``` and ```\ncode\n```
        if cleaned.hasPrefix("```") {
            // Find the end of the opening ``` line (may include language identifier)
            if let firstNewline = cleaned.firstIndex(of: "\n") {
                cleaned = String(cleaned[cleaned.index(after: firstNewline)...])
            } else {
                // No newline, just remove the ```
                cleaned = String(cleaned.dropFirst(3))
            }
        }

        // Remove closing ```
        if cleaned.hasSuffix("```") {
            cleaned = String(cleaned.dropLast(3))
        }

        // Also handle ``` anywhere in the string (in case of partial blocks)
        cleaned = cleaned.replacingOccurrences(of: "```", with: "")

        // Remove common prefixes the model might add
        let prefixesToRemove = [
            "Output:",
            "Corrected:",
            "Result:",
            "Here is the corrected text:",
            "The corrected text is:",
        ]

        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in prefixesToRemove {
            if cleaned.lowercased().hasPrefix(prefix.lowercased()) {
                cleaned = String(cleaned.dropFirst(prefix.count))
                cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        // Remove quotes if the model wrapped the output
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        if (cleaned.hasPrefix("\"") && cleaned.hasSuffix("\"")) ||
           (cleaned.hasPrefix("'") && cleaned.hasSuffix("'")) ||
           (cleaned.hasPrefix("`") && cleaned.hasSuffix("`")) {
            cleaned = String(cleaned.dropFirst().dropLast())
        }

        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        os_log(.info, log: llmLog, "RAW OUTPUT: %{public}@", response)
        os_log(.info, log: llmLog, "CLEANED: %{public}@", cleaned)

        // If the response is empty or much longer than input, return original
        if cleaned.isEmpty || cleaned.count > originalText.count * 3 {
            os_log(.info, log: llmLog, "REJECTED: empty or too long, using original")
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
