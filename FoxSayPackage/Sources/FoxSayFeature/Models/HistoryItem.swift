import Foundation

/// A single transcription history item
public struct HistoryItem: Codable, Identifiable, Equatable {
    public let id: UUID
    public let text: String
    public let originalText: String?
    public let timestamp: Date
    public let duration: TimeInterval
    public let processingTime: TimeInterval
    public let confidence: Double?
    public let appBundleId: String?
    public let appName: String?
    public let wasDevCorrected: Bool
    public let audioFileName: String?  // e.g., "{uuid}.caf"
    public var isStarred: Bool

    public init(
        id: UUID = UUID(),
        text: String,
        originalText: String? = nil,
        timestamp: Date = Date(),
        duration: TimeInterval,
        processingTime: TimeInterval,
        confidence: Double? = nil,
        appBundleId: String? = nil,
        appName: String? = nil,
        wasDevCorrected: Bool = false,
        audioFileName: String? = nil,
        isStarred: Bool = false
    ) {
        self.id = id
        self.text = text
        self.originalText = originalText
        self.timestamp = timestamp
        self.duration = duration
        self.processingTime = processingTime
        self.confidence = confidence
        self.appBundleId = appBundleId
        self.appName = appName
        self.wasDevCorrected = wasDevCorrected
        self.audioFileName = audioFileName
        self.isStarred = isStarred
    }

    /// Create a history item from a transcription result
    public static func from(
        result: TranscriptionResult,
        duration: TimeInterval,
        appBundleId: String?,
        appName: String?,
        audioFileName: String?
    ) -> HistoryItem {
        HistoryItem(
            text: result.text,
            originalText: result.originalText,
            duration: duration,
            processingTime: result.processingTime,
            confidence: result.confidence,
            appBundleId: appBundleId,
            appName: appName,
            wasDevCorrected: result.wasDevCorrected,
            audioFileName: audioFileName
        )
    }

    /// Formatted duration string (e.g., "1.2s")
    public var formattedDuration: String {
        String(format: "%.1fs", duration)
    }

    /// Formatted processing time (e.g., "0.5s")
    public var formattedProcessingTime: String {
        String(format: "%.2fs", processingTime)
    }

    /// Formatted timestamp for display
    public var formattedTimestamp: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: timestamp, relativeTo: Date())
    }

    /// Full date/time string
    public var fullTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: timestamp)
    }
}
