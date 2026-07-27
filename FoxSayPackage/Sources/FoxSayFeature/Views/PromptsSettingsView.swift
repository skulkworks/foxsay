import SwiftUI

/// Prompts settings view for managing the prompt library
public struct PromptsSettingsView: View {
    @ObservedObject private var promptManager = PromptManager.shared
    @ObservedObject private var providerManager = LLMProviderManager.shared

    @State private var showAddPromptSheet = false
    @State private var editingPrompt: Prompt?
    @State private var showDeleteConfirmation = false
    @State private var promptToDelete: Prompt?

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SettingsPaneHeader(
                    "Prompts",
                    description: "Transform transcribed text with AI, on demand or by voice."
                )

                // AI model requirement warning
                if !providerManager.isReady {
                    SettingsWarningBanner(
                        title: "AI provider required",
                        message: "Select a local model or remote provider in AI Models to use prompts."
                    )
                }

                // Active prompt indicator
                if let activePrompt = promptManager.activePrompt {
                    activePromptIndicator(activePrompt)
                }

                // Built-in prompts
                VStack(alignment: .leading, spacing: 10) {
                    SettingsSectionHeader("Built-in Prompts", systemImage: "sparkles")

                    VStack(spacing: 8) {
                        ForEach(promptManager.builtInPrompts) { prompt in
                            promptRow(prompt)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Custom prompts
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        SettingsSectionHeader("Custom Prompts", systemImage: "person")

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
                        Text("No custom prompts yet. Add your own to create custom text transformations.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 4)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(promptManager.customPrompts) { prompt in
                                promptRow(prompt)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

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

    private func activePromptIndicator(_ prompt: Prompt) -> some View {
        HStack(spacing: 12) {
            IconTile(systemName: "text.bubble", isActive: true)

            VStack(alignment: .leading, spacing: 3) {
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private func promptRow(_ prompt: Prompt) -> some View {
        let isActive = promptManager.isActive(prompt)

        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(prompt.displayName)
                        .fontWeight(.medium)

                    if isActive {
                        ChipLabel(text: "Active", tinted: true)
                    }

                    if prompt.isModified {
                        ChipLabel(text: "Modified")
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

            HStack(spacing: 2) {
                // Activate / deactivate
                if isActive {
                    Button {
                        promptManager.deactivatePrompt()
                    } label: {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 20, height: 20)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .help("Deactivate this prompt")
                } else if prompt.isEnabled {
                    RowActionButton("circle", help: "Activate this prompt") {
                        promptManager.activatePrompt(id: prompt.id)
                    }
                }

                // Visibility toggle
                RowActionButton(
                    prompt.isEnabled ? "eye" : "eye.slash",
                    help: prompt.isEnabled ? "Hide from the prompt selector" : "Show in the prompt selector"
                ) {
                    promptManager.toggleEnabled(prompt)
                }

                RowActionButton("pencil", help: "Edit prompt") {
                    editingPrompt = prompt
                }

                // Reset or delete
                if prompt.isBuiltIn {
                    if prompt.isModified {
                        RowActionButton("arrow.counterclockwise", help: "Reset to default") {
                            promptManager.resetToDefault(prompt)
                        }
                    }
                } else {
                    RowActionButton("trash", help: "Delete prompt", role: .destructive) {
                        promptToDelete = prompt
                        showDeleteConfirmation = true
                    }
                }
            }
        }
        .opacity(prompt.isEnabled ? 1 : 0.55)
        .selectableCard(isSelected: isActive, padding: 12)
        .contentShape(Rectangle())
        .onTapGesture {
            if prompt.isEnabled {
                if isActive {
                    promptManager.deactivatePrompt()
                } else {
                    promptManager.activatePrompt(id: prompt.id)
                }
            }
        }
    }

    private var voiceActivationInfo: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsSectionHeader("Voice Activation", systemImage: "mic")

            Text("Activate prompts by saying:")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text("\"[name] prompt\" — e.g. \"summarize prompt\"")
                Text("\"prompt [name]\" — e.g. \"prompt expand\"")
                Text("\"prompt off\" or \"clear prompt\" to deactivate")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.leading, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
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
        VStack(spacing: 0) {
            SheetHeader(
                title: prompt == nil ? "Add Prompt" : "Edit Prompt",
                subtitle: "Use {input} where the transcribed text should go."
            )

            Divider()

            Form {
                if prompt == nil || !prompt!.isBuiltIn {
                    Section("Details") {
                        TextField("Name", text: $name, prompt: Text("e.g., summarize"))
                        TextField("Display Name", text: $displayName, prompt: Text("e.g., Summarize Text"))
                        TextField("Description", text: $description, prompt: Text("What this prompt does"))
                    }
                }

                Section("Prompt Text") {
                    TextEditor(text: $promptText)
                        .font(.system(.caption, design: .monospaced))
                        .frame(minHeight: 140, maxHeight: 180)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.primary.opacity(0.05))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                        )
                }

                Section("Preview With Sample Input") {
                    Text(promptText.replacingOccurrences(of: "{input}", with: "Hello world"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .formStyle(.grouped)

            Divider()

            SheetFooter(
                confirmTitle: prompt == nil ? "Add" : "Save",
                isConfirmDisabled: !isValid,
                onCancel: { dismiss() }
            ) {
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
        }
        .frame(minWidth: 460, idealWidth: 500, minHeight: 460, idealHeight: 520)
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
