import SwiftUI

/// Prompts settings view for managing the prompt library
public struct PromptsSettingsView: View {
    @ObservedObject private var promptManager = PromptManager.shared
    @ObservedObject private var aiModelManager = AIModelManager.shared

    @State private var showAddPromptSheet = false
    @State private var editingPrompt: Prompt?
    @State private var showDeleteConfirmation = false
    @State private var promptToDelete: Prompt?

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                Text("Prompts")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Manage your prompt library. Use prompts to transform transcribed text with AI assistance.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                // AI model requirement warning
                if !aiModelManager.isModelReady {
                    aiModelWarning
                }

                // Active prompt indicator
                if let activePrompt = promptManager.activePrompt {
                    activePromptIndicator(activePrompt)
                }

                // Built-in prompts
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Built-in Prompts", systemImage: "star.fill")
                            .font(.headline)

                        ForEach(promptManager.builtInPrompts) { prompt in
                            promptRow(prompt)
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Custom prompts
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label("Custom Prompts", systemImage: "person.fill")
                                .font(.headline)

                            Spacer()

                            Button {
                                showAddPromptSheet = true
                            } label: {
                                Label("Add Prompt", systemImage: "plus")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }

                        if promptManager.customPrompts.isEmpty {
                            Text("No custom prompts yet. Add your own prompts to create custom text transformations.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 8)
                        } else {
                            ForEach(promptManager.customPrompts) { prompt in
                                promptRow(prompt)
                            }
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Voice activation info
                voiceActivationInfo

                Spacer()
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showAddPromptSheet) {
            PromptEditSheet(prompt: nil) { newPrompt in
                promptManager.addPrompt(newPrompt)
            }
        }
        .sheet(item: $editingPrompt) { prompt in
            PromptEditSheet(prompt: prompt) { updatedPrompt in
                promptManager.updatePrompt(updatedPrompt)
            }
        }
        .alert("Delete Prompt?", isPresented: $showDeleteConfirmation, presenting: promptToDelete) { prompt in
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                promptManager.deletePrompt(prompt)
            }
        } message: { prompt in
            Text("Are you sure you want to delete \"\(prompt.displayName)\"? This cannot be undone.")
        }
    }

    private var aiModelWarning: some View {
        GroupBox {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.title2)
                    .foregroundColor(.orange)

                VStack(alignment: .leading, spacing: 4) {
                    Text("AI Model Required")
                        .font(.headline)
                    Text("Download and select an AI model in the AI Models section to use prompts.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(8)
        }
    }

    private func activePromptIndicator(_ prompt: Prompt) -> some View {
        GroupBox {
            HStack(spacing: 12) {
                Image(systemName: "text.bubble.fill")
                    .font(.title2)
                    .foregroundColor(.accentColor)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Active Prompt")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(prompt.displayName)
                        .font(.headline)
                }

                Spacer()

                Button("Deactivate") {
                    promptManager.deactivatePrompt()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(8)
        }
    }

    private func promptRow(_ prompt: Prompt) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(prompt.displayName)
                        .fontWeight(.medium)

                    if prompt.isModified {
                        Text("Modified")
                            .font(.caption2)
                            .foregroundColor(.orange)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.orange.opacity(0.2)))
                    }

                    if promptManager.isActive(prompt) {
                        Text("Active")
                            .font(.caption2)
                            .foregroundColor(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.accentColor))
                    }
                }

                Text(prompt.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("Trigger: \"\(prompt.name) prompt\"")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            HStack(spacing: 8) {
                // Activate/Deactivate button
                if promptManager.isActive(prompt) {
                    Button("Deactivate") {
                        promptManager.deactivatePrompt()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                } else {
                    Button("Activate") {
                        promptManager.activatePrompt(id: prompt.id)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!aiModelManager.isModelReady || !prompt.isEnabled)
                }

                // Visibility toggle (eye icon)
                Button {
                    promptManager.toggleEnabled(prompt)
                } label: {
                    Image(systemName: prompt.isEnabled ? "eye" : "eye.slash")
                        .foregroundColor(prompt.isEnabled ? .secondary : .red.opacity(0.6))
                }
                .buttonStyle(.borderless)
                .help(prompt.isEnabled ? "Hide from selector" : "Show in selector")

                // Edit button
                Button {
                    editingPrompt = prompt
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)

                // Reset or Delete button
                if prompt.isBuiltIn {
                    if prompt.isModified {
                        Button {
                            promptManager.resetToDefault(prompt)
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                        }
                        .buttonStyle(.borderless)
                        .help("Reset to default")
                    }
                } else {
                    Button(role: .destructive) {
                        promptToDelete = prompt
                        showDeleteConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .padding(.vertical, 8)
    }

    private var voiceActivationInfo: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Label("Voice Activation", systemImage: "mic")
                    .font(.headline)

                Text("Activate prompts by saying:")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 4) {
                    Text("\"[name] prompt\" - e.g., \"summarize prompt\"")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\"prompt [name]\" - e.g., \"prompt expand\"")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\"prompt off\" or \"clear prompt\" - deactivate")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.leading, 8)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Sheet for adding/editing prompts
struct PromptEditSheet: View {
    let prompt: Prompt?
    let onSave: (Prompt) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var displayName: String = ""
    @State private var description: String = ""
    @State private var promptText: String = ""

    init(prompt: Prompt?, onSave: @escaping (Prompt) -> Void) {
        self.prompt = prompt
        self.onSave = onSave

        if let prompt = prompt {
            _name = State(initialValue: prompt.name)
            _displayName = State(initialValue: prompt.displayName)
            _description = State(initialValue: prompt.description)
            _promptText = State(initialValue: prompt.promptText)
        }
    }

    var body: some View {
        VStack(spacing: 20) {
            Text(prompt == nil ? "Add Prompt" : "Edit Prompt")
                .font(.headline)

            VStack(alignment: .leading, spacing: 12) {
                if prompt == nil || !prompt!.isBuiltIn {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Name (for voice activation)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("e.g., summarize", text: $name)
                            .textFieldStyle(.roundedBorder)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Display Name")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("e.g., Summarize Text", text: $displayName)
                            .textFieldStyle(.roundedBorder)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Description")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("Brief description of what this prompt does", text: $description)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Prompt Text")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Use {input} as placeholder for the transcribed text")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                    TextEditor(text: $promptText)
                        .font(.system(.caption, design: .monospaced))
                        .frame(minHeight: 150, maxHeight: 200)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .background(Color(nsColor: .textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                        )
                }
            }

            // Preview
            GroupBox {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Preview with sample input")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(promptText.replacingOccurrences(of: "{input}", with: "Hello world"))
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .lineLimit(3)
                }
                .padding(4)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.bordered)

                Spacer()

                Button(prompt == nil ? "Add" : "Save") {
                    let newPrompt: Prompt
                    if let existing = prompt {
                        newPrompt = Prompt(
                            id: existing.id,
                            name: existing.isBuiltIn ? existing.name : name.lowercased().trimmingCharacters(in: .whitespaces),
                            displayName: existing.isBuiltIn ? existing.displayName : displayName,
                            description: existing.isBuiltIn ? existing.description : description,
                            promptText: promptText,
                            isBuiltIn: existing.isBuiltIn,
                            isModified: existing.isBuiltIn
                        )
                    } else {
                        newPrompt = Prompt(
                            name: name.lowercased().trimmingCharacters(in: .whitespaces),
                            displayName: displayName,
                            description: description,
                            promptText: promptText,
                            isBuiltIn: false
                        )
                    }
                    onSave(newPrompt)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isValid)
            }
        }
        .padding(24)
        .frame(width: 500)
    }

    private var isValid: Bool {
        if prompt?.isBuiltIn == true {
            return !promptText.isEmpty && promptText.contains("{input}")
        }
        return !name.isEmpty && !displayName.isEmpty && !promptText.isEmpty && promptText.contains("{input}")
    }
}

#Preview {
    PromptsSettingsView()
        .frame(width: 500, height: 700)
}
