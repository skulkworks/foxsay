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
            VStack(alignment: .leading, spacing: 20) {
                SettingsPaneHeader(
                    "Dictionary",
                    description: "Replace or remove words in transcribed text — filler words, names, custom terms."
                )

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        SettingsSectionHeader("Word Replacements", systemImage: "character.book.closed")

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
                        Text("No entries yet. Add one to remove or replace words in your transcriptions.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 4)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(dictionaryManager.entries) { entry in
                                entryRow(entry)

                                if entry.id != dictionaryManager.entries.last?.id {
                                    Divider()
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardSurface()

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
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.displayName)
                    .fontWeight(.medium)
                    .foregroundStyle(entry.isEnabled ? .primary : .secondary)

                Text(entry.actionDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 2) {
                RowActionButton(
                    entry.isEnabled ? "eye" : "eye.slash",
                    help: entry.isEnabled ? "Deactivate this entry" : "Activate this entry"
                ) {
                    dictionaryManager.toggleEntry(entry)
                }

                RowActionButton("pencil", help: "Edit entry") {
                    editingEntry = entry
                }

                RowActionButton("trash", help: "Delete entry", role: .destructive) {
                    entryToDelete = entry
                    showDeleteConfirmation = true
                }
            }
        }
        .opacity(entry.isEnabled ? 1 : 0.6)
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
        VStack(spacing: 0) {
            SheetHeader(
                title: entry == nil ? "Add Entry" : "Edit Entry",
                subtitle: "Trigger words are matched in transcribed text and replaced."
            )

            Divider()

            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Trigger Words")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TextField("word1, word2, word3", text: $triggersText)
                        .textFieldStyle(.roundedBorder)

                    Text("Comma-separated list of words that trigger the replacement")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text("Replacement")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TextField("Leave empty to remove", text: $replacement)
                        .textFieldStyle(.roundedBorder)

                    Text("The text to replace trigger words with. Leave empty to remove them.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                // Preview
                if !triggersText.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Preview")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        let previewTrigger = parseTriggers(triggersText).first ?? "word"

                        HStack(spacing: 8) {
                            Text("\"\(previewTrigger)\"")
                            Image(systemName: "arrow.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                            if replacement.isEmpty {
                                Text("removed")
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("\"\(replacement)\"")
                            }
                        }
                        .font(.system(.callout, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .cardSurface(padding: 10)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(20)

            Divider()

            SheetFooter(
                confirmTitle: entry == nil ? "Add" : "Save",
                isConfirmDisabled: parseTriggers(triggersText).isEmpty,
                onCancel: { dismiss() },
                onConfirm: { saveEntry() }
            )
        }
        .frame(width: 420, height: 380)
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
