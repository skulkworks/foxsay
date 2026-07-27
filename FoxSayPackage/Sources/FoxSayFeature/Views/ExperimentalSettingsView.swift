import SwiftUI

/// Experimental features settings view
public struct ExperimentalSettingsView: View {
    @ObservedObject private var modeManager = VoiceModeManager.shared

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SettingsPaneHeader(
                    "Text Transforms",
                    description: "Experimental formatting features — these may change or be removed in future updates."
                )

                markdownModeSection

                Spacer()
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Markdown Mode Section

    private var markdownModeSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header with toggle
            HStack {
                SettingsSectionHeader("Markdown Mode", systemImage: "text.badge.checkmark")

                Spacer()

                Toggle("", isOn: $modeManager.markdownModeEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }

            Divider()

            Text("Voice commands are converted to markdown syntax — useful when dictating into Obsidian, Notion, or a code editor.")
                .font(.callout)
                .foregroundStyle(.secondary)

            // How to use
            VStack(alignment: .leading, spacing: 7) {
                Text("How to Use")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                VStack(alignment: .leading, spacing: 5) {
                    bulletPoint("Toggle with the switch above")
                    bulletPoint("Say \"markdown mode\" or \"markdown on\" to enable")
                    bulletPoint("Say \"markdown off\" or \"plain text\" to disable")
                    bulletPoint("Select from the prompt selector overlay")
                }
            }

            // Voice commands
            VStack(alignment: .leading, spacing: 7) {
                Text("Example Voice Commands")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                VStack(alignment: .leading, spacing: 5) {
                    commandExample("\"bold on text bold off\"", "**text**")
                    commandExample("\"italic on text italic off\"", "*text*")
                    commandExample("\"h1 my title\"", "# my title")
                    commandExample("\"bullet item\"", "- item")
                    commandExample("\"code on func code off\"", "`func`")
                    commandExample("\"checkbox task\"", "- [ ] task")
                }

                Text("See the full command reference in Docs/MarkdownVoiceCommands.md")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 2)
            }

            Divider()

            StatusCaption(
                text: modeManager.markdownModeEnabled ? "Markdown mode is active" : "Markdown mode is off",
                color: modeManager.markdownModeEnabled ? .statusOK : .secondary,
                emphasized: modeManager.markdownModeEnabled
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private func bulletPoint(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("•")
                .foregroundStyle(.tertiary)
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func commandExample(_ voice: String, _ output: String) -> some View {
        HStack(spacing: 10) {
            Text(voice)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 190, alignment: .leading)

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
