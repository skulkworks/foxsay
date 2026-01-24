import SwiftUI

/// Main content view for VoiceFox - minimal status display
public struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var audioEngine = AudioEngine.shared
    @ObservedObject private var engineManager = EngineManager.shared
    @ObservedObject private var hotkeyManager = HotkeyManager.shared
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
                    Image(systemName: "waveform.circle.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(.tint)

                    Text("VoiceFox")
                        .font(.title)
                        .fontWeight(.bold)
                }

                // Recording indicator
                recordingIndicator

                // Status pills
                HStack(spacing: 8) {
                    statusPill(
                        icon: audioEngine.hasPermission ? "mic.fill" : "mic.slash",
                        color: audioEngine.hasPermission ? .green : .orange
                    )

                    statusPill(
                        icon: HotkeyManager.checkAccessibilityPermission() ? "hand.raised.fill" : "hand.raised.slash",
                        color: HotkeyManager.checkAccessibilityPermission() ? .green : .orange
                    )

                    statusPill(
                        icon: engineManager.isModelReady ? "checkmark.circle.fill" : "arrow.down.circle",
                        color: engineManager.isModelReady ? .green : .orange
                    )
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
            return .red
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
        } else {
            return "Hold \(hotkeyManager.selectedModifier.displayName) to record"
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
}

#Preview {
    ContentView()
        .environmentObject(AppState.shared)
        .frame(width: 280, height: 300)
}
