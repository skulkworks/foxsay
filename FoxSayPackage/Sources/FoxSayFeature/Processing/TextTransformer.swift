import Foundation

/// Protocol defining a common interface for text transformation services.
/// Both local (MLX) and remote (OpenAI-compatible) providers conform to this protocol.
public protocol TextTransformer: Sendable {
    /// Whether the transformer is currently available for use
    var isAvailable: Bool { get async }

    /// Transform text using the given prompt
    /// - Parameters:
    ///   - text: The text to transform
    ///   - prompt: The prompt template (should contain {input} placeholder)
    /// - Returns: The transformed text
    func transform(_ text: String, prompt: String) async throws -> String
}
