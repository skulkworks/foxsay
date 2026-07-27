import Foundation

// MARK: - Dashboard Period

/// Time period for dashboard display
public enum DashboardPeriod: String, CaseIterable, Identifiable {
    case sixMonths = "6mo"
    case oneYear = "1y"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .sixMonths: return "6 months"
        case .oneYear: return "1 year"
        }
    }

    /// Number of days in this period
    public var days: Int {
        switch self {
        case .sixMonths: return 180
        case .oneYear: return 365
        }
    }

    /// Number of weeks to display in the activity grid
    public var weeks: Int {
        switch self {
        case .sixMonths: return 26
        case .oneYear: return 53
        }
    }
}

// MARK: - Activity Level

/// Activity intensity level for grid display (0-4 scale like GitHub)
public enum ActivityLevel: Int, CaseIterable {
    case none = 0
    case low = 1
    case medium = 2
    case high = 3
    case veryHigh = 4

    /// Calculate activity level from word count
    public static func from(wordCount: Int) -> ActivityLevel {
        switch wordCount {
        case 0:
            return .none
        case 1...100:
            return .low
        case 101...500:
            return .medium
        case 501...2000:
            return .high
        default:
            return .veryHigh
        }
    }

    /// Opacity for the activity grid cell
    public var opacity: Double {
        switch self {
        case .none: return 0.1
        case .low: return 0.25
        case .medium: return 0.45
        case .high: return 0.65
        case .veryHigh: return 0.85
        }
    }
}

// MARK: - Daily Aggregate

/// Aggregated statistics for a single day
public struct DailyAggregate: Codable, Equatable {
    public var date: String  // "YYYY-MM-DD" format
    public var sessionCount: Int
    public var wordCount: Int
    public var totalDurationSeconds: Double
    public var confidenceSum: Double
    public var confidenceCount: Int

    public init(
        date: String,
        sessionCount: Int = 0,
        wordCount: Int = 0,
        totalDurationSeconds: Double = 0,
        confidenceSum: Double = 0,
        confidenceCount: Int = 0
    ) {
        self.date = date
        self.sessionCount = sessionCount
        self.wordCount = wordCount
        self.totalDurationSeconds = totalDurationSeconds
        self.confidenceSum = confidenceSum
        self.confidenceCount = confidenceCount
    }

    /// Average confidence for this day
    public var averageConfidence: Double? {
        guard confidenceCount > 0 else { return nil }
        return confidenceSum / Double(confidenceCount)
    }

    /// Activity level based on word count
    public var activityLevel: ActivityLevel {
        ActivityLevel.from(wordCount: wordCount)
    }
}

// MARK: - Aggregate Statistics

/// Lifetime aggregate statistics
public struct AggregateStatistics: Codable, Equatable {
    public var totalSessions: Int
    public var totalWords: Int
    public var totalDurationSeconds: Double
    public var confidenceSum: Double
    public var confidenceCount: Int
    public var firstSessionDate: Date?
    public var lastUpdated: Date

    public init(
        totalSessions: Int = 0,
        totalWords: Int = 0,
        totalDurationSeconds: Double = 0,
        confidenceSum: Double = 0,
        confidenceCount: Int = 0,
        firstSessionDate: Date? = nil,
        lastUpdated: Date = Date()
    ) {
        self.totalSessions = totalSessions
        self.totalWords = totalWords
        self.totalDurationSeconds = totalDurationSeconds
        self.confidenceSum = confidenceSum
        self.confidenceCount = confidenceCount
        self.firstSessionDate = firstSessionDate
        self.lastUpdated = lastUpdated
    }

    /// Average confidence across all sessions
    public var averageConfidence: Double? {
        guard confidenceCount > 0 else { return nil }
        return confidenceSum / Double(confidenceCount)
    }

    /// Estimated time saved in minutes (assuming 40 WPM typing speed)
    public var timeSavedMinutes: Double {
        Double(totalWords) / 40.0
    }
}

// MARK: - Statistics Store

/// Persistent store for all statistics data
public struct StatisticsStore: Codable {
    public var version: Int
    public var aggregates: AggregateStatistics
    public var dailyData: [String: DailyAggregate]  // keyed by "YYYY-MM-DD"

    public init(
        version: Int = 1,
        aggregates: AggregateStatistics = AggregateStatistics(),
        dailyData: [String: DailyAggregate] = [:]
    ) {
        self.version = version
        self.aggregates = aggregates
        self.dailyData = dailyData
    }
}

// MARK: - Monthly Statistics

/// Statistics for a single month (for trend calculations)
public struct MonthlyStatistics {
    public var sessions: Int = 0
    public var words: Int = 0
    public var durationSeconds: Double = 0
    public var confidenceSum: Double = 0
    public var confidenceCount: Int = 0

    public var timeSavedMinutes: Double {
        Double(words) / 40.0
    }

    public var averageConfidence: Double? {
        guard confidenceCount > 0 else { return nil }
        return confidenceSum / Double(confidenceCount)
    }
}

// MARK: - Dashboard Display Data

/// Computed data for dashboard display
public struct DashboardDisplayData {
    public let period: DashboardPeriod
    public let aggregates: AggregateStatistics
    public let dailyData: [DailyAggregate]  // Sorted by date, most recent last
    public let gridData: [[DailyAggregate?]]  // 7 rows (days) x N columns (weeks)

    // Monthly trend data
    public let thisMonth: MonthlyStatistics
    public let lastMonth: MonthlyStatistics

    /// Sessions in the current period
    public var periodSessions: Int {
        dailyData.reduce(0) { $0 + $1.sessionCount }
    }

    /// Words in the current period
    public var periodWords: Int {
        dailyData.reduce(0) { $0 + $1.wordCount }
    }

    // MARK: - Trend Calculations

    /// Session trend percentage (positive = increase)
    public var sessionTrend: Double? {
        calculateTrend(current: thisMonth.sessions, previous: lastMonth.sessions)
    }

    /// Words trend percentage
    public var wordsTrend: Double? {
        calculateTrend(current: thisMonth.words, previous: lastMonth.words)
    }

    /// Time saved trend percentage
    public var timeSavedTrend: Double? {
        calculateTrend(current: thisMonth.timeSavedMinutes, previous: lastMonth.timeSavedMinutes)
    }

    /// Accuracy trend (absolute change, not percentage)
    public var accuracyTrend: Double? {
        guard let currentAcc = thisMonth.averageConfidence,
              let previousAcc = lastMonth.averageConfidence else { return nil }
        // Return absolute change in percentage points
        return (currentAcc - previousAcc) * 100
    }

    private func calculateTrend(current: Int, previous: Int) -> Double? {
        guard previous > 0 else { return nil }
        return Double(current - previous) / Double(previous) * 100
    }

    private func calculateTrend(current: Double, previous: Double) -> Double? {
        guard previous > 0 else { return nil }
        return (current - previous) / previous * 100
    }

    // MARK: - Formatted Trends

    public var sessionTrendText: String? {
        formatTrend(sessionTrend, suffix: "this month")
    }

    public var wordsTrendText: String? {
        formatTrend(wordsTrend, suffix: "this month")
    }

    public var timeSavedTrendText: String? {
        formatTrend(timeSavedTrend, suffix: "this month")
    }

    public var accuracyTrendText: String? {
        guard let trend = accuracyTrend else { return nil }
        if abs(trend) < 0.1 { return nil }  // Ignore tiny changes
        let arrow = trend >= 0 ? "↑" : "↓"
        return "\(arrow) \(String(format: "%.1f", abs(trend)))% improved"
    }

    private func formatTrend(_ trend: Double?, suffix: String) -> String? {
        guard let trend = trend else { return nil }
        if abs(trend) < 1 { return nil }  // Ignore changes less than 1%
        let arrow = trend >= 0 ? "↑" : "↓"
        return "\(arrow) \(Int(abs(trend)))% \(suffix)"
    }
}
