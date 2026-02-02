import SwiftUI

/// GitHub-style activity grid showing dictation activity over time
struct ActivityGridView: View {
    let gridData: [[DailyAggregate?]]
    let period: DashboardPeriod

    @State private var hoveredCell: (day: Int, week: Int)? = nil

    private let dayLabels = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    // Target width for the grid (based on 6-month view as baseline)
    private let targetGridWidth: CGFloat = 390

    // Max cell size to prevent 30-day view from being too tall
    private let maxCellSize: CGFloat = 12
    private let maxCellSpacing: CGFloat = 3

    // Dynamic cell size based on period
    private var cellSize: CGFloat {
        let weeks = CGFloat(period.weeks)
        let calculated = (targetGridWidth / weeks) * 0.8
        return min(calculated, maxCellSize)
    }

    // Dynamic spacing based on period
    private var cellSpacing: CGFloat {
        let weeks = CGFloat(period.weeks)
        let calculated = (targetGridWidth / weeks) * 0.2
        return min(calculated, maxCellSpacing)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Month labels
            monthLabelsRow

            HStack(alignment: .top, spacing: 4) {
                // Day labels column
                dayLabelsColumn

                // Activity grid
                activityGrid
            }

            // Legend
            legendRow
        }
    }

    // MARK: - Month Labels

    private var monthLabelsRow: some View {
        HStack(spacing: 0) {
            // Offset for day labels column
            Spacer()
                .frame(width: 28)

            // Month labels positioned at week boundaries
            HStack(spacing: 0) {
                ForEach(monthPositions, id: \.month) { position in
                    Text(position.month)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .frame(width: CGFloat(position.weekSpan) * (cellSize + cellSpacing), alignment: .leading)
                }
            }
        }
    }

    private var monthPositions: [(month: String, weekSpan: Int)] {
        guard !gridData.isEmpty, let firstRow = gridData.first else { return [] }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        let monthFormatter = DateFormatter()
        monthFormatter.dateFormat = "MMM"

        var positions: [(month: String, weekSpan: Int)] = []
        var currentMonth: String? = nil
        var weekCount = 0

        for weekIndex in 0..<firstRow.count {
            // Get any valid date from this week
            var weekDate: Date? = nil
            for dayIndex in 0..<min(7, gridData.count) {
                if let aggregate = gridData[dayIndex][weekIndex],
                   let date = dateFormatter.date(from: aggregate.date) {
                    weekDate = date
                    break
                }
            }

            if let date = weekDate {
                let month = monthFormatter.string(from: date)

                if month != currentMonth {
                    if let current = currentMonth {
                        positions.append((month: current, weekSpan: weekCount))
                    }
                    currentMonth = month
                    weekCount = 1
                } else {
                    weekCount += 1
                }
            } else {
                weekCount += 1
            }
        }

        // Add last month
        if let current = currentMonth, weekCount > 0 {
            positions.append((month: current, weekSpan: weekCount))
        }

        return positions
    }

    // MARK: - Day Labels

    private var dayLabelsColumn: some View {
        VStack(spacing: cellSpacing) {
            ForEach(0..<7, id: \.self) { index in
                if index == 1 || index == 3 || index == 5 {
                    Text(dayLabels[index])
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: cellSize, alignment: .trailing)
                } else {
                    Color.clear
                        .frame(width: 24, height: cellSize)
                }
            }
        }
    }

    // MARK: - Activity Grid

    private var activityGrid: some View {
        HStack(spacing: cellSpacing) {
            ForEach(0..<(gridData.first?.count ?? 0), id: \.self) { weekIndex in
                VStack(spacing: cellSpacing) {
                    ForEach(0..<7, id: \.self) { dayIndex in
                        gridCell(day: dayIndex, week: weekIndex)
                    }
                }
            }
        }
    }

    private func gridCell(day: Int, week: Int) -> some View {
        let aggregate = gridData.indices.contains(day) && gridData[day].indices.contains(week)
            ? gridData[day][week]
            : nil

        let level = aggregate?.activityLevel ?? .none
        let isHovered = hoveredCell?.day == day && hoveredCell?.week == week

        return RoundedRectangle(cornerRadius: 2)
            .fill(Color.dashboardOrange.opacity(level.opacity))
            .frame(width: cellSize, height: cellSize)
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .stroke(isHovered ? Color.primary.opacity(0.5) : Color.clear, lineWidth: 1)
            )
            .help(tooltipText(for: aggregate))
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.1)) {
                    hoveredCell = hovering ? (day, week) : nil
                }
            }
    }

    private func tooltipText(for aggregate: DailyAggregate?) -> String {
        guard let aggregate = aggregate else { return "No data" }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        let displayFormatter = DateFormatter()
        displayFormatter.dateStyle = .medium

        guard let date = dateFormatter.date(from: aggregate.date) else {
            return "No data"
        }

        let dateStr = displayFormatter.string(from: date)

        if aggregate.wordCount == 0 {
            return "No activity on \(dateStr)"
        }

        let wordsStr = aggregate.wordCount == 1 ? "1 word" : "\(formatNumber(aggregate.wordCount)) words"
        let sessionsStr = aggregate.sessionCount == 1 ? "1 session" : "\(aggregate.sessionCount) sessions"

        return "\(wordsStr) in \(sessionsStr) on \(dateStr)"
    }

    // MARK: - Legend

    private var legendRow: some View {
        HStack(spacing: 4) {
            Spacer()

            Text("Less")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            ForEach(ActivityLevel.allCases, id: \.rawValue) { level in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.dashboardOrange.opacity(level.opacity))
                    .frame(width: cellSize, height: cellSize)
            }

            Text("More")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Helpers

    private func formatNumber(_ number: Int) -> String {
        if number >= 1_000_000 {
            return String(format: "%.1fM", Double(number) / 1_000_000)
        } else if number >= 1_000 {
            return String(format: "%.1fK", Double(number) / 1_000)
        } else {
            return "\(number)"
        }
    }
}

#Preview {
    // Create sample grid data
    let sampleData: [[DailyAggregate?]] = (0..<7).map { day in
        (0..<26).map { week in
            if Bool.random() {
                var agg = DailyAggregate(date: "2024-01-\(String(format: "%02d", week + 1))")
                agg.wordCount = Int.random(in: 0...3000)
                agg.sessionCount = Int.random(in: 0...20)
                return agg
            }
            return DailyAggregate(date: "2024-01-\(String(format: "%02d", week + 1))")
        }
    }

    return ActivityGridView(gridData: sampleData, period: .sixMonths)
        .padding()
        .frame(width: 500)
}
