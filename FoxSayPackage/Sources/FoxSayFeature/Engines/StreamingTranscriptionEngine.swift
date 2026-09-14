import Foundation

/// A model that can transcribe while the user is still speaking.
///
/// The batch engines take one complete utterance and hand back text. A streaming
/// engine is fed as the audio arrives and reports a running transcript, which is
/// what makes live text in the overlay — and live typing into the target app —
/// possible.
///
/// Partials from these models are monotonic: each one extends the last rather
/// than rewriting it, which is what lets the injector append instead of having
/// to take text back. `TextInjector` still guards against the other case.
public protocol StreamingTranscriptionEngine: TranscriptionEngine {
    /// Begin a session. `onPartial` receives the running transcript — the whole
    /// thing each time, not just the new words — on an arbitrary thread.
    func startStream(onPartial: @escaping @Sendable (String) -> Void) async throws

    /// Feed captured audio. 16 kHz mono, same as `transcribe(audioBuffer:)`.
    func appendStream(samples: [Float]) async throws

    /// End the session and return everything that was said.
    func finishStream() async throws -> TranscriptionResult

    /// Abandon the session without producing a result.
    func cancelStream() async
}
