import SwiftUI

/// Row view for a single history item
public struct HistoryRowView: View {
    let item: HistoryItem
    @ObservedObject private var playbackManager = AudioPlaybackManager.shared

    public init(item: HistoryItem) {
        self.item = item
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header row
            HStack(spacing: 8) {
                // App badge
                if let appName = item.appName {
                    Text(appName)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(item.wasDevCorrected ? Color.purple.opacity(0.2) : Color.secondary.opacity(0.15))
                        .foregroundColor(item.wasDevCorrected ? .purple : .secondary)
                        .clipShape(Capsule())
                }

                // Timestamp
                Text(item.formattedTimestamp)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                Spacer()

                // Star indicator
                if item.isStarred {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundColor(.yellow)
                }

                // Duration
                Text(item.formattedDuration)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            // Text content
            Text(item.text)
                .font(.body)
                .lineLimit(3)
                .foregroundColor(.primary)

            // Audio playback controls (if audio available)
            if item.audioFileName != nil {
                audioControls
            }

            // Footer row
            HStack(spacing: 12) {
                // Processing time
                Label(item.formattedProcessingTime, systemImage: "bolt")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                Spacer()

                // Copy button
                Button {
                    copyToClipboard()
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help("Copy to clipboard")
            }
        }
        .padding(12)
        .background(Color(.textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private var audioControls: some View {
        let isCurrentItem = playbackManager.currentItemId == item.id

        HStack(spacing: 12) {
            // Play/Stop button
            Button {
                playbackManager.toggle(item)
            } label: {
                Image(systemName: isCurrentItem && playbackManager.isPlaying ? "stop.fill" : "play.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.accentColor)
                    .frame(width: 24, height: 24)
                    .background(Color.accentColor.opacity(0.15))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            // Progress slider
            if isCurrentItem {
                Slider(value: Binding(
                    get: { playbackManager.progress },
                    set: { playbackManager.seek(to: $0) }
                ))
                .controlSize(.small)

                // Time display
                Text(formatTime(playbackManager.progress * playbackManager.duration))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(width: 35, alignment: .trailing)
            } else {
                // Waveform placeholder when not playing
                HStack(spacing: 2) {
                    ForEach(0..<12, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color.secondary.opacity(0.3))
                            .frame(width: 3, height: CGFloat.random(in: 4...12))
                    }
                }
                .frame(height: 12)

                Spacer()
            }
        }
        .padding(.vertical, 4)
    }

    private func copyToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(item.text, forType: .string)
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

#Preview {
    VStack(spacing: 12) {
        HistoryRowView(item: HistoryItem(
            text: "This is a sample transcription that might be a bit longer to show how text wrapping works.",
            duration: 3.5,
            processingTime: 0.42,
            appName: "Xcode",
            wasDevCorrected: true,
            isStarred: true
        ))

        HistoryRowView(item: HistoryItem(
            text: "A shorter transcription.",
            duration: 1.2,
            processingTime: 0.15
        ))
    }
    .padding()
    .frame(width: 400)
}
