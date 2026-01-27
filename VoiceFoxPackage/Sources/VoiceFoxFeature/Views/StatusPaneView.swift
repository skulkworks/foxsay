import SwiftUI

/// Main status pane showing recording state and system status
public struct StatusPaneView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var audioEngine = AudioEngine.shared
    @ObservedObject private var modelManager = ModelManager.shared
    @ObservedObject private var hotkeyManager = HotkeyManager.shared
    @ObservedObject private var llmManager = LLMModelManager.shared

    public init() {}

    public var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // App icon and name
            VStack(spacing: 12) {
                Image("AppIconImage")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 96, height: 96)

                Text("VoiceFox")
                    .font(.largeTitle)
                    .fontWeight(.bold)
            }

            // Recording indicator
            recordingIndicator

            // System status cards
            systemStatusCards

            Spacer()

            // Hotkey reminder
            Text("Hold \(hotkeyManager.selectedModifier.displayName) to record")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.windowBackgroundColor))
    }

    // MARK: - Recording Indicator

    private var recordingIndicator: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(indicatorColor.opacity(0.15))
                    .frame(width: 100, height: 100)

                Circle()
                    .fill(indicatorColor.opacity(0.3))
                    .frame(width: 76, height: 76)
                    .scaleEffect(appState.isRecording ? 1.0 + CGFloat(audioEngine.audioLevel) * 0.3 : 1.0)
                    .animation(.easeInOut(duration: 0.1), value: audioEngine.audioLevel)

                Circle()
                    .fill(indicatorColor)
                    .frame(width: 56, height: 56)

                Image(systemName: indicatorIcon)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(.white)
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !appState.isRecording && !appState.isTranscribing {
                            Task {
                                await appState.startRecording()
                            }
                        }
                    }
                    .onEnded { _ in
                        if appState.isRecording {
                            Task {
                                await appState.stopRecordingAndTranscribe()
                            }
                        }
                    }
            )
            .help("Hold to record, release to transcribe")

            Text(indicatorText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var indicatorColor: Color {
        if appState.isRecording {
            return .tertiaryAccent
        } else if appState.isTranscribing {
            return .orange
        } else {
            return .gray
        }
    }

    private var indicatorIcon: String {
        if appState.isRecording {
            return "mic.fill"
        } else if appState.isTranscribing {
            return "waveform"
        } else {
            return "mic"
        }
    }

    private var indicatorText: String {
        if appState.isRecording {
            return "Recording..."
        } else if appState.isTranscribing {
            return "Transcribing..."
        } else if modelManager.isPreloading {
            return "Warming up model..."
        } else {
            return "Ready"
        }
    }

    // MARK: - System Status

    private var systemStatusCards: some View {
        HStack(spacing: 16) {
            // Microphone
            statusCard(
                title: "Microphone",
                icon: audioEngine.hasPermission ? "mic.fill" : "mic.slash",
                status: audioEngine.hasPermission ? "Ready" : "Permission needed",
                isReady: audioEngine.hasPermission
            ) {
                if !audioEngine.hasPermission {
                    Task {
                        await audioEngine.checkPermission()
                    }
                }
            }

            // Accessibility
            let hasAccessibility = HotkeyManager.checkAccessibilityPermission()
            statusCard(
                title: "Hotkey",
                icon: hasAccessibility ? "hand.raised.fill" : "hand.raised.slash",
                status: hasAccessibility ? "Enabled" : "Permission needed",
                isReady: hasAccessibility
            ) {
                if !hasAccessibility {
                    HotkeyManager.requestAccessibilityPermission()
                }
            }

            // Model
            statusCard(
                title: "Model",
                icon: modelStatusIcon,
                status: modelStatusText,
                isReady: modelManager.isModelLoaded
            ) {
                if !modelManager.isModelReady {
                    appState.selectedSidebarItem = .models
                }
            }
        }
        .padding(.horizontal, 32)
    }

    private var modelStatusIcon: String {
        if modelManager.isModelLoaded {
            return "checkmark.circle.fill"
        } else if modelManager.isPreloading {
            return "arrow.trianglehead.2.clockwise.rotate.90"
        } else if modelManager.isModelReady {
            return "hourglass"
        } else {
            return "arrow.down.circle"
        }
    }

    private var modelStatusText: String {
        if modelManager.isModelLoaded {
            return modelManager.currentModelType.shortName
        } else if modelManager.isPreloading {
            return "Loading..."
        } else if modelManager.isModelReady {
            return "Ready to load"
        } else {
            return "Download required"
        }
    }

    private func statusCard(title: String, icon: String, status: String, isReady: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundColor(isReady ? .secondaryAccent : .orange)

                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)

                Text(status)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: 100, height: 90)
            .background(Color(.textBackgroundColor).opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    StatusPaneView()
        .environmentObject(AppState.shared)
        .frame(width: 450, height: 500)
}
