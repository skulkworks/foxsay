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
        VStack(spacing: 24) {
            // Icon
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(.accentColor)

            // Title
            VStack(spacing: 8) {
                Text("Download Model")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("VoiceFox needs to download a speech recognition model to work offline.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            // Engine info
            VStack(spacing: 8) {
                Text(engineManager.currentEngineType.displayName)
                    .font(.headline)

                Text(engineManager.currentEngineType.description)
                    .font(.caption)
                    .foregroundColor(.secondary)

                let sizeBytes = engineManager.currentEngine?.modelSize ?? 0
                let sizeMB = Double(sizeBytes) / 1_000_000
                Text(String(format: "Size: %.0f MB", sizeMB))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(.textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Progress
            if isDownloading {
                VStack(spacing: 8) {
                    ProgressView(value: engineManager.downloadProgress)
                        .progressViewStyle(.linear)

                    Text("Downloading... \(Int(engineManager.downloadProgress * 100))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
            }

            // Error message
            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
            }

            // Success message
            if downloadComplete {
                Label("Download Complete", systemImage: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.headline)
            }

            Spacer()

            // Buttons
            HStack(spacing: 12) {
                if !downloadComplete {
                    Button("Skip") {
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                }

                if downloadComplete {
                    Button("Done") {
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                } else if isDownloading {
                    Button("Cancel") {
                        engineManager.cancelDownload()
                        isDownloading = false
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button("Download") {
                        startDownload()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(24)
        .frame(width: 400, height: 450)
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
