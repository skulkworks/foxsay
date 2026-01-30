import SwiftUI

/// Experimental features settings view
public struct ExperimentalSettingsView: View {
    @ObservedObject private var modeManager = VoiceModeManager.shared

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                HStack {
                    Text("Text Transforms")
                        .font(.title2)
                        .fontWeight(.bold)

                    Image(systemName: "flask")
                        .foregroundStyle(.secondary)
                }

                Text("Features in this section are experimental and may change or be removed in future updates.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                // Markdown Mode Section
                markdownModeSection

                Spacer()
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Markdown Mode Section

    private var markdownModeSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                // Header with toggle
                HStack {
                    Label("Markdown Mode", systemImage: "text.badge.checkmark")
                        .font(.headline)

                    Spacer()

                    Toggle("", isOn: $modeManager.markdownModeEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }

                Divider()

                // Description
                VStack(alignment: .leading, spacing: 12) {
                    Text("When enabled, voice commands are converted to markdown syntax. This is useful when dictating into markdown-aware editors like Obsidian, Notion, or code editors.")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    // How to use
                    VStack(alignment: .leading, spacing: 8) {
                        Text("How to Use")
                            .font(.subheadline)
                            .fontWeight(.semibold)

                        VStack(alignment: .leading, spacing: 6) {
                            bulletPoint("Toggle with the switch above")
                            bulletPoint("Say \"markdown mode\" or \"markdown on\" to enable")
                            bulletPoint("Say \"markdown off\" or \"plain text\" to disable")
                            bulletPoint("Select from the prompt selector overlay")
                        }
                    }

                    // Voice commands
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Example Voice Commands")
                            .font(.subheadline)
                            .fontWeight(.semibold)

                        VStack(alignment: .leading, spacing: 4) {
                            commandExample("\"bold on text bold off\"", "**text**")
                            commandExample("\"italic on text italic off\"", "*text*")
                            commandExample("\"h1 my title\"", "# my title")
                            commandExample("\"bullet item\"", "- item")
                            commandExample("\"code on func code off\"", "`func`")
                            commandExample("\"checkbox task\"", "- [ ] task")
                        }

                        Text("See full command reference in Docs/MarkdownVoiceCommands.md")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .padding(.top, 4)
                    }

                    // Status indicator
                    HStack(spacing: 8) {
                        Circle()
                            .fill(modeManager.markdownModeEnabled ? Color.accentColor : Color.secondary)
                            .frame(width: 8, height: 8)

                        Text(modeManager.markdownModeEnabled ? "Markdown mode is active" : "Markdown mode is off")
                            .font(.caption)
                            .foregroundStyle(modeManager.markdownModeEnabled ? .primary : .secondary)
                    }
                    .padding(.top, 4)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func bulletPoint(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
                .foregroundStyle(.secondary)
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func commandExample(_ voice: String, _ output: String) -> some View {
        HStack(spacing: 8) {
            Text(voice)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 180, alignment: .leading)

            Image(systemName: "arrow.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            Text(output)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.primary)
        }
    }
}

#Preview {
    ExperimentalSettingsView()
        .frame(width: 450, height: 600)
}
