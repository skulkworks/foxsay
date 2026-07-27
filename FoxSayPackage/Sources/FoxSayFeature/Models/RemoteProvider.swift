import Foundation

/// Represents a remote LLM provider configuration (OpenAI-compatible API)
public struct RemoteProvider: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public var baseURL: String
    public var apiKey: String?
    public var modelName: String?
    public var isEnabled: Bool
    public var isBuiltIn: Bool
    /// Whether this provider has been verified to work (via connection test)
    public var isVerified: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        baseURL: String,
        apiKey: String? = nil,
        modelName: String? = nil,
        isEnabled: Bool = true,
        isBuiltIn: Bool = false,
        isVerified: Bool = false
    ) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.modelName = modelName
        self.isEnabled = isEnabled
        self.isBuiltIn = isBuiltIn
        self.isVerified = isVerified
    }

    /// Pre-configured provider presets for common services
    public static let presets: [RemoteProvider] = [
        RemoteProvider(
            name: "OpenAI",
            baseURL: "https://api.openai.com/v1",
            apiKey: nil,
            modelName: "gpt-5-chat-latest",
            isEnabled: true,
            isBuiltIn: true
        ),
        RemoteProvider(
            name: "Anthropic",
            baseURL: "https://api.anthropic.com/v1",
            apiKey: nil,
            modelName: "claude-haiku-4-5",
            isEnabled: true,
            isBuiltIn: true
        ),
        RemoteProvider(
            name: "Google",
            baseURL: "https://generativelanguage.googleapis.com/v1beta/openai",
            apiKey: nil,
            modelName: "gemini-2.5-flash",
            isEnabled: true,
            isBuiltIn: true
        ),
        RemoteProvider(
            name: "OpenRouter",
            baseURL: "https://openrouter.ai/api/v1",
            apiKey: nil,
            modelName: "openrouter/free",
            isEnabled: true,
            isBuiltIn: true
        ),
        RemoteProvider(
            name: "LM Studio",
            baseURL: "http://localhost:1234/v1",
            apiKey: nil,
            modelName: nil,
            isEnabled: true,
            isBuiltIn: true
        ),
        RemoteProvider(
            name: "Ollama",
            baseURL: "http://localhost:11434/v1",
            apiKey: nil,
            modelName: nil,
            isEnabled: true,
            isBuiltIn: true
        )
    ]

    /// Create a copy of this provider with a new UUID
    public func createCopy() -> RemoteProvider {
        RemoteProvider(
            id: UUID(),
            name: name,
            baseURL: baseURL,
            apiKey: apiKey,
            modelName: modelName,
            isEnabled: isEnabled,
            isBuiltIn: isBuiltIn,
            isVerified: isVerified
        )
    }
}

// Custom Codable to handle migration from older versions
extension RemoteProvider: Codable {
    enum CodingKeys: String, CodingKey {
        case id, name, baseURL, apiKey, modelName, isEnabled, isBuiltIn, isVerified
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        baseURL = try container.decode(String.self, forKey: .baseURL)
        apiKey = try container.decodeIfPresent(String.self, forKey: .apiKey)
        modelName = try container.decodeIfPresent(String.self, forKey: .modelName)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        // Handle migration: default to false if missing, but mark as built-in if it matches a preset URL
        if let builtIn = try container.decodeIfPresent(Bool.self, forKey: .isBuiltIn) {
            isBuiltIn = builtIn
        } else {
            // Migration: check if this matches a built-in preset by URL
            let presetURLs = RemoteProvider.presets.map { $0.baseURL }
            isBuiltIn = presetURLs.contains(baseURL)
        }
        // Migration: default to false if missing
        isVerified = try container.decodeIfPresent(Bool.self, forKey: .isVerified) ?? false
    }
}

/// Type of LLM provider to use
public enum LLMProviderType: String, Codable, CaseIterable, Sendable {
    case local = "local"
    case remote = "remote"

    public var displayName: String {
        switch self {
        case .local: return "Local Models"
        case .remote: return "Remote API"
        }
    }
}
