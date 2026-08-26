import SwiftUI

/// View for downloading the transcription model
public struct ModelDownloadView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var engineManager = EngineManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var isDownloading = false
    @State private var downloadComplete = false
    @State private var errorMessage: String?

    public init() {}

    public var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Color.accentColor)
                .padding(.top, 8)

            VStack(spacing: 6) {
                Text("Download Model")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("FoxSay needs a speech recognition model to transcribe offline.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            // Engine info
            VStack(spacing: 6) {
                Text(engineManager.currentEngineType.displayName)
                    .font(.headline)

                Text(engineManager.currentEngineType.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                let sizeBytes = engineManager.currentEngine?.modelSize ?? 0
                let sizeMB = Double(sizeBytes) / 1_000_000
                Text(String(format: "%.0f MB", sizeMB))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity)
            .cardSurface()

            // Progress
            if isDownloading {
                VStack(spacing: 6) {
                    ProgressView(value: engineManager.downloadProgress)
                        .progressViewStyle(.linear)

                    // Before the first byte lands there is nothing honest to put
                    // a percentage on — the repository listing takes a few
                    // seconds on its own.
                    Text(
                        engineManager.downloadProgress > 0
                            ? "Downloading… \(Int(engineManager.downloadProgress * 100))%"
                            : "Preparing…"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                    Button("Cancel") {
                        engineManager.cancelDownload()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            // Error message
            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(Color.statusError)
                    .multilineTextAlignment(.center)
            }

            // Success message
            if downloadComplete {
                Label("Download complete", systemImage: "checkmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(Color.statusOK)
            }

            Spacer()

            // Buttons
            HStack(spacing: 10) {
                Spacer()

                if downloadComplete {
                    Button("Done") {
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                } else if isDownloading {
                    Button("Cancel") {
                        engineManager.cancelDownload()
                        isDownloading = false
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button("Skip") {
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.cancelAction)

                    Button("Download") {
                        startDownload()
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(24)
        .frame(width: 420, height: 450)
    }

    private func startDownload() {
        isDownloading = true
        errorMessage = nil

        Task {
            do {
                try await engineManager.downloadCurrentModel()
                await MainActor.run {
                    isDownloading = false
                    downloadComplete = true
                }
            } catch is CancellationError {
                // Stopped on purpose — back to the Download button, no error.
                await MainActor.run {
                    isDownloading = false
                }
            } catch {
                await MainActor.run {
                    isDownloading = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

#Preview {
    ModelDownloadView()
        .environmentObject(AppState.shared)
}
