import Foundation
import AVFoundation

/// Manages audio playback for history items
@MainActor
public class AudioPlaybackManager: NSObject, ObservableObject {
    public static let shared = AudioPlaybackManager()

    @Published public private(set) var isPlaying = false
    @Published public private(set) var currentItemId: UUID?
    @Published public private(set) var progress: Double = 0
    @Published public private(set) var duration: TimeInterval = 0

    private var audioPlayer: AVAudioPlayer?
    private var progressTimer: Timer?

    private override init() {
        super.init()
    }

    /// Play audio for a history item
    public func play(_ item: HistoryItem) {
        // Stop any current playback
        stop()

        guard let url = HistoryManager.shared.getAudioURL(for: item) else {
            print("FoxSay: No audio file for item")
            return
        }

        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.delegate = self
            audioPlayer?.prepareToPlay()

            duration = audioPlayer?.duration ?? 0
            currentItemId = item.id
            isPlaying = true
            progress = 0

            audioPlayer?.play()
            startProgressTimer()

            print("FoxSay: Playing audio for item \(item.id)")
        } catch {
            print("FoxSay: Failed to play audio: \(error)")
        }
    }

    /// Stop playback
    public func stop() {
        audioPlayer?.stop()
        audioPlayer = nil
        stopProgressTimer()

        isPlaying = false
        currentItemId = nil
        progress = 0
        duration = 0
    }

    /// Toggle play/pause
    public func toggle(_ item: HistoryItem) {
        if currentItemId == item.id && isPlaying {
            pause()
        } else if currentItemId == item.id && !isPlaying {
            resume()
        } else {
            play(item)
        }
    }

    /// Pause playback
    public func pause() {
        audioPlayer?.pause()
        isPlaying = false
        stopProgressTimer()
    }

    /// Resume playback
    public func resume() {
        audioPlayer?.play()
        isPlaying = true
        startProgressTimer()
    }

    /// Seek to position (0.0 - 1.0)
    public func seek(to position: Double) {
        guard let player = audioPlayer else { return }
        let time = position * player.duration
        player.currentTime = time
        progress = position
    }

    // MARK: - Timer

    private func startProgressTimer() {
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, let player = self.audioPlayer else { return }
                self.progress = player.currentTime / player.duration
            }
        }
    }

    private func stopProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }
}

// MARK: - AVAudioPlayerDelegate

extension AudioPlaybackManager: AVAudioPlayerDelegate {
    nonisolated public func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.stop()
        }
    }

    nonisolated public func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        print("FoxSay: Audio decode error: \(error?.localizedDescription ?? "unknown")")
        Task { @MainActor in
            self.stop()
        }
    }
}
