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
            VStack(spacing: 24) {
                // Header
                DashboardHeaderView()

                // Hotkey indicator
                hotkeyIndicator

                // Activity Section
                activitySection

                // Stats Grid
                statsSection

                // System Status Section
                systemStatusSection

                // Footer
                DashboardFooterView()
            }
            .padding(24)
        }
        .background(Color(.windowBackgroundColor))
    }

    // MARK: - Hotkey Indicator

    private var hotkeyIndicator: some View {
        HStack(spacing: 12) {
            // Recording hotkey - clickable
            Button {
                appState.selectedSidebarItem = .general
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.dashboardOrange)

                    Text("Record")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)

                    Text(hotkeyManager.selectedModifier.shortName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.primary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.dashboardOrange.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Click to change recording hotkey")

            Spacer()

            // Prompts hotkey (if enabled) - clickable
            if hotkeyManager.promptSelectorEnabled {
                Button {
                    appState.selectedSidebarItem = .general
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "text.bubble.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.dashboardPurple)

                        Text("Prompts")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)

                        Text(hotkeyManager.promptSelectorModifier.shortName)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.primary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.dashboardPurple.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Click to change prompts hotkey")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.textBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Activity Section

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Activity")
                    .font(.headline)
                    .fontWeight(.semibold)

                Spacer()

                PeriodSelectorView(selectedPeriod: $selectedPeriod)
            }

            // Activity grid card
            VStack(alignment: .leading, spacing: 16) {
                ActivityGridView(
                    gridData: dashboardData.gridData,
                    period: selectedPeriod
                )
            }
            .padding(16)
            .background(Color(.textBackgroundColor).opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Stats Section

    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Statistics")
                .font(.headline)
                .fontWeight(.semibold)

            StatsGridView(data: dashboardData)
        }
    }

    // MARK: - System Status Section

    private var systemStatusSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("System Status")
                .font(.headline)
                .fontWeight(.semibold)

            SystemStatusGridView()
        }
    }

    // MARK: - Data

    private var dashboardData: DashboardDisplayData {
        statisticsManager.getDashboardData(period: selectedPeriod)
    }
}

#Preview {
    DashboardView()
        .environmentObject(AppState.shared)
        .frame(width: 500, height: 700)
}
