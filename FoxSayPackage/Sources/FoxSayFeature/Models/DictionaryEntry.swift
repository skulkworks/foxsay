import Foundation

/// A dictionary entry for word replacement
public struct DictionaryEntry: Codable, Identifiable, Equatable {
    public let id: UUID
    public var triggers: [String]       // Words that trigger replacement
    public var replacement: String?     // nil/empty = remove word
    public var isEnabled: Bool

    public init(
        id: UUID = UUID(),
        triggers: [String],
        replacement: String? = nil,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.triggers = triggers
        self.replacement = replacement
        self.isEnabled = isEnabled
    }

    /// Display name for the entry (triggers joined)
    public var displayName: String {
        triggers.joined(separator: ", ")
    }

    /// Description of what happens when triggered
    public var actionDescription: String {
        if let replacement = replacement, !replacement.isEmpty {
            return "Replace with \"\(replacement)\""
        } else {
            return "Remove"
        }
    }
}
