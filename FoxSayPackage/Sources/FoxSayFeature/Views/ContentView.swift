import SwiftUI

/// Main content view for FoxSay - minimal status display
public struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var audioEngine = AudioEngine.shared
    @ObservedObject private var engineManager = EngineManager.shared
    @ObservedObject private var hotkeyManager = HotkeyManager.shared
    @ObservedObject private var aiModelManager = AIModelManager.shared
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
                        color: audioEngine.hasPermission ? .accentColor : .statusWarning
                    )

                    statusPill(
                        icon: HotkeyManager.checkAccessibilityPermission() ? "doc.on.clipboard.fill" : "doc.on.clipboard",
                        color: HotkeyManager.checkAccessibilityPermission() ? .accentColor : .statusWarning
                    )

                    engineStatusPill

                    // AI Model status pill
                    if aiModelManager.selectedModelId != nil {
                        aiModelStatusPill
                    }
                }
                .id(permissionRefreshID)  // Force refresh when ID changes
            }

            Spacer()

            Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                .font(.caption2)
                .foregroundStyle(.quaternary)
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
                    .foregroundStyle(isActive ? Color.white : Color.secondary)
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

    /// True while the app is actively capturing or processing speech.
    private var isActive: Bool {
        appState.isRecording || appState.isTranscribing
    }

    private var indicatorColor: Color {
        isActive ? .accentColor : Color.primary.opacity(0.25)
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
            return "Recording…"
        } else if appState.isTranscribing {
            return "Transcribing…"
        } else if engineManager.isPreloading {
            return "Warming up…"
        } else {
            return "Hold \(hotkeyManager.selectedModifier.displayName) to record"
        }
    }

    private var engineStatusIcon: String {
        if engineManager.isEngineReady {
            return "checkmark.circle.fill"
        } else if engineManager.isModelReady {
            return "hourglass"
        } else {
            return "arrow.down.circle"
        }
    }

    private var engineStatusColor: Color {
        engineManager.isEngineReady ? .accentColor : .secondary
    }

    private func statusPill(icon: String, color: Color) -> some View {
        Image(systemName: icon)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(color)
            .frame(width: 28, height: 28)
            .background(Circle().fill(color.opacity(0.12)))
    }

    private var loadingPill: some View {
        ProgressView()
            .controlSize(.small)
            .scaleEffect(0.7)
            .frame(width: 28, height: 28)
            .background(Circle().fill(Color.primary.opacity(0.06)))
    }

    @ViewBuilder
    private var engineStatusPill: some View {
        if engineManager.isPreloading {
            loadingPill
        } else {
            statusPill(icon: engineStatusIcon, color: engineStatusColor)
        }
    }

    // MARK: - AI Model Status

    private var aiModelStatusIcon: String {
        if aiModelManager.isModelLoaded || aiModelManager.isModelReady {
            return "brain"
        } else {
            return "arrow.down.circle"
        }
    }

    private var aiModelStatusColor: Color {
        aiModelManager.isModelLoaded ? .accentColor : .secondary
    }

    @ViewBuilder
    private var aiModelStatusPill: some View {
        if aiModelManager.isPreloading {
            loadingPill
        } else {
            statusPill(icon: aiModelStatusIcon, color: aiModelStatusColor)
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState.shared)
        .frame(width: 280, height: 300)
}
