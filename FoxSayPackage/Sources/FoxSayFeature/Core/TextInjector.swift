import AppKit
import Carbon.HIToolbox
import Foundation

/// Injects transcribed text into the active application
@MainActor
public class TextInjector {
    public static let shared = TextInjector()

    private let pasteboard = NSPasteboard.general

    /// Whether to paste into the active app
    public var shouldPasteToActiveApp: Bool {
        UserDefaults.standard.object(forKey: "pasteToActiveApp") as? Bool ?? true
    }

    /// Whether to copy to clipboard
    public var shouldCopyToClipboard: Bool {
        UserDefaults.standard.bool(forKey: "copyToClipboard")
    }

    /// Whether to save to history
    public var shouldSaveToHistory: Bool {
        UserDefaults.standard.object(forKey: "saveToHistory") as? Bool ?? true
    }

    /// Legacy support - returns true if paste is disabled and copy is enabled
    @available(*, deprecated, message: "Use shouldPasteToActiveApp and shouldCopyToClipboard instead")
    public var copyToClipboardOnly: Bool {
        !shouldPasteToActiveApp && shouldCopyToClipboard
    }

    private let typeUnicodeOverride: ((String) -> Void)?
    private let sendBackspacesOverride: ((Int) -> Void)?

    // Tests can exercise insertion without sending keystrokes to the active app.
    init(typeUnicode: ((String) -> Void)? = nil, sendBackspaces: ((Int) -> Void)? = nil) {
        typeUnicodeOverride = typeUnicode
        sendBackspacesOverride = sendBackspaces
    }

    /// Copy text to clipboard without pasting
    public func copyToClipboard(_ text: String) {
        guard !text.isEmpty else { return }
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        print("FoxSay: Text copied to clipboard")
    }

    /// Inject text into the frontmost application using pasteboard + Cmd+V
    /// - Parameter restoreClipboard: If true, restores the previous clipboard contents after pasting
    public func injectText(_ text: String, restoreClipboard: Bool = false) async throws {
        guard !text.isEmpty else { return }

        NSLog("FoxSay: injectText called with: '%@', restoreClipboard: %d", text, restoreClipboard ? 1 : 0)

        // Save previous clipboard contents if we need to restore later
        let previousContents: [NSPasteboardItem]? = restoreClipboard ? savePasteboardContents() : nil

        // Set new text to pasteboard
        pasteboard.clearContents()
        let success = pasteboard.setString(text, forType: .string)
        NSLog("FoxSay: Pasteboard setString success: %d", success ? 1 : 0)

        // Small delay to ensure pasteboard is ready
        try await Task.sleep(nanoseconds: 50_000_000)  // 50ms

        // Simulate Cmd+V
        simulatePaste()

        // Wait for paste to complete
        try await Task.sleep(nanoseconds: 100_000_000)  // 100ms

        // Restore previous clipboard contents if requested
        if restoreClipboard, let previousContents {
            restorePasteboardContents(previousContents)
            NSLog("FoxSay: Previous clipboard contents restored")
        }

        NSLog("FoxSay: Text injection complete")
    }

    // MARK: - Live injection (streaming models)

    /// Exactly what this session has typed into the target app so far. The
    /// streaming models emit monotonically — every partial extends the last one
    /// rather than rewriting it — so live injection only ever appends, and this
    /// is the record of what would have to be taken back if the processed text
    /// ends up differing.
    public private(set) var liveInjectedText = ""
    private var isLiveInjectionActive = false

    /// Whether anything has been typed live into the target app this session.
    public var hasLiveInjection: Bool { !liveInjectedText.isEmpty }

    public func beginLiveInjection() {
        liveInjectedText = ""
        isLiveInjectionActive = true
    }

    /// Forget this recording's text without deleting it from the target app.
    /// Completed dictations must never be reconciled by a later recording.
    public func resetLiveInjection() {
        liveInjectedText = ""
        isLiveInjectionActive = false
    }

    /// Type whatever part of `transcript` has not been typed yet.
    ///
    /// Uses synthesised key events rather than the pasteboard: a partial lands
    /// every half second or so, and going through the clipboard that often would
    /// stamp on whatever the user had copied.
    public func injectLive(transcript: String) {
        guard isLiveInjectionActive else { return }
        // Partials reach the main actor through separate tasks, and those are
        // not guaranteed to run in the order they were produced. Because the
        // model only ever extends its transcript, anything that is not strictly
        // longer than what we have typed is a straggler from earlier and must be
        // dropped — typing it would duplicate words already on screen.
        guard transcript.count > liveInjectedText.count else { return }

        guard transcript.hasPrefix(liveInjectedText) else {
            // The model rewrote something it had already emitted. Rather than
            // deleting text out from under the user mid-sentence, leave the
            // screen alone and let the reconcile at the end sort it out.
            NSLog("FoxSay: Live partial diverged from typed text — deferring to the final reconcile")
            return
        }

        let delta = String(transcript.dropFirst(liveInjectedText.count))
        guard !delta.isEmpty else { return }

        typeUnicode(delta)
        liveInjectedText = transcript
    }

    /// Reconcile what was typed live with the text the processing pipeline
    /// produced. A no-op when they already agree, which is the common case.
    public func replaceLiveInjection(with finalText: String) async {
        guard isLiveInjectionActive else { return }
        guard liveInjectedText != finalText else { return }

        // Keep the shared opening: only take back the part that differs.
        let commonPrefix = String(liveInjectedText.commonPrefix(with: finalText))
        let toDelete = liveInjectedText.count - commonPrefix.count
        if toDelete > 0 {
            sendBackspaces(toDelete)
            try? await Task.sleep(nanoseconds: 30_000_000)  // let the app catch up
        }

        let remainder = String(finalText.dropFirst(commonPrefix.count))
        if !remainder.isEmpty {
            typeUnicode(remainder)
        }
        liveInjectedText = finalText
    }

    /// Type a string via synthesised key events, no pasteboard involved.
    /// Chunked because a single event carries a limited unicode payload.
    private func typeUnicode(_ text: String) {
        if let typeUnicodeOverride {
            typeUnicodeOverride(text)
            return
        }
        let units = Array(text.utf16)
        let chunkSize = 16
        var index = 0

        while index < units.count {
            let end = min(index + chunkSize, units.count)
            var chunk = Array(units[index..<end])
            index = end

            guard
                let down = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true),
                let up = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false)
            else { continue }

            // The payload goes on the key-down only. Putting it on the key-up
            // as well makes text fields insert the same characters twice.
            down.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: &chunk)
            // Clear the modifiers explicitly. In hold mode the user's finger is
            // still on Right Command while this types, and an inherited flag
            // would turn every character into a menu shortcut.
            down.flags = []
            up.flags = []
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
        }
    }

    private func sendBackspaces(_ count: Int) {
        guard count > 0 else { return }
        if let sendBackspacesOverride {
            sendBackspacesOverride(count)
            return
        }
        for _ in 0..<count {
            let down = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_Delete), keyDown: true)
            let up = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_Delete), keyDown: false)
            // Same reason as typeUnicode: a held hotkey modifier must not turn a
            // backspace into Command-Delete, which deletes the whole line.
            down?.flags = []
            up?.flags = []
            down?.post(tap: .cghidEventTap)
            up?.post(tap: .cghidEventTap)
        }
        NSLog("FoxSay: Took back %d live-typed characters", count)
    }

    /// Save current pasteboard contents for later restoration
    private func savePasteboardContents() -> [NSPasteboardItem]? {
        guard let items = pasteboard.pasteboardItems, !items.isEmpty else { return nil }
        var saved: [NSPasteboardItem] = []
        for item in items {
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    copy.setData(data, forType: type)
                }
            }
            saved.append(copy)
        }
        return saved
    }

    /// Restore previously saved pasteboard contents
    private func restorePasteboardContents(_ items: [NSPasteboardItem]) {
        pasteboard.clearContents()
        pasteboard.writeObjects(items)
    }

    /// Simulate Cmd+V keystroke
    private func simulatePaste() {
        // Create key down event for Cmd+V
        let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true)
        keyDown?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)

        // Create key up event
        let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
        keyUp?.flags = .maskCommand
        keyUp?.post(tap: .cghidEventTap)

        NSLog("FoxSay: Simulated Cmd+V paste")
    }

    /// Alternative: Type text character by character (slower but more compatible)
    public func typeText(_ text: String) async {
        for character in text {
            if let keyCode = keyCode(for: character) {
                let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: keyCode.code, keyDown: true)
                if keyCode.shift {
                    keyDown?.flags = .maskShift
                }
                keyDown?.post(tap: .cghidEventTap)

                let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: keyCode.code, keyDown: false)
                keyUp?.post(tap: .cghidEventTap)

                try? await Task.sleep(nanoseconds: 10_000_000)  // 10ms between keystrokes
            }
        }
    }

    private func keyCode(for character: Character) -> (code: CGKeyCode, shift: Bool)? {
        let char = String(character).lowercased()

        // Basic alphanumeric mappings
        let keyMap: [String: CGKeyCode] = [
            "a": CGKeyCode(kVK_ANSI_A), "b": CGKeyCode(kVK_ANSI_B), "c": CGKeyCode(kVK_ANSI_C),
            "d": CGKeyCode(kVK_ANSI_D), "e": CGKeyCode(kVK_ANSI_E), "f": CGKeyCode(kVK_ANSI_F),
            "g": CGKeyCode(kVK_ANSI_G), "h": CGKeyCode(kVK_ANSI_H), "i": CGKeyCode(kVK_ANSI_I),
            "j": CGKeyCode(kVK_ANSI_J), "k": CGKeyCode(kVK_ANSI_K), "l": CGKeyCode(kVK_ANSI_L),
            "m": CGKeyCode(kVK_ANSI_M), "n": CGKeyCode(kVK_ANSI_N), "o": CGKeyCode(kVK_ANSI_O),
            "p": CGKeyCode(kVK_ANSI_P), "q": CGKeyCode(kVK_ANSI_Q), "r": CGKeyCode(kVK_ANSI_R),
            "s": CGKeyCode(kVK_ANSI_S), "t": CGKeyCode(kVK_ANSI_T), "u": CGKeyCode(kVK_ANSI_U),
            "v": CGKeyCode(kVK_ANSI_V), "w": CGKeyCode(kVK_ANSI_W), "x": CGKeyCode(kVK_ANSI_X),
            "y": CGKeyCode(kVK_ANSI_Y), "z": CGKeyCode(kVK_ANSI_Z),
            "0": CGKeyCode(kVK_ANSI_0), "1": CGKeyCode(kVK_ANSI_1), "2": CGKeyCode(kVK_ANSI_2),
            "3": CGKeyCode(kVK_ANSI_3), "4": CGKeyCode(kVK_ANSI_4), "5": CGKeyCode(kVK_ANSI_5),
            "6": CGKeyCode(kVK_ANSI_6), "7": CGKeyCode(kVK_ANSI_7), "8": CGKeyCode(kVK_ANSI_8),
            "9": CGKeyCode(kVK_ANSI_9),
            " ": CGKeyCode(kVK_Space),
            "-": CGKeyCode(kVK_ANSI_Minus),
            "=": CGKeyCode(kVK_ANSI_Equal),
            ".": CGKeyCode(kVK_ANSI_Period),
            ",": CGKeyCode(kVK_ANSI_Comma),
            "/": CGKeyCode(kVK_ANSI_Slash),
            "\n": CGKeyCode(kVK_Return),
            "\t": CGKeyCode(kVK_Tab),
        ]

        if let code = keyMap[char] {
            let needsShift = character.isUppercase
            return (code, needsShift)
        }

        return nil
    }
}
