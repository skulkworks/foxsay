import Foundation
import os.log

private let remoteLog = OSLog(subsystem: "com.foxsay", category: "REMOTE-LLM")

/// Error types for remote LLM service
public enum RemoteLLMError: Error, LocalizedError {
    case invalidURL
    case connectionFailed(String)
    case requestFailed(Int, String)
    case noResponse
    case decodingFailed(String)
    case providerNotConfigured

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid server URL"
        case .connectionFailed(let message):
            return "Connection failed: \(message)"
        case .requestFailed(let status, let message):
            return "Request failed (\(status)): \(message)"
        case .noResponse:
            return "No response from server"
        case .decodingFailed(let message):
            return "Failed to decode response: \(message)"
        case .providerNotConfigured:
            return "Remote provider not configured"
        }
    }
}

/// HTTP client for OpenAI-compatible LLM APIs
public actor RemoteLLMService: TextTransformer {
    private let provider: RemoteProvider
    private let session: URLSession

    public init(provider: RemoteProvider) {
        self.provider = provider

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 120
        self.session = URLSession(configuration: config)
    }

    public var isAvailable: Bool {
        get async {
            provider.isEnabled && !provider.baseURL.isEmpty
        }
    }

    /// Test connection to the remote server by fetching available models
    public func testConnection() async -> Result<[String], RemoteLLMError> {
        guard let baseURL = URL(string: provider.baseURL) else {
            return .failure(.invalidURL)
        }

        let modelsURL = baseURL.appendingPathComponent("models")
        var request = URLRequest(url: modelsURL)
        request.httpMethod = "GET"

        if let apiKey = provider.apiKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                return .failure(.noResponse)
            }

            guard httpResponse.statusCode == 200 else {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                return .failure(.requestFailed(httpResponse.statusCode, errorMessage))
            }

            // Parse the models response
            struct ModelsResponse: Decodable {
                let data: [ModelInfo]?

                struct ModelInfo: Decodable {
                    let id: String
                }
            }

            let modelsResponse = try JSONDecoder().decode(ModelsResponse.self, from: data)

            // Filter to only chat-capable models for OpenAI
            // OpenAI's API doesn't provide capability metadata, so we filter by name:
            // - Models with "chat" (case insensitive) support chat completions
            // - Reasoning models (o1, o3, gpt-5 without chat) don't work with chat completions
            let chatModels = modelsResponse.data?.filter { model in
                let id = model.id.lowercased()
                // Include if it contains "chat", or is from a local server (different naming conventions)
                let isChatModel = id.contains("chat")
                let isLocalServer = !provider.baseURL.contains("openai.com")
                return isChatModel || isLocalServer
            }

            let modelIds = chatModels?.map { $0.id } ?? []
            return .success(modelIds)
        } catch let error as RemoteLLMError {
            return .failure(error)
        } catch {
            return .failure(.connectionFailed(error.localizedDescription))
        }
    }

    /// Transform text using the remote LLM
    public func transform(_ text: String, prompt: String) async throws -> String {
        guard let baseURL = URL(string: provider.baseURL) else {
            throw RemoteLLMError.invalidURL
        }

        let completionsURL = baseURL.appendingPathComponent("chat/completions")

        // Build the prompt with input substituted
        let promptText = prompt.replacingOccurrences(of: "{input}", with: text)

        os_log(.info, log: remoteLog, ">>> PRE-REMOTE: %{public}@", text)
        os_log(.info, log: remoteLog, ">>> PROMPT: %{public}@", promptText)
        print("FoxSay: [REMOTE-LLM] Full prompt being sent to remote model:")
        print("---BEGIN PROMPT---")
        print(promptText)
        print("---END PROMPT---")

        let startTime = CFAbsoluteTimeGetCurrent()

        // Build the request
        var request = URLRequest(url: completionsURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let apiKey = provider.apiKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        // Build the request body
        // Use max_completion_tokens (required for OpenAI's newer models: gpt-4o, gpt-5, o1, etc.)
        // Omit temperature as reasoning models (o1, o3, gpt-5) only support the default value
        var requestBody: [String: Any] = [
            "messages": [
                ["role": "user", "content": promptText]
            ],
            "max_completion_tokens": 200
        ]

        // Add model name if specified
        if let modelName = provider.modelName, !modelName.isEmpty {
            requestBody["model"] = modelName
        } else {
            // Default model name for compatibility
            requestBody["model"] = "default"
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        // Make the request
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw RemoteLLMError.noResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw RemoteLLMError.requestFailed(httpResponse.statusCode, errorMessage)
        }

        // Parse the response
        struct ChatCompletionResponse: Decodable {
            let choices: [Choice]

            struct Choice: Decodable {
                let message: Message?
                // Some models return content directly in the choice
                let text: String?
            }

            struct Message: Decodable {
                let content: String?
            }
        }

        // Log raw response for debugging
        if let rawJson = String(data: data, encoding: .utf8) {
            print("FoxSay: [REMOTE-LLM] Raw API response: \(rawJson.prefix(500))")
        }

        let completionResponse: ChatCompletionResponse
        do {
            completionResponse = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        } catch {
            if let rawJson = String(data: data, encoding: .utf8) {
                print("FoxSay: [REMOTE-LLM] Failed to decode response: \(rawJson)")
            }
            throw RemoteLLMError.decodingFailed(error.localizedDescription)
        }

        guard let firstChoice = completionResponse.choices.first else {
            throw RemoteLLMError.noResponse
        }

        // Try message.content first (standard chat format), then fall back to text (completion format)
        let generatedText = firstChoice.message?.content ?? firstChoice.text ?? ""

        let processingTime = CFAbsoluteTimeGetCurrent() - startTime
        print("FoxSay: [REMOTE-LLM] Generation took \(String(format: "%.0f", processingTime * 1000))ms")
        print("FoxSay: [REMOTE-LLM] Raw output: \"\(generatedText)\"")

        // Clean up the response
        let corrected = cleanResponse(generatedText, originalText: text, promptText: promptText)
        print("FoxSay: [REMOTE-LLM] Cleaned output: \"\(corrected)\"")

        return corrected
    }

    /// Clean up the LLM response to extract just the corrected text
    /// Reused logic from LLMCorrector
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
        if cleaned.hasPrefix("```") {
            if let firstNewline = cleaned.firstIndex(of: "\n") {
                cleaned = String(cleaned[cleaned.index(after: firstNewline)...])
            } else {
                cleaned = String(cleaned.dropFirst(3))
            }
        }

        if cleaned.hasSuffix("```") {
            cleaned = String(cleaned.dropLast(3))
        }

        cleaned = cleaned.replacingOccurrences(of: "```", with: "")
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove chatty LLM prefixes
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

        os_log(.info, log: remoteLog, "RAW OUTPUT: %{public}@", response)
        os_log(.info, log: remoteLog, "CLEANED: %{public}@", cleaned)

        // If the response is empty, return original
        if cleaned.isEmpty {
            os_log(.info, log: remoteLog, "REJECTED: empty, using original")
            return originalText
        }

        return cleaned
    }
}
