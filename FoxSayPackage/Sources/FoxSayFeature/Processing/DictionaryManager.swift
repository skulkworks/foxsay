import Foundation
import os.log

private let dictionaryLog = OSLog(subsystem: "com.foxsay", category: "DICTIONARY")

/// Manages custom dictionary entries for word replacement
@MainActor
public class DictionaryManager: ObservableObject {
    public static let shared = DictionaryManager()

    @Published public private(set) var entries: [DictionaryEntry] = []

    private let userDefaultsKey = "customDictionaryEntries"
    private let hasInitializedKey = "dictionaryHasInitialized"

    private init() {
        loadEntries()
        addDefaultEntriesIfNeeded()
    }

    // MARK: - Default Filler Word Entries (added on first launch only)

    private static let defaultEntries: [DictionaryEntry] = [
        DictionaryEntry(triggers: ["umm", "um"], replacement: nil, isEnabled: true),
        DictionaryEntry(triggers: ["uh", "uhh"], replacement: nil, isEnabled: true),
        DictionaryEntry(triggers: ["hmm", "hmmm"], replacement: nil, isEnabled: true),
        DictionaryEntry(triggers: ["er"], replacement: nil, isEnabled: true),
        DictionaryEntry(triggers: ["ah"], replacement: nil, isEnabled: true),
    ]

    // MARK: - Persistence

    private func loadEntries() {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey) else {
            entries = []
            return
        }

        do {
            entries = try JSONDecoder().decode([DictionaryEntry].self, from: data)
        } catch {
            os_log(.error, log: dictionaryLog, "Failed to load dictionary entries: %{public}@", String(describing: error))
            entries = []
        }
    }

    private func saveEntries() {
        do {
            let data = try JSONEncoder().encode(entries)
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        } catch {
            os_log(.error, log: dictionaryLog, "Failed to save dictionary entries: %{public}@", String(describing: error))
        }
    }

    private func addDefaultEntriesIfNeeded() {
        let hasInitialized = UserDefaults.standard.bool(forKey: hasInitializedKey)
        guard !hasInitialized else { return }

        // Add default filler word entries on first launch
        entries.append(contentsOf: Self.defaultEntries)
        saveEntries()

        UserDefaults.standard.set(true, forKey: hasInitializedKey)
        os_log(.info, log: dictionaryLog, "Added default dictionary entries")
    }

    // MARK: - Public API

    /// Add a new entry
    public func addEntry(_ entry: DictionaryEntry) {
        entries.append(entry)
        saveEntries()
        os_log(.info, log: dictionaryLog, "Added entry: %{public}@", entry.displayName)
    }

    /// Update an existing entry
    public func updateEntry(_ entry: DictionaryEntry) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[index] = entry
        saveEntries()
        os_log(.info, log: dictionaryLog, "Updated entry: %{public}@", entry.displayName)
    }

    /// Toggle an entry's enabled state
    public func toggleEntry(_ entry: DictionaryEntry) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[index].isEnabled.toggle()
        saveEntries()
        os_log(.info, log: dictionaryLog, "Toggled entry: %{public}@ -> %{public}@",
               entry.displayName, entries[index].isEnabled ? "enabled" : "disabled")
    }

    /// Delete an entry
    public func deleteEntry(_ entry: DictionaryEntry) {
        entries.removeAll { $0.id == entry.id }
        saveEntries()
        os_log(.info, log: dictionaryLog, "Deleted entry: %{public}@", entry.displayName)
    }

    // MARK: - Text Processing

    /// Apply dictionary replacements to text
    /// - Parameter text: Input text to process
    /// - Returns: Text with replacements applied
    public func applyReplacements(_ text: String) -> String {
        var result = text

        let enabledEntries = entries.filter { $0.isEnabled }
        guard !enabledEntries.isEmpty else { return text }

        for entry in enabledEntries {
            for trigger in entry.triggers {
                // Case-insensitive word boundary matching
                let pattern = "\\b\(NSRegularExpression.escapedPattern(for: trigger))\\b"
                guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
                    continue
                }

                let range = NSRange(result.startIndex..., in: result)
                let replacement = entry.replacement ?? ""
                result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: replacement)
            }
        }

        // Clean up multiple spaces
        while result.contains("  ") {
            result = result.replacingOccurrences(of: "  ", with: " ")
        }

        return result.trimmingCharacters(in: .whitespaces)
    }
}
