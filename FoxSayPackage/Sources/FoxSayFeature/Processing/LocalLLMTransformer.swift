import Foundation

/// Wrapper to conform the existing LLMCorrector to the TextTransformer protocol.
/// This allows local MLX models to be used interchangeably with remote providers.
public actor LocalLLMTransformer: TextTransformer {
    public static let shared = LocalLLMTransformer()

    private init() {}

    public var isAvailable: Bool {
        get async {
            await LLMCorrector.shared.available
        }
    }

    public func transform(_ text: String, prompt: String) async throws -> String {
        try await LLMCorrector.shared.correct(text, prompt: prompt)
    }
}
