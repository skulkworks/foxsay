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
    ///   - prompt: The prompt template (must contain {input} placeholder)
    /// - Returns: Transformed text
    public func correct(_ text: String, prompt: String) async throws -> String {
        let manager = await AIModelManager.shared
        let container = try await manager.getModel()

        // Build the prompt with input substituted
        let promptText = prompt.replacingOccurrences(of: "{input}", with: text)

        os_log(.info, log: llmLog, ">>> PRE-LLM: %{public}@", text)
        os_log(.info, log: llmLog, ">>> PROMPT: %{public}@", promptText)
        print("FoxSay: [LLM] Full prompt being sent to model:")
        print("---BEGIN PROMPT---")
        print(promptText)
        print("---END PROMPT---")

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
        print("FoxSay: [LLM] Generation took \(String(format: "%.0f", processingTime * 1000))ms")
        print("FoxSay: [LLM] Raw output: \"\(generatedText)\"")

        // Clean up the response
        let corrected = cleanResponse(generatedText, originalText: text, promptText: promptText)
        print("FoxSay: [LLM] Cleaned output: \"\(corrected)\"")

        return corrected
    }

    /// Clean up the LLM response to extract just the corrected text
    private func cleanResponse(_ response: String, originalText: String, promptText: String) -> String {
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

        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove chatty LLM prefixes (applied repeatedly until none match)
        // These are common phrases models use before giving the actual answer
        let chattyPrefixes = [
            "sure,", "sure!", "sure.",
            "of course,", "of course!", "of course.",
            "certainly,", "certainly!", "certainly.",
            "absolutely,", "absolutely!", "absolutely.",
            "okay,", "okay.", "ok,", "ok.",
            "here you go:", "here you go.",
            "here it is:", "here it is.",
            "here's", "here is",
            "the result is:", "the result is",
            "the answer is:", "the answer is",
            "the output is:", "the output is",
            "the reversed text is:", "the reversed text is",
            "the corrected text is:", "the corrected text is",
            "output:", "result:", "answer:", "corrected:", "reversed:",
        ]

        var didRemovePrefix = true
        while didRemovePrefix {
            didRemovePrefix = false
            cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
            for prefix in chattyPrefixes {
                if cleaned.lowercased().hasPrefix(prefix) {
                    cleaned = String(cleaned.dropFirst(prefix.count))
                    cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
                    didRemovePrefix = true
                    break
                }
            }
        }

        // If the response contains a colon followed by content, and the part before
        // the colon looks like an explanation, take only what's after
        // e.g., "Here's the reversed order of words: actual result"
        if let colonRange = cleaned.range(of: ":") {
            let beforeColon = String(cleaned[..<colonRange.lowerBound]).lowercased()
            let explanatoryPhrases = [
                "here's the", "here is the", "the reversed", "the corrected",
                "the result", "the answer", "the output", "your text",
                "the words", "reversed order", "word order"
            ]
            if explanatoryPhrases.contains(where: { beforeColon.contains($0) }) {
                let afterColon = String(cleaned[colonRange.upperBound...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !afterColon.isEmpty {
                    cleaned = afterColon
                }
            }
        }

        // If the model echoed the prompt, try to extract just the result
        if cleaned.hasPrefix(promptText) {
            cleaned = String(cleaned.dropFirst(promptText.count))
            cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Some models output the original text followed by the transformation
        if cleaned.hasPrefix(originalText) && cleaned.count > originalText.count + 5 {
            let afterInput = String(cleaned.dropFirst(originalText.count))
            let trimmed = afterInput.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.count > 3 {
                cleaned = trimmed
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

        // If the response is empty, return original
        // Note: We allow longer outputs since prompts like "expand" or "friendly" may generate more text
        if cleaned.isEmpty {
            os_log(.info, log: llmLog, "REJECTED: empty, using original")
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
