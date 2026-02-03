import SwiftUI
import AppKit

/// Main status pane showing recording state and system status
public struct StatusPaneView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var audioEngine = AudioEngine.shared
    @ObservedObject private var modelManager = ModelManager.shared
    @ObservedObject private var hotkeyManager = HotkeyManager.shared
    @ObservedObject private var aiModelManager = AIModelManager.shared
    @ObservedObject private var promptManager = PromptManager.shared
    @ObservedObject private var providerManager = LLMProviderManager.shared

    public init() {}

    public var body: some View {
        VStack(spacing: 32) {
            Spacer()
                .frame(maxHeight: 40)

            // App icon and name
            VStack(spacing: 12) {
                Image("AppIconImage")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 96, height: 96)

                Text("FoxSay")
                    .font(.largeTitle)
                    .fontWeight(.bold)
            }

            // Recording indicator
            recordingIndicator

            // System status cards
            systemStatusCards

            // Active prompt info
            if let activePrompt = promptManager.activePrompt {
                activePromptInfo(activePrompt)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottom) {
            // Hotkey reminder pinned to bottom
            Text("Hold \(hotkeyManager.selectedModifier.displayName) to record")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.bottom, 8)
        }
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
        HStack(spacing: 12) {
            // Microphone
            statusCard(
                title: "Microphone",
                icon: audioEngine.hasPermission ? "mic.fill" : "mic.slash",
                status: audioEngine.hasPermission ? "Ready" : "Permission",
                isReady: audioEngine.hasPermission,
                isLoading: false
            ) {
                if audioEngine.hasPermission {
                    // Open System Settings > Privacy & Security > Microphone
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                        NSWorkspace.shared.open(url)
                    }
                } else {
                    Task {
                        await audioEngine.checkPermission()
                    }
                }
            }

            // Auto-paste (requires Accessibility for text injection)
            let hasAccessibility = HotkeyManager.checkAccessibilityPermission()
            statusCard(
                title: "Auto-Paste",
                icon: hasAccessibility ? "doc.on.clipboard.fill" : "doc.on.clipboard",
                status: hasAccessibility ? "Enabled" : "Permission",
                isReady: hasAccessibility,
                isLoading: false
            ) {
                // Always request/re-request accessibility - handles both initial setup and re-adding
                HotkeyManager.requestAccessibilityPermission()
            }

            // Speech Model
            statusCard(
                title: "Speech",
                icon: modelStatusIcon,
                status: modelStatusText,
                isReady: modelManager.isModelLoaded,
                isLoading: modelManager.isPreloading
            ) {
                appState.selectedSidebarItem = .models
            }

            // AI Model
            statusCard(
                title: "AI",
                icon: aiModelStatusIcon,
                status: aiModelStatusText,
                isReady: aiModelReady,
                isLoading: aiModelManager.isPreloading
            ) {
                appState.selectedSidebarItem = .aiModels
            }
        }
        .padding(.horizontal, 24)
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
            return "Ready"
        } else {
            return "Download"
        }
    }

    private var aiModelStatusIcon: String {
        // Check remote provider first
        if providerManager.providerType == .remote && providerManager.isRemoteReady {
            return "globe"
        }
        // Then check local
        if aiModelManager.isModelLoaded {
            return "brain"
        } else if aiModelManager.isPreloading {
            return "arrow.trianglehead.2.clockwise.rotate.90"
        } else if aiModelManager.isModelReady {
            return "brain"
        } else {
            return "arrow.down.circle"
        }
    }

    private var aiModelStatusText: String {
        // Check remote provider first
        if providerManager.providerType == .remote && providerManager.isRemoteReady,
           let provider = providerManager.selectedRemoteProvider {
            return provider.name
        }
        // Then check local
        if aiModelManager.isModelLoaded, let model = aiModelManager.selectedModel {
            return model.shortName
        } else if aiModelManager.isPreloading {
            return "Loading..."
        } else if aiModelManager.isModelReady {
            return "Ready"
        } else if aiModelManager.selectedModelId != nil {
            return "Download"
        } else {
            return "Download"
        }
    }

    private var aiModelReady: Bool {
        // Remote provider is ready
        if providerManager.providerType == .remote && providerManager.isRemoteReady {
            return true
        }
        // Local model is loaded
        return aiModelManager.isModelLoaded
    }

    private func activePromptInfo(_ prompt: Prompt) -> some View {
        Button {
            appState.selectedSidebarItem = .prompts
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "text.bubble.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text("AI Prompt")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(prompt.displayName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(width: 376) // Match width of 4 status cards (4×85 + 3×12)
            .background(Color(.textBackgroundColor).opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private func statusCard(title: String, icon: String, status: String, isReady: Bool, isLoading: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                if isLoading {
                    SpinningIcon(icon: icon)
                        .frame(height: 28)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 24))
                        .foregroundColor(isReady ? .accentColor : .secondary)
                        .frame(height: 28)
                }

                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text(status)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(width: 85, height: 85)
            .background(Color(.textBackgroundColor).opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

/// Spinning icon for loading states using TimelineView for reliable animation
private struct SpinningIcon: View {
    let icon: String

    var body: some View {
        TimelineView(.animation) { timeline in
            let rotation = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.0) * 360

            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(.accentColor)
                .rotationEffect(.degrees(rotation))
        }
    }
}

#Preview {
    StatusPaneView()
        .environmentObject(AppState.shared)
        .frame(width: 450, height: 500)
}
