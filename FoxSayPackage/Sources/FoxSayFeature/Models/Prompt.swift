import Foundation

/// Represents a prompt template for AI text transformation
public struct Prompt: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public var name: String
    public var displayName: String
    public var description: String
    public var promptText: String
    public let isBuiltIn: Bool
    public var isModified: Bool
    public var isEnabled: Bool

    // Coding keys for custom Decodable
    private enum CodingKeys: String, CodingKey {
        case id, name, displayName, description, promptText, isBuiltIn, isModified, isEnabled
    }

    public init(
        id: UUID = UUID(),
        name: String,
        displayName: String,
        description: String,
        promptText: String,
        isBuiltIn: Bool = false,
        isModified: Bool = false,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.displayName = displayName
        self.description = description
        self.promptText = promptText
        self.isBuiltIn = isBuiltIn
        self.isModified = isModified
        self.isEnabled = isEnabled
    }

    // Custom Decodable to handle missing isEnabled from older saved data
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        displayName = try container.decode(String.self, forKey: .displayName)
        description = try container.decode(String.self, forKey: .description)
        promptText = try container.decode(String.self, forKey: .promptText)
        isBuiltIn = try container.decode(Bool.self, forKey: .isBuiltIn)
        isModified = try container.decodeIfPresent(Bool.self, forKey: .isModified) ?? false
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
    }

    /// Build the final prompt with input text substituted
    public func buildPrompt(for inputText: String) -> String {
        promptText.replacingOccurrences(of: "{input}", with: inputText)
    }

    public static func == (lhs: Prompt, rhs: Prompt) -> Bool {
        lhs.id == rhs.id
    }

    // MARK: - Built-in Prompts

    public static let builtInPrompts: [Prompt] = [
        Prompt(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            name: "summarize",
            displayName: "Summarize",
            description: "Condense text to key points",
            promptText: """
                Summarize the following text into key bullet points. Be concise and capture the main ideas.
                Output only the bullet points, nothing else.

                Text: {input}
                """,
            isBuiltIn: true
        ),
        Prompt(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            name: "expand",
            displayName: "Expand & Detail",
            description: "Add elaboration and detail",
            promptText: """
                Expand the following text with more detail and elaboration. Keep the same tone and style.
                Add context, examples, or explanations where appropriate.
                Output only the expanded text, nothing else.

                Text: {input}
                """,
            isBuiltIn: true
        ),
        Prompt(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
            name: "formal",
            displayName: "Professional Tone",
            description: "Rewrite in formal business style",
            promptText: """
                Rewrite the following text in a professional, formal business tone.
                Maintain the core message but make it suitable for professional communication.
                Output only the rewritten text, nothing else.

                Text: {input}
                """,
            isBuiltIn: true
        ),
        Prompt(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
            name: "friendly",
            displayName: "Friendly Tone",
            description: "Rewrite in conversational style",
            promptText: """
                Rewrite the following text in a friendly, conversational tone.
                Make it warm and approachable while keeping the message clear.
                Output only the rewritten text, nothing else.

                Text: {input}
                """,
            isBuiltIn: true
        ),
        Prompt(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000005")!,
            name: "concise",
            displayName: "Concise & Clear",
            description: "Make brief but complete",
            promptText: """
                Rewrite the following text to be more concise and clear.
                Remove unnecessary words while preserving all important information.
                Output only the rewritten text, nothing else.

                Text: {input}
                """,
            isBuiltIn: true
        ),
        Prompt(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000006")!,
            name: "proofread",
            displayName: "Proofread",
            description: "Fix grammar, spelling, punctuation",
            promptText: """
                Proofread and correct the following text. Fix any grammar, spelling, or punctuation errors.
                Preserve the original meaning and style. Make minimal changes.
                Output only the corrected text, nothing else.

                Text: {input}
                """,
            isBuiltIn: true
        ),
        Prompt(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000007")!,
            name: "bullets",
            displayName: "Bullet Points",
            description: "Convert to bullet list",
            promptText: """
                Convert the following text into a bullet point list.
                Each bullet should be a complete, clear point.
                Output only the bullet points using markdown format (- item), nothing else.

                Text: {input}
                """,
            isBuiltIn: true
        ),
        Prompt(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000008")!,
            name: "email",
            displayName: "Email Format",
            description: "Structure as professional email",
            promptText: """
                Format the following text as a professional email.
                Include a greeting, body paragraphs, and closing.
                Keep it professional but warm. Output only the email text, nothing else.

                Text: {input}
                """,
            isBuiltIn: true
        ),
    ]

    /// Get a built-in prompt by its name
    public static func builtInPrompt(named name: String) -> Prompt? {
        builtInPrompts.first { $0.name.lowercased() == name.lowercased() }
    }
}
