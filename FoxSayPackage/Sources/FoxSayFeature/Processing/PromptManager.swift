import Foundation
import os.log

private let promptLog = OSLog(subsystem: "com.foxsay", category: "PROMPT")

/// Manages the prompt library and active prompt state
@MainActor
public class PromptManager: ObservableObject {
    public static let shared = PromptManager()

    // MARK: - UserDefaults Keys

    private static let promptsKey = "promptLibrary"
    private static let activePromptIdKey = "activePromptId"

    // MARK: - Published Properties

    /// All available prompts (built-in + custom)
    @Published public private(set) var prompts: [Prompt] = []

    /// Currently active prompt ID (persists until turned off)
    @Published public var activePromptId: UUID? {
        didSet {
            if let id = activePromptId {
                UserDefaults.standard.set(id.uuidString, forKey: Self.activePromptIdKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.activePromptIdKey)
            }
            os_log(.info, log: promptLog, "Active prompt changed: %{public}@",
                   activePromptId?.uuidString ?? "none")
        }
    }

    // MARK: - Computed Properties

    /// Get the currently active prompt
    public var activePrompt: Prompt? {
        guard let id = activePromptId else { return nil }
        return prompts.first { $0.id == id }
    }

    /// Get only custom prompts
    public var customPrompts: [Prompt] {
        prompts.filter { !$0.isBuiltIn }
    }

    /// Get only built-in prompts
    public var builtInPrompts: [Prompt] {
        prompts.filter { $0.isBuiltIn }
    }

    /// Get only enabled prompts (for selector and voice triggers)
    public var enabledPrompts: [Prompt] {
        prompts.filter { $0.isEnabled }
    }

    // MARK: - Initialization

    private init() {
        loadPrompts()

        // Restore active prompt ID
        if let idString = UserDefaults.standard.string(forKey: Self.activePromptIdKey),
           let id = UUID(uuidString: idString) {
            activePromptId = id
        }
    }

    // MARK: - Prompt Management

    /// Add a new custom prompt
    public func addPrompt(_ prompt: Prompt) {
        guard !prompt.isBuiltIn else { return }
        guard !prompts.contains(where: { $0.id == prompt.id }) else { return }

        prompts.append(prompt)
        savePrompts()

        os_log(.info, log: promptLog, "Added prompt: %{public}@", prompt.name)
    }

    /// Update an existing prompt
    public func updatePrompt(_ prompt: Prompt) {
        guard let index = prompts.firstIndex(where: { $0.id == prompt.id }) else { return }

        var updated = prompt
        if prompt.isBuiltIn {
            // Mark built-in prompts as modified when changed
            let original = Prompt.builtInPrompts.first { $0.id == prompt.id }
            updated.isModified = original?.promptText != prompt.promptText
        }

        prompts[index] = updated
        savePrompts()

        os_log(.info, log: promptLog, "Updated prompt: %{public}@", prompt.name)
    }

    /// Delete a prompt (only custom prompts can be deleted)
    public func deletePrompt(_ prompt: Prompt) {
        guard !prompt.isBuiltIn else { return }

        prompts.removeAll { $0.id == prompt.id }
        savePrompts()

        // Clear active prompt if it was deleted
        if activePromptId == prompt.id {
            activePromptId = nil
        }

        os_log(.info, log: promptLog, "Deleted prompt: %{public}@", prompt.name)
    }

    /// Reset a modified built-in prompt to its default
    public func resetToDefault(_ prompt: Prompt) {
        guard prompt.isBuiltIn else { return }
        guard let original = Prompt.builtInPrompts.first(where: { $0.id == prompt.id }) else { return }
        guard let index = prompts.firstIndex(where: { $0.id == prompt.id }) else { return }

        prompts[index] = original
        savePrompts()

        os_log(.info, log: promptLog, "Reset prompt to default: %{public}@", prompt.name)
    }

    /// Toggle the enabled state of a prompt
    public func toggleEnabled(_ prompt: Prompt) {
        guard let index = prompts.firstIndex(where: { $0.id == prompt.id }) else { return }

        // Defer to avoid "Publishing changes from within view updates" warning
        Task { @MainActor in
            self.prompts[index].isEnabled.toggle()
            self.savePrompts()

            // If disabling the active prompt, deactivate it
            if !self.prompts[index].isEnabled && self.activePromptId == prompt.id {
                self.activePromptId = nil
            }

            os_log(.info, log: promptLog, "Toggled prompt enabled: %{public}@ -> %{public}@",
                   prompt.name, self.prompts[index].isEnabled ? "enabled" : "disabled")
        }
    }

    // MARK: - Prompt Activation

    /// Activate a prompt by name (for voice activation)
    /// Returns true if prompt was found and activated
    @discardableResult
    public func activatePrompt(byName name: String) -> Bool {
        let lowercased = name.lowercased().trimmingCharacters(in: .whitespaces)

        if let prompt = prompts.first(where: { $0.name.lowercased() == lowercased }) {
            activePromptId = prompt.id
            os_log(.info, log: promptLog, "Activated prompt by name: %{public}@", name)
            return true
        }

        return false
    }

    /// Activate a prompt by ID
    public func activatePrompt(id: UUID) {
        guard prompts.contains(where: { $0.id == id }) else { return }
        activePromptId = id
        os_log(.info, log: promptLog, "Activated prompt by ID: %{public}@", id.uuidString)
    }

    /// Deactivate the current prompt
    public func deactivatePrompt() {
        activePromptId = nil
        os_log(.info, log: promptLog, "Prompt deactivated")
    }

    /// Check if a prompt is currently active
    public func isActive(_ prompt: Prompt) -> Bool {
        activePromptId == prompt.id
    }

    // MARK: - Voice Command Detection

    /// Detect prompt activation/deactivation commands in text
    /// Returns (command detected, prompt name or nil, remaining text)
    public func detectPromptCommand(in text: String) -> (detected: Bool, promptName: String?, remainingText: String) {
        let normalized = text.normalizedForVoiceCommand

        // Check for deactivation commands
        let offCommands = ["prompt off", "clear prompt", "no prompt", "disable prompt"]
        for cmd in offCommands {
            if normalized == cmd {
                return (true, nil, "")
            }
            if normalized.hasPrefix(cmd + " ") {
                let remaining = String(normalized.dropFirst(cmd.count + 1))
                return (true, nil, remaining)
            }
        }

        // Check for "[name] prompt" pattern (only enabled prompts)
        for prompt in enabledPrompts {
            let pattern1 = "\(prompt.name.lowercased()) prompt"
            if normalized == pattern1 {
                return (true, prompt.name, "")
            }
            if normalized.hasPrefix(pattern1 + " ") {
                let remaining = String(normalized.dropFirst(pattern1.count + 1))
                return (true, prompt.name, remaining)
            }

            // Check for "prompt [name]" pattern
            let pattern2 = "prompt \(prompt.name.lowercased())"
            if normalized == pattern2 {
                return (true, prompt.name, "")
            }
            if normalized.hasPrefix(pattern2 + " ") {
                let remaining = String(normalized.dropFirst(pattern2.count + 1))
                return (true, prompt.name, remaining)
            }
        }

        return (false, nil, text)
    }

    // MARK: - Persistence

    private func loadPrompts() {
        // Start with built-in prompts
        var loaded: [Prompt] = Prompt.builtInPrompts

        // Load saved prompts (custom + modified built-ins)
        if let data = UserDefaults.standard.data(forKey: Self.promptsKey),
           let savedPrompts = try? JSONDecoder().decode([Prompt].self, from: data) {

            // Replace built-ins with saved versions (if modified)
            for saved in savedPrompts {
                if saved.isBuiltIn {
                    if let index = loaded.firstIndex(where: { $0.id == saved.id }) {
                        loaded[index] = saved
                    }
                } else {
                    // Add custom prompts
                    loaded.append(saved)
                }
            }
        }

        prompts = loaded
    }

    private func savePrompts() {
        // Save custom prompts, modified built-ins, and disabled prompts
        let toSave = prompts.filter { !$0.isBuiltIn || $0.isModified || !$0.isEnabled }

        if let data = try? JSONEncoder().encode(toSave) {
            UserDefaults.standard.set(data, forKey: Self.promptsKey)
        }
    }
}
