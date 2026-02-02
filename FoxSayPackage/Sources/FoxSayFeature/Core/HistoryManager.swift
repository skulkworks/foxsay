import Foundation
import AVFoundation

/// Manages transcription history with persistence
@MainActor
public class HistoryManager: ObservableObject {
    public static let shared = HistoryManager()

    /// Maximum number of items to keep (starred items exempt)
    public static let maxItems = 500

    /// Maximum age for items in days (starred items exempt)
    public static let maxAgeDays = 30

    @Published public private(set) var items: [HistoryItem] = []
    @Published public private(set) var isLoading = false

    private let historyFileURL: URL
    private let audioDirectoryURL: URL

    private init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!.appendingPathComponent("FoxSay", isDirectory: true)

        historyFileURL = appSupport.appendingPathComponent("history.json")
        audioDirectoryURL = appSupport.appendingPathComponent("audio", isDirectory: true)

        // Ensure directories exist
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: audioDirectoryURL, withIntermediateDirectories: true)

        // Load history
        Task {
            await loadHistory()
        }
    }

    // MARK: - Public Methods

    /// Add a new history item
    public func addItem(_ item: HistoryItem) {
        items.insert(item, at: 0)
        applyRetentionPolicy()
        saveHistory()
    }

    /// Add item from transcription result
    public func addItem(
        from result: TranscriptionResult,
        duration: TimeInterval,
        audioBuffer: [Float]?
    ) {
        let appBundleId = AppDetector.shared.frontmostAppBundleId
        let appName = AppDetector.shared.frontmostAppName

        var audioFileName: String? = nil
        if let buffer = audioBuffer, !buffer.isEmpty {
            let itemId = UUID()
            audioFileName = saveAudio(buffer, for: itemId)
        }

        let item = HistoryItem.from(
            result: result,
            duration: duration,
            appBundleId: appBundleId,
            appName: appName,
            audioFileName: audioFileName
        )

        addItem(item)
    }

    /// Delete an item
    public func deleteItem(_ item: HistoryItem) {
        // Delete associated audio file
        if let audioFileName = item.audioFileName {
            let audioURL = audioDirectoryURL.appendingPathComponent(audioFileName)
            try? FileManager.default.removeItem(at: audioURL)
        }

        items.removeAll { $0.id == item.id }
        saveHistory()
    }

    /// Toggle starred status
    public func toggleStar(for item: HistoryItem) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index].isStarred.toggle()
            saveHistory()
        }
    }

    /// Clear all non-starred items
    public func clearAll() {
        // Delete all audio files for non-starred items
        for item in items where !item.isStarred {
            if let audioFileName = item.audioFileName {
                let audioURL = audioDirectoryURL.appendingPathComponent(audioFileName)
                try? FileManager.default.removeItem(at: audioURL)
            }
        }

        items.removeAll { !$0.isStarred }
        saveHistory()
    }

    /// Get audio URL for a history item
    public func getAudioURL(for item: HistoryItem) -> URL? {
        guard let audioFileName = item.audioFileName else { return nil }
        let url = audioDirectoryURL.appendingPathComponent(audioFileName)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Search items
    public func search(_ query: String) -> [HistoryItem] {
        guard !query.isEmpty else { return items }
        let lowercased = query.lowercased()
        return items.filter {
            $0.text.lowercased().contains(lowercased) ||
            $0.appName?.lowercased().contains(lowercased) == true
        }
    }

    /// Filter items
    public func filter(_ filter: HistoryFilter) -> [HistoryItem] {
        switch filter {
        case .all:
            return items
        case .starred:
            return items.filter { $0.isStarred }
        case .devApps:
            return items.filter { $0.wasDevCorrected }
        }
    }

    // MARK: - Audio Storage

    /// Save audio buffer to file
    @discardableResult
    public func saveAudio(_ audioBuffer: [Float], for itemId: UUID) -> String? {
        let fileName = "\(itemId.uuidString).caf"
        let fileURL = audioDirectoryURL.appendingPathComponent(fileName)

        // Create audio file with 16kHz sample rate
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        )!

        guard let audioFile = try? AVAudioFile(
            forWriting: fileURL,
            settings: format.settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        ) else {
            print("FoxSay: Failed to create audio file")
            return nil
        }

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(audioBuffer.count)
        ) else {
            print("FoxSay: Failed to create audio buffer")
            return nil
        }

        buffer.frameLength = buffer.frameCapacity

        // Copy audio data
        audioBuffer.withUnsafeBufferPointer { sourcePtr in
            if let channelData = buffer.floatChannelData?[0] {
                for i in 0..<audioBuffer.count {
                    channelData[i] = sourcePtr[i]
                }
            }
        }

        do {
            try audioFile.write(from: buffer)
            print("FoxSay: Saved audio file: \(fileName)")
            return fileName
        } catch {
            print("FoxSay: Failed to write audio file: \(error)")
            return nil
        }
    }

    // MARK: - Persistence

    private func loadHistory() async {
        isLoading = true
        defer { isLoading = false }

        guard FileManager.default.fileExists(atPath: historyFileURL.path) else {
            return
        }

        do {
            let data = try Data(contentsOf: historyFileURL)
            let decoder = JSONDecoder()
            items = try decoder.decode([HistoryItem].self, from: data)
            applyRetentionPolicy()
        } catch {
            print("FoxSay: Failed to load history: \(error)")
        }
    }

    private func saveHistory() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(items)
            try data.write(to: historyFileURL)
        } catch {
            print("FoxSay: Failed to save history: \(error)")
        }
    }

    private func applyRetentionPolicy() {
        let cutoffDate = Calendar.current.date(
            byAdding: .day,
            value: -Self.maxAgeDays,
            to: Date()
        )!

        // Remove old items (except starred)
        var itemsToRemove: [HistoryItem] = []
        for item in items where !item.isStarred && item.timestamp < cutoffDate {
            itemsToRemove.append(item)
        }

        // Remove excess items (except starred)
        let nonStarredItems = items.filter { !$0.isStarred }
        if nonStarredItems.count > Self.maxItems {
            let excessCount = nonStarredItems.count - Self.maxItems
            let oldestItems = nonStarredItems.suffix(excessCount)
            itemsToRemove.append(contentsOf: oldestItems)
        }

        // Delete audio files and remove items
        for item in itemsToRemove {
            if let audioFileName = item.audioFileName {
                let audioURL = audioDirectoryURL.appendingPathComponent(audioFileName)
                try? FileManager.default.removeItem(at: audioURL)
            }
        }

        items.removeAll { item in itemsToRemove.contains(where: { $0.id == item.id }) }
    }
}
