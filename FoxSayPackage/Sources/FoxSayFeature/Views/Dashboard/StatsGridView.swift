import SwiftUI

/// Grid of statistics cards
struct StatsGridView: View {
    let data: DashboardDisplayData

    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible())
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            StatCardView(
                icon: "mic.fill",
                value: formatNumber(data.aggregates.totalSessions),
                label: "Sessions",
                trend: data.sessionTrendText
            )

            StatCardView(
                icon: "text.bubble.fill",
                value: formatNumber(data.aggregates.totalWords),
                label: "Words",
                trend: data.wordsTrendText
            )

            StatCardView(
                icon: "clock.fill",
                value: formatTimeSaved(data.aggregates.timeSavedMinutes),
                label: "Time Saved",
                trend: data.timeSavedTrendText
            )

            StatCardView(
                icon: "checkmark.seal.fill",
                value: formatAccuracy(data.aggregates.averageConfidence),
                label: "Accuracy",
                trend: data.accuracyTrendText
            )
        }
    }

    // MARK: - Formatting

    private func formatNumber(_ number: Int) -> String {
        if number >= 1_000_000 {
            return String(format: "%.1fM", Double(number) / 1_000_000)
        } else if number >= 1_000 {
            let formatted = String(format: "%.1fK", Double(number) / 1_000)
            // Remove trailing .0K
            return formatted.replacingOccurrences(of: ".0K", with: "K")
        } else {
            return "\(number)"
        }
    }

    private func formatTimeSaved(_ minutes: Double) -> String {
        let hours = minutes / 60.0

        if hours < 1 {
            return String(format: "%.0fm", minutes)
        } else if hours < 100 {
            return String(format: "%.1fh", hours)
        } else {
            return String(format: "%.0fh", hours)
        }
    }

    private func formatAccuracy(_ confidence: Double?) -> String {
        guard let confidence = confidence else { return "—" }
        return String(format: "%.1f%%", confidence * 100)
    }
}

#Preview {
    StatsGridView(data: DashboardDisplayData(
        period: .sixMonths,
        aggregates: AggregateStatistics(
            totalSessions: 2847,
            totalWords: 847_000,
            totalDurationSeconds: 50000,
            confidenceSum: 2800 * 0.964,
            confidenceCount: 2800
        ),
        dailyData: [],
        gridData: [],
        thisMonth: MonthlyStatistics(),
        lastMonth: MonthlyStatistics()
    ))
    .padding()
    .frame(width: 500)
}
