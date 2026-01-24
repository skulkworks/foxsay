import AppKit
import Carbon.HIToolbox
import Foundation

/// Injects transcribed text into the active application
@MainActor
public class TextInjector {
    public static let shared = TextInjector()

    private let pasteboard = NSPasteboard.general

    /// Whether to only copy to clipboard without pasting
    public var copyToClipboardOnly: Bool {
        UserDefaults.standard.bool(forKey: "copyToClipboardOnly")
    }

    private init() {}

    /// Copy text to clipboard without pasting
    public func copyToClipboard(_ text: String) {
        guard !text.isEmpty else { return }
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        print("VoiceFox: Text copied to clipboard")
    }

    /// Inject text into the frontmost application using pasteboard + Cmd+V
    public func injectText(_ text: String) async throws {
        guard !text.isEmpty else { return }

        NSLog("VoiceFox: injectText called with: '%@'", text)

        // Save current pasteboard contents
        let savedContents = pasteboard.string(forType: .string)
        let savedChangeCount = pasteboard.changeCount

        // Set new text to pasteboard
        pasteboard.clearContents()
        let success = pasteboard.setString(text, forType: .string)
        NSLog("VoiceFox: Pasteboard setString success: %d", success ? 1 : 0)

        // Small delay to ensure pasteboard is ready
        try await Task.sleep(nanoseconds: 50_000_000)  // 50ms

        // Simulate Cmd+V
        simulatePaste()

        // Wait for paste to complete
        try await Task.sleep(nanoseconds: 100_000_000)  // 100ms

        // Don't restore previous pasteboard - let user paste again if needed
        NSLog("VoiceFox: Text injection complete")
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

        NSLog("VoiceFox: Simulated Cmd+V paste")
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
