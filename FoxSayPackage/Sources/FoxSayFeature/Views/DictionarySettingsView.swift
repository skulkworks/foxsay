import SwiftUI

/// Settings view for managing custom dictionary entries
public struct DictionarySettingsView: View {
    @ObservedObject private var dictionaryManager = DictionaryManager.shared

    @State private var showingAddSheet = false
    @State private var editingEntry: DictionaryEntry?
    @State private var showDeleteConfirmation = false
    @State private var entryToDelete: DictionaryEntry?

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                Text("Dictionary")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Define word replacements that are applied to transcribed text. Use this to remove filler words or replace custom terms.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                // Dictionary Entries
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label("Word Replacements", systemImage: "character.book.closed")
                                .font(.headline)

                            Spacer()

                            Button {
                                showingAddSheet = true
                            } label: {
                                Label("Add Entry", systemImage: "plus")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }

                        if dictionaryManager.entries.isEmpty {
                            Text("No dictionary entries. Add entries to remove or replace words in your transcriptions.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 8)
                        } else {
                            ForEach(dictionaryManager.entries) { entry in
                                entryRow(entry)

                                if entry.id != dictionaryManager.entries.last?.id {
                                    Divider()
                                }
                            }
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Spacer()
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showingAddSheet) {
            DictionaryEntrySheet(entry: nil) { newEntry in
                dictionaryManager.addEntry(newEntry)
            }
        }
        .sheet(item: $editingEntry) { entry in
            DictionaryEntrySheet(entry: entry) { updatedEntry in
                dictionaryManager.updateEntry(updatedEntry)
            }
        }
        .alert("Delete Entry?", isPresented: $showDeleteConfirmation, presenting: entryToDelete) { entry in
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                dictionaryManager.deleteEntry(entry)
            }
        } message: { entry in
            Text("Are you sure you want to delete \"\(entry.displayName)\"? This cannot be undone.")
        }
    }

    // MARK: - Entry Row

    private func entryRow(_ entry: DictionaryEntry) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.displayName)
                    .fontWeight(.medium)
                    .foregroundStyle(entry.isEnabled ? .primary : .secondary)

                Text(entry.actionDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 8) {
                // Visibility toggle (eye icon)
                Button {
                    dictionaryManager.toggleEntry(entry)
                } label: {
                    Image(systemName: entry.isEnabled ? "eye" : "eye.slash")
                        .foregroundColor(entry.isEnabled ? .secondary : .red.opacity(0.6))
                }
                .buttonStyle(.borderless)
                .help(entry.isEnabled ? "Deactivate" : "Activate")

                // Edit button
                Button {
                    editingEntry = entry
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)

                // Delete button
                Button(role: .destructive) {
                    entryToDelete = entry
                    showDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Add/Edit Entry Sheet

private struct DictionaryEntrySheet: View {
    let entry: DictionaryEntry?
    let onSave: (DictionaryEntry) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var triggersText: String = ""
    @State private var replacement: String = ""
    @State private var isEnabled: Bool = true

    init(entry: DictionaryEntry?, onSave: @escaping (DictionaryEntry) -> Void) {
        self.entry = entry
        self.onSave = onSave
    }

    var body: some View {
        VStack(spacing: 20) {
            Text(entry == nil ? "Add Entry" : "Edit Entry")
                .font(.headline)

            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Trigger Words")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TextField("word1, word2, word3", text: $triggersText)
                        .textFieldStyle(.roundedBorder)

                    Text("Comma-separated list of words that trigger the replacement")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Replacement")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TextField("Leave empty to remove", text: $replacement)
                        .textFieldStyle(.roundedBorder)

                    Text("The text to replace trigger words with. Leave empty to remove them.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            // Preview
            if !triggersText.isEmpty {
                GroupBox {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Preview")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)

                        let previewTrigger = parseTriggers(triggersText).first ?? "word"
                        let previewResult = replacement.isEmpty ? "" : replacement

                        HStack {
                            Text("\"\(previewTrigger)\"")
                            Image(systemName: "arrow.right")
                                .foregroundStyle(.secondary)
                            if previewResult.isEmpty {
                                Text("(removed)")
                                    .italic()
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("\"\(previewResult)\"")
                            }
                        }
                        .font(.callout)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Spacer()

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button(entry == nil ? "Add" : "Save") {
                    saveEntry()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(parseTriggers(triggersText).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 400, height: 350)
        .onAppear {
            if let entry = entry {
                triggersText = entry.triggers.joined(separator: ", ")
                replacement = entry.replacement ?? ""
                isEnabled = entry.isEnabled
            }
        }
    }

    private func parseTriggers(_ text: String) -> [String] {
        text.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private func saveEntry() {
        let triggers = parseTriggers(triggersText)
        guard !triggers.isEmpty else { return }

        let newEntry = DictionaryEntry(
            id: entry?.id ?? UUID(),
            triggers: triggers,
            replacement: replacement.isEmpty ? nil : replacement,
            isEnabled: entry?.isEnabled ?? true
        )

        onSave(newEntry)
        dismiss()
    }
}

#Preview {
    DictionarySettingsView()
        .frame(width: 500, height: 600)
}
