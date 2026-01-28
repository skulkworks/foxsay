import Foundation
import os.log

private let modeLog = OSLog(subsystem: "com.foxsay", category: "MODE")

/// Voice modes - simplified to just markdown toggle
/// AI prompts are now handled by PromptManager
public enum VoiceMode: String, CaseIterable {
    case none
    case markdown

    /// Keywords that trigger this mode
    var triggers: [String] {
        switch self {
        case .none: return ["plain", "plain text", "clear mode", "normal", "markdown off", "mark down off", "md off"]
        case .markdown: return ["markdown", "mark down", "md", "markdown on", "mark down on", "md on", "markdown mode", "mark down mode", "md mode"]
        }
    }

    /// Display name for UI
    public var displayName: String {
        switch self {
        case .none: return "Plain Text"
        case .markdown: return "Markdown"
        }
    }
}

/// Manages the current voice mode (markdown toggle)
/// AI prompts are now handled separately by PromptManager
@MainActor
public class VoiceModeManager: ObservableObject {
    public static let shared = VoiceModeManager()

    /// Markdown mode enabled state (persisted)
    @Published public var markdownModeEnabled: Bool {
        didSet {
            UserDefaults.standard.set(markdownModeEnabled, forKey: "markdownModeEnabled")
            os_log(.info, log: modeLog, "Markdown mode: %{public}@", markdownModeEnabled ? "enabled" : "disabled")
        }
    }

    /// Current voice mode (derived from markdownModeEnabled)
    public var currentMode: VoiceMode {
        markdownModeEnabled ? .markdown : .none
    }

    private init() {
        // Load persisted state, default to false
        self.markdownModeEnabled = UserDefaults.standard.bool(forKey: "markdownModeEnabled")
    }

    /// Check if text contains a markdown mode trigger
    /// Returns (triggered, enable, remainingText)
    public func detectMarkdownTrigger(in text: String) -> (triggered: Bool, enable: Bool, remainingText: String) {
        let lowercased = text.lowercased()
        let stripped = lowercased.trimmingCharacters(in: .punctuationCharacters.union(.whitespaces))

        // Check for markdown on triggers
        let onTriggers = ["markdown", "mark down", "md", "markdown on", "mark down on", "md on", "markdown mode", "mark down mode", "md mode"]
        for trigger in onTriggers {
            if lowercased.hasPrefix(trigger + " ") {
                let remaining = String(text.dropFirst(trigger.count + 1))
                os_log(.info, log: modeLog, "Markdown ON trigger: %{public}@", trigger)
                return (true, true, remaining)
            }
            if lowercased == trigger || stripped == trigger {
                os_log(.info, log: modeLog, "Markdown ON (no content)")
                return (true, true, "")
            }
        }

        // Check for markdown off triggers
        let offTriggers = ["markdown off", "mark down off", "md off", "plain", "plain text"]
        for trigger in offTriggers {
            if lowercased.hasPrefix(trigger + " ") {
                let remaining = String(text.dropFirst(trigger.count + 1))
                os_log(.info, log: modeLog, "Markdown OFF trigger: %{public}@", trigger)
                return (true, false, remaining)
            }
            if lowercased == trigger || stripped == trigger {
                os_log(.info, log: modeLog, "Markdown OFF (no content)")
                return (true, false, "")
            }
        }

        return (false, markdownModeEnabled, text)
    }

    /// Toggle markdown mode
    public func toggleMarkdownMode() {
        markdownModeEnabled.toggle()
    }

    /// Set markdown mode explicitly
    public func setMarkdownMode(_ enabled: Bool) {
        markdownModeEnabled = enabled
    }
}
