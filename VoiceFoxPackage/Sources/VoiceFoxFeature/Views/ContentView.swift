import SwiftUI

/// Main content view for VoiceFox - minimal status display
public struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var audioEngine = AudioEngine.shared
    @ObservedObject private var engineManager = EngineManager.shared
    @ObservedObject private var hotkeyManager = HotkeyManager.shared
    @ObservedObject private var llmManager = LLMModelManager.shared
    @Environment(\.scenePhase) private var scenePhase

    @State private var permissionRefreshID = UUID()

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Header with settings button
            HStack {
                Spacer()
                Button {
                    appState.showSettings = true
                } label: {
                    Image(systemName: "gear")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Settings")
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            Spacer()

            // Main content
            VStack(spacing: 20) {
                // App icon and name
                VStack(spacing: 8) {
                    Image("AppIconImage")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 72, height: 72)

                    Text("FoxSay")
                        .font(.title)
                        .fontWeight(.bold)
                }

                // Recording indicator
                recordingIndicator

                // Status pills
                HStack(spacing: 8) {
                    statusPill(
                        icon: audioEngine.hasPermission ? "mic.fill" : "mic.slash",
                        color: audioEngine.hasPermission ? .secondaryAccent : .orange
                    )

                    statusPill(
                        icon: HotkeyManager.checkAccessibilityPermission() ? "doc.on.clipboard.fill" : "doc.on.clipboard",
                        color: HotkeyManager.checkAccessibilityPermission() ? .secondaryAccent : .orange
                    )

                    engineStatusPill

                    // LLM status pill (only show if LLM is enabled)
                    if llmManager.isEnabled {
                        llmStatusPill
                    }
                }
                .id(permissionRefreshID)  // Force refresh when ID changes
            }

            Spacer()

            // Version
            Text("Version 1.0.0")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.windowBackgroundColor))
        .onAppear {
            refreshPermissions()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                refreshPermissions()
            }
        }
        .sheet(isPresented: $appState.showSettings, onDismiss: {
            refreshPermissions()
        }) {
            SettingsView()
                .environmentObject(appState)
        }
    }

    private func refreshPermissions() {
        audioEngine.updatePermissionStatus()
        Task {
            await engineManager.refreshModelReadyState()
        }
        // Force view refresh
        permissionRefreshID = UUID()
    }

    private var recordingIndicator: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(indicatorColor.opacity(0.15))
                    .frame(width: 80, height: 80)

                Circle()
                    .fill(indicatorColor.opacity(0.3))
                    .frame(width: 60, height: 60)
                    .scaleEffect(appState.isRecording ? 1.0 + CGFloat(audioEngine.audioLevel) * 0.3 : 1.0)
                    .animation(.easeInOut(duration: 0.1), value: audioEngine.audioLevel)

                Circle()
                    .fill(indicatorColor)
                    .frame(width: 44, height: 44)

                Image(systemName: indicatorIcon)
                    .font(.system(size: 20, weight: .medium))
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
                .font(.caption)
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
        } else if engineManager.isPreloading {
            return "Warming up..."
        } else {
            return "Hold \(hotkeyManager.selectedModifier.displayName) to record"
        }
    }

    private var engineStatusIcon: String {
        if engineManager.isEngineReady {
            return "checkmark.circle.fill"
        } else if engineManager.isPreloading {
            return "arrow.trianglehead.2.clockwise.rotate.90"
        } else if engineManager.isModelReady {
            return "hourglass"
        } else {
            return "arrow.down.circle"
        }
    }

    private var engineStatusColor: Color {
        if engineManager.isEngineReady {
            return .secondaryAccent
        } else if engineManager.isPreloading || engineManager.isModelReady {
            return .accentColor
        } else {
            return .orange
        }
    }

    private func statusPill(icon: String, color: Color) -> some View {
        Image(systemName: icon)
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(color)
            .frame(width: 28, height: 28)
            .background(color.opacity(0.15))
            .clipShape(Circle())
    }

    @ViewBuilder
    private var engineStatusPill: some View {
        if engineManager.isPreloading {
            SpinningIconView(icon: engineStatusIcon, color: engineStatusColor)
        } else {
            statusPill(icon: engineStatusIcon, color: engineStatusColor)
        }
    }

    // MARK: - LLM Status

    private var llmStatusIcon: String {
        if llmManager.isLoaded {
            return "brain"
        } else if llmManager.isPreloading {
            return "arrow.trianglehead.2.clockwise.rotate.90"
        } else if llmManager.isModelReady {
            return "brain"
        } else {
            return "arrow.down.circle"
        }
    }

    private var llmStatusColor: Color {
        if llmManager.isLoaded {
            return .secondaryAccent
        } else if llmManager.isPreloading || llmManager.isModelReady {
            return .accentColor
        } else {
            return .orange
        }
    }

    @ViewBuilder
    private var llmStatusPill: some View {
        if llmManager.isPreloading {
            SpinningIconView(icon: llmStatusIcon, color: llmStatusColor)
        } else {
            statusPill(icon: llmStatusIcon, color: llmStatusColor)
        }
    }
}

/// Separate view for spinning animation - animation stops when view is removed
struct SpinningIconView: View {
    let icon: String
    let color: Color
    @State private var rotation: Double = 0

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(color)
            .rotationEffect(.degrees(rotation))
            .frame(width: 28, height: 28)
            .background(color.opacity(0.15))
            .clipShape(Circle())
            .onAppear {
                withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState.shared)
        .frame(width: 280, height: 300)
}
