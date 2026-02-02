import SwiftUI

/// Main dashboard view replacing StatusPaneView
public struct DashboardView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var statisticsManager = StatisticsManager.shared

    @State private var selectedPeriod: DashboardPeriod = .sixMonths

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                DashboardHeaderView()

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
