import Foundation

/// Manages statistics persistence and aggregation for the dashboard
@MainActor
public class StatisticsManager: ObservableObject {
    public static let shared = StatisticsManager()

    // MARK: - Published Properties

    @Published public private(set) var store: StatisticsStore
    @Published public private(set) var isLoading = false

    // MARK: - Private Properties

    private let statisticsFileURL: URL
    private let dateFormatter: DateFormatter
    private var cacheInvalidationDate: Date?
    private var cachedDisplayData: [DashboardPeriod: DashboardDisplayData] = [:]

    // MARK: - Initialization

    private init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!.appendingPathComponent("FoxSay", isDirectory: true)

        statisticsFileURL = appSupport.appendingPathComponent("statistics.json")

        // Ensure directory exists
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)

        // Setup date formatter
        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = TimeZone.current

        // Load existing store
        store = StatisticsStore()
        loadStatistics()
    }

    // MARK: - Public Methods

    /// Record a new session from a history item
    public func recordSession(from historyItem: HistoryItem) {
        let dateKey = dateKeyFor(historyItem.timestamp)
        let wordCount = countWords(in: historyItem.text)

        // Update or create daily aggregate
        var daily = store.dailyData[dateKey] ?? DailyAggregate(date: dateKey)
        daily.sessionCount += 1
        daily.wordCount += wordCount
        daily.totalDurationSeconds += historyItem.duration

        if let confidence = historyItem.confidence {
            daily.confidenceSum += confidence
            daily.confidenceCount += 1
        }

        store.dailyData[dateKey] = daily

        // Update aggregates
        store.aggregates.totalSessions += 1
        store.aggregates.totalWords += wordCount
        store.aggregates.totalDurationSeconds += historyItem.duration

        if let confidence = historyItem.confidence {
            store.aggregates.confidenceSum += confidence
            store.aggregates.confidenceCount += 1
        }

        if store.aggregates.firstSessionDate == nil {
            store.aggregates.firstSessionDate = historyItem.timestamp
        }
        store.aggregates.lastUpdated = Date()

        // Invalidate cache and save
        invalidateCache()
        saveStatistics()
    }

    /// Get dashboard display data for a period
    public func getDashboardData(period: DashboardPeriod) -> DashboardDisplayData {
        // Check cache
        if let cached = cachedDisplayData[period],
           let invalidationDate = cacheInvalidationDate,
           Date().timeIntervalSince(invalidationDate) < 300 {  // 5 minute cache
            return cached
        }

        let data = computeDashboardData(for: period)
        cachedDisplayData[period] = data
        cacheInvalidationDate = Date()
        return data
    }

    /// Backfill statistics from existing history items
    public func backfillFromHistory(_ items: [HistoryItem]) {
        guard !items.isEmpty else { return }

        // Reset store
        store = StatisticsStore()

        // Process items oldest first
        let sortedItems = items.sorted { $0.timestamp < $1.timestamp }

        for item in sortedItems {
            let dateKey = dateKeyFor(item.timestamp)
            let wordCount = countWords(in: item.text)

            // Update daily aggregate
            var daily = store.dailyData[dateKey] ?? DailyAggregate(date: dateKey)
            daily.sessionCount += 1
            daily.wordCount += wordCount
            daily.totalDurationSeconds += item.duration

            if let confidence = item.confidence {
                daily.confidenceSum += confidence
                daily.confidenceCount += 1
            }

            store.dailyData[dateKey] = daily

            // Update aggregates
            store.aggregates.totalSessions += 1
            store.aggregates.totalWords += wordCount
            store.aggregates.totalDurationSeconds += item.duration

            if let confidence = item.confidence {
                store.aggregates.confidenceSum += confidence
                store.aggregates.confidenceCount += 1
            }
        }

        store.aggregates.firstSessionDate = sortedItems.first?.timestamp
        store.aggregates.lastUpdated = Date()

        invalidateCache()
        saveStatistics()

        print("FoxSay: Backfilled statistics from \(items.count) history items")
    }

    /// Generate realistic demo data for screenshots
    public func generateDemoData() {
        store = StatisticsStore()

        let calendar = Calendar.current
        let today = Date()

        // Generate 6 months of data with realistic patterns
        for dayOffset in 0..<180 {
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: today) else { continue }
            let dateKey = dateKeyFor(date)
            let weekday = calendar.component(.weekday, from: date)

            // More activity on weekdays (matching HTML mockup logic)
            let isWeekday = weekday >= 2 && weekday <= 6
            let baseChance = isWeekday ? 0.7 : 0.3

            guard Double.random(in: 0...1) < baseChance else { continue }

            // Random intensity level
            let intensity = Double.random(in: 0...1)
            let (sessions, wordsPerSession): (Int, ClosedRange<Int>) = {
                if intensity < 0.3 { return (Int.random(in: 1...3), 50...200) }
                else if intensity < 0.6 { return (Int.random(in: 3...8), 200...500) }
                else if intensity < 0.85 { return (Int.random(in: 8...15), 500...1500) }
                else { return (Int.random(in: 15...25), 1500...4000) }
            }()

            var daily = DailyAggregate(date: dateKey)
            daily.sessionCount = sessions
            daily.wordCount = (0..<sessions).reduce(0) { acc, _ in
                acc + Int.random(in: wordsPerSession)
            }
            daily.totalDurationSeconds = Double(daily.wordCount) / 2.5  // ~150 WPM speaking
            daily.confidenceSum = Double(sessions) * Double.random(in: 0.990...0.994)  // Target ~99.2% average
            daily.confidenceCount = sessions

            store.dailyData[dateKey] = daily

            // Update aggregates
            store.aggregates.totalSessions += daily.sessionCount
            store.aggregates.totalWords += daily.wordCount
            store.aggregates.totalDurationSeconds += daily.totalDurationSeconds
            store.aggregates.confidenceSum += daily.confidenceSum
            store.aggregates.confidenceCount += daily.confidenceCount
        }

        store.aggregates.firstSessionDate = calendar.date(byAdding: .day, value: -180, to: today)
        store.aggregates.lastUpdated = today

        invalidateCache()
        saveStatistics()

        print("FoxSay: Generated demo statistics data")
    }

    /// Clear all statistics data
    public func clearAllData() {
        store = StatisticsStore()
        invalidateCache()
        saveStatistics()
        print("FoxSay: Cleared all statistics data")
    }

    // MARK: - Private Methods

    private func dateKeyFor(_ date: Date) -> String {
        dateFormatter.string(from: date)
    }

    private func dateFrom(_ dateKey: String) -> Date? {
        dateFormatter.date(from: dateKey)
    }

    private func countWords(in text: String) -> Int {
        let words = text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        return words.count
    }

    private func invalidateCache() {
        cachedDisplayData.removeAll()
        cacheInvalidationDate = nil
    }

    private func computeDashboardData(for period: DashboardPeriod) -> DashboardDisplayData {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // Get start date for period
        guard let startDate = calendar.date(byAdding: .day, value: -period.days, to: today) else {
            return DashboardDisplayData(
                period: period,
                aggregates: store.aggregates,
                dailyData: [],
                gridData: [],
                thisMonth: MonthlyStatistics(),
                lastMonth: MonthlyStatistics()
            )
        }

        // Filter daily data for period
        let dailyData = store.dailyData.values
            .filter { daily in
                guard let date = dateFrom(daily.date) else { return false }
                return date >= startDate && date <= today
            }
            .sorted { $0.date < $1.date }

        // Build grid data (7 rows x N weeks)
        let gridData = buildGridData(for: period, endDate: today)

        // Calculate monthly statistics for trends
        let (thisMonth, lastMonth) = computeMonthlyStatistics(calendar: calendar, today: today)

        return DashboardDisplayData(
            period: period,
            aggregates: store.aggregates,
            dailyData: dailyData,
            gridData: gridData,
            thisMonth: thisMonth,
            lastMonth: lastMonth
        )
    }

    private func computeMonthlyStatistics(calendar: Calendar, today: Date) -> (thisMonth: MonthlyStatistics, lastMonth: MonthlyStatistics) {
        // Get first day of this month
        let thisMonthComponents = calendar.dateComponents([.year, .month], from: today)
        guard let thisMonthStart = calendar.date(from: thisMonthComponents) else {
            return (MonthlyStatistics(), MonthlyStatistics())
        }

        // Get first day of last month
        guard let lastMonthStart = calendar.date(byAdding: .month, value: -1, to: thisMonthStart) else {
            return (MonthlyStatistics(), MonthlyStatistics())
        }

        var thisMonth = MonthlyStatistics()
        var lastMonth = MonthlyStatistics()

        for (_, daily) in store.dailyData {
            guard let date = dateFrom(daily.date) else { continue }

            if date >= thisMonthStart && date <= today {
                // This month
                thisMonth.sessions += daily.sessionCount
                thisMonth.words += daily.wordCount
                thisMonth.durationSeconds += daily.totalDurationSeconds
                thisMonth.confidenceSum += daily.confidenceSum
                thisMonth.confidenceCount += daily.confidenceCount
            } else if date >= lastMonthStart && date < thisMonthStart {
                // Last month
                lastMonth.sessions += daily.sessionCount
                lastMonth.words += daily.wordCount
                lastMonth.durationSeconds += daily.totalDurationSeconds
                lastMonth.confidenceSum += daily.confidenceSum
                lastMonth.confidenceCount += daily.confidenceCount
            }
        }

        return (thisMonth, lastMonth)
    }

    private func buildGridData(for period: DashboardPeriod, endDate: Date) -> [[DailyAggregate?]] {
        let calendar = Calendar.current

        // Find the end of the week containing endDate (Saturday)
        let weekday = calendar.component(.weekday, from: endDate)
        let daysToSaturday = (7 - weekday) % 7
        guard let gridEndDate = calendar.date(byAdding: .day, value: daysToSaturday, to: endDate) else {
            return []
        }

        // Calculate grid start date
        let totalDays = period.weeks * 7
        guard let gridStartDate = calendar.date(byAdding: .day, value: -(totalDays - 1), to: gridEndDate) else {
            return []
        }

        // Build 7 rows (Sunday to Saturday) x N weeks
        var grid: [[DailyAggregate?]] = Array(repeating: Array(repeating: nil, count: period.weeks), count: 7)

        for weekIndex in 0..<period.weeks {
            for dayIndex in 0..<7 {
                let dayOffset = weekIndex * 7 + dayIndex
                guard let date = calendar.date(byAdding: .day, value: dayOffset, to: gridStartDate) else {
                    continue
                }

                // Don't include future dates
                if date > endDate {
                    continue
                }

                let dateKey = dateKeyFor(date)
                grid[dayIndex][weekIndex] = store.dailyData[dateKey] ?? DailyAggregate(date: dateKey)
            }
        }

        return grid
    }

    // MARK: - Persistence

    private func loadStatistics() {
        isLoading = true
        defer { isLoading = false }

        guard FileManager.default.fileExists(atPath: statisticsFileURL.path) else {
            return
        }

        do {
            let data = try Data(contentsOf: statisticsFileURL)
            let decoder = JSONDecoder()
            store = try decoder.decode(StatisticsStore.self, from: data)
            print("FoxSay: Loaded statistics - \(store.aggregates.totalSessions) sessions, \(store.aggregates.totalWords) words")
        } catch {
            print("FoxSay: Failed to load statistics: \(error)")
        }
    }

    private func saveStatistics() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(store)
            try data.write(to: statisticsFileURL)
        } catch {
            print("FoxSay: Failed to save statistics: \(error)")
        }
    }
}
