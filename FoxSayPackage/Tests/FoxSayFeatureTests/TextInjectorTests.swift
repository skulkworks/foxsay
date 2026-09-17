import Testing
@testable import FoxSayFeature

@Suite("Dictation text ownership")
@MainActor
struct TextInjectorTests {
    @MainActor
    private final class TextBuffer {
        var text = "Existing note. "
        var deletedCharacters = 0

        func makeInjector() -> TextInjector {
            TextInjector(
                typeUnicode: { self.text += $0 },
                sendBackspaces: {
                    self.deletedCharacters += $0
                    self.text.removeLast($0)
                }
            )
        }
    }

    @Test("Switching from streaming to batch preserves the completed dictation")
    func streamingToBatch() async {
        let buffer = TextBuffer()
        let injector = buffer.makeInjector()
        injector.beginLiveInjection()
        injector.injectLive(transcript: "First dictation.")
        await injector.replaceLiveInjection(with: "First dictation.")
        injector.resetLiveInjection()

        // The batch output path must see no live text to reconcile or delete.
        #expect(!injector.hasLiveInjection)
        #expect(injector.liveInjectedText.isEmpty)
        await injector.replaceLiveInjection(with: "Second dictation.")
        #expect(buffer.text == "Existing note. First dictation.")
        #expect(buffer.deletedCharacters == 0)
    }

    @Test("A fresh recording forgets live text even if previous cleanup was missed")
    func resetBeforeNextRecording() {
        let buffer = TextBuffer()
        let injector = buffer.makeInjector()
        injector.beginLiveInjection()
        injector.injectLive(transcript: "First dictation.")

        injector.resetLiveInjection()
        #expect(!injector.hasLiveInjection)
        #expect(buffer.text == "Existing note. First dictation.")
    }

    @Test("Late partials cannot restore a completed recording's text")
    func ignoresLatePartial() {
        let buffer = TextBuffer()
        let injector = buffer.makeInjector()
        injector.beginLiveInjection()
        injector.injectLive(transcript: "First.")
        injector.resetLiveInjection()
        injector.injectLive(transcript: "First. Late words.")

        #expect(!injector.hasLiveInjection)
        #expect(buffer.text == "Existing note. First.")
    }

    @Test("Consecutive streaming dictations only correct their own text")
    func consecutiveStreamingRecordings() async {
        let buffer = TextBuffer()
        let injector = buffer.makeInjector()
        injector.beginLiveInjection()
        injector.injectLive(transcript: "First dictation.")
        injector.resetLiveInjection()

        injector.beginLiveInjection()
        injector.injectLive(transcript: " Second draft")
        await injector.replaceLiveInjection(with: " Second dictation.")
        injector.resetLiveInjection()

        #expect(buffer.text == "Existing note. First dictation. Second dictation.")
        #expect(buffer.deletedCharacters == 4)
        #expect(!injector.hasLiveInjection)
    }

    @Test("Cancelling or discarding a recording removes only its live text")
    func discardCurrentRecording() async {
        let buffer = TextBuffer()
        let injector = buffer.makeInjector()
        injector.beginLiveInjection()
        injector.injectLive(transcript: "Keep this.")
        injector.resetLiveInjection()

        injector.beginLiveInjection()
        injector.injectLive(transcript: " Discard this.")
        await injector.replaceLiveInjection(with: "")
        injector.resetLiveInjection()

        #expect(buffer.text == "Existing note. Keep this.")
        #expect(buffer.deletedCharacters == " Discard this.".count)
        #expect(!injector.hasLiveInjection)
    }
}
