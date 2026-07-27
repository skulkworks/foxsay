import SwiftUI

/// Main dashboard view replacing StatusPaneView
public struct DashboardView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var statisticsManager = StatisticsManager.shared
    @ObservedObject private var hotkeyManager = HotkeyManager.shared

    @State private var selectedPeriod: DashboardPeriod = .sixMonths

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                DashboardHeaderView()

                hotkeyIndicator

                activitySection

                statsSection

                systemStatusSection

                DashboardFooterView()
                    .padding(.top, 4)
            }
            .padding(24)
        }
        .background(Color(.windowBackgroundColor))
    }

    // MARK: - Hotkey Indicator

    private var hotkeyIndicator: some View {
        HStack(spacing: 12) {
            HotkeyChip(
                icon: "mic",
                label: "Record",
                key: hotkeyManager.selectedModifier.shortName,
                help: "Click to change recording hotkey"
            ) {
                appState.selectedSidebarItem = .general
            }

            Spacer()

            if hotkeyManager.promptSelectorEnabled {
                HotkeyChip(
                    icon: "text.bubble",
                    label: "Prompts",
                    key: hotkeyManager.promptSelectorModifier.shortName,
                    help: "Click to change prompts hotkey"
                ) {
                    appState.selectedSidebarItem = .general
                }
            }
        }
        .cardSurface(padding: 12)
    }

    // MARK: - Activity Section

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Activity")
                    .font(.headline)

                Spacer()

                PeriodSelectorView(selectedPeriod: $selectedPeriod)
            }

            ActivityGridView(
                gridData: dashboardData.gridData,
                period: selectedPeriod
            )
            .cardSurface()
        }
    }

    // MARK: - Stats Section

    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Statistics")
                .font(.headline)

            StatsGridView(data: dashboardData)
        }
    }

    // MARK: - System Status Section

    private var systemStatusSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("System Status")
                .font(.headline)

            SystemStatusGridView()
        }
    }

    // MARK: - Data

    private var dashboardData: DashboardDisplayData {
        statisticsManager.getDashboardData(period: selectedPeriod)
    }
}

// MARK: - Hotkey Chip

/// A clickable "label + keycap" pair. Neutral at rest, accent-tinted on hover
/// so it reads as interactive without adding a second color to the pane.
private struct HotkeyChip: View {
    let icon: String
    let label: String
    let key: String
    let help: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundStyle(isHovering ? Color.accentColor : Color.secondary)

                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)

                KeycapLabel(text: key, tinted: isHovering)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.18)) {
                isHovering = hovering
            }
        }
    }
}

#Preview {
    DashboardView()
        .environmentObject(AppState.shared)
        .frame(width: 500, height: 700)
}
