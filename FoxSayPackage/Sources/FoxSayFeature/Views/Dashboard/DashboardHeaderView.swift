import SwiftUI

/// Header component showing app icon, name, version, and status
struct DashboardHeaderView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var modelManager = ModelManager.shared

    @State private var showDebugMenu = false

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Dashboard")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("v\(appVersion)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
            }

            Spacer()

            // Status badge
            statusBadge
        }
    }

    // MARK: - Status Badge

    private var statusBadge: some View {
        HStack(spacing: 6) {
            // Pulsing status dot
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
                .overlay {
                    if appState.isRecording || appState.isTranscribing {
                        Circle()
                            .stroke(statusColor.opacity(0.5), lineWidth: 2)
                            .scaleEffect(pulseAnimation ? 1.8 : 1.0)
                            .opacity(pulseAnimation ? 0 : 0.8)
                    }
                }

            Text(statusText)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(statusColor)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(statusColor.opacity(0.1))
        .clipShape(Capsule())
        .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: pulseAnimation)
        .onAppear {
            pulseAnimation = true
        }
    }

    @State private var pulseAnimation = false

    private var statusColor: Color {
        if appState.isRecording {
            return .dashboardOrange
        } else if appState.isTranscribing {
            return .dashboardAmber
        } else if modelManager.isPreloading {
            return .dashboardBlue
        } else {
            return .dashboardBlue  // Ready state is blue
        }
    }

    private var statusText: String {
        if appState.isRecording {
            return "Recording"
        } else if appState.isTranscribing {
            return "Transcribing"
        } else if modelManager.isPreloading {
            return "Loading..."
        } else {
            return "Ready"
        }
    }

    // MARK: - Version

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
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
