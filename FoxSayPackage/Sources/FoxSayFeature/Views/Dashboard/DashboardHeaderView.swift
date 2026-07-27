import SwiftUI

/// Header component for the dashboard pane: title, one-line description, and
/// the current recording status.
struct DashboardHeaderView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var modelManager = ModelManager.shared

    @State private var showDebugMenu = false
    @State private var isPulsing = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Dashboard")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .onTapGesture {
                        #if DEBUG
                        if NSEvent.modifierFlags.contains(.option) {
                            showDebugMenu = true
                        }
                        #endif
                    }
                    .popover(isPresented: $showDebugMenu) {
                        debugMenuContent
                    }

                Text("Your dictation activity and system readiness at a glance.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            statusIndicator
        }
    }

    // MARK: - Status Indicator

    private var statusIndicator: some View {
        HStack(spacing: 6) {
            if modelManager.isPreloading && !isActive {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.65)
                    .frame(width: 12, height: 12)
            } else {
                StatusDot(color: statusColor)
                    .opacity(isActive && isPulsing ? 0.35 : 1)
                    .animation(
                        isActive
                            ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true)
                            : .easeOut(duration: 0.18),
                        value: isPulsing
                    )
            }

            Text(statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onAppear { isPulsing = isActive }
        .onChange(of: isActive) { _, active in
            isPulsing = active
        }
    }

    /// True while the app is actively capturing or processing speech.
    private var isActive: Bool {
        appState.isRecording || appState.isTranscribing
    }

    private var statusColor: Color {
        isActive ? .accentColor : .statusOK
    }

    private var statusText: String {
        if appState.isRecording {
            return "Recording"
        } else if appState.isTranscribing {
            return "Transcribing"
        } else if modelManager.isPreloading {
            return "Loading model…"
        } else {
            return "Ready"
        }
    }

    // MARK: - Debug Menu (DEBUG builds only)

    #if DEBUG
    private var debugMenuContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Debug Options")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .padding(.bottom, 4)

            Button {
                StatisticsManager.shared.generateDemoData()
                showDebugMenu = false
            } label: {
                Label("Generate Demo Data", systemImage: "sparkles")
            }
            .buttonStyle(.plain)

            Button {
                StatisticsManager.shared.clearAllData()
                showDebugMenu = false
            } label: {
                Label("Clear Statistics", systemImage: "trash")
            }
            .buttonStyle(.plain)

            Divider()

            Button {
                StatisticsManager.shared.backfillFromHistory(HistoryManager.shared.items)
                showDebugMenu = false
            } label: {
                Label("Backfill from History", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.plain)
        }
        .padding()
        .frame(width: 200)
    }
    #else
    private var debugMenuContent: some View {
        EmptyView()
    }
    #endif
}

#Preview {
    DashboardHeaderView()
        .environmentObject(AppState.shared)
        .padding()
        .frame(width: 400)
}
