import AVFoundation
import Foundation

/// Manages sound effect playback for overlay open/close events
@MainActor
public class SoundEffectManager {
    public static let shared = SoundEffectManager()

    private var openPlayer: AVAudioPlayer?
    private var closePlayer: AVAudioPlayer?

    /// Whether sound effects are enabled
    public var isEnabled: Bool {
        UserDefaults.standard.object(forKey: "enableSoundEffects") as? Bool ?? false
    }

    private init() {
        preloadSounds()
    }

    private func preloadSounds() {
        if let openURL = Bundle.module.url(forResource: "overlay-open", withExtension: "wav") {
            openPlayer = try? AVAudioPlayer(contentsOf: openURL)
            openPlayer?.volume = 0.5
            openPlayer?.prepareToPlay()
        }
        if let closeURL = Bundle.module.url(forResource: "overlay-close", withExtension: "wav") {
            closePlayer = try? AVAudioPlayer(contentsOf: closeURL)
            closePlayer?.volume = 0.5
            closePlayer?.prepareToPlay()
        }
    }

    /// Play the overlay open sound
    public func playOpen() {
        guard isEnabled else { return }
        openPlayer?.currentTime = 0
        openPlayer?.play()
    }

    /// Play the overlay close sound
    public func playClose() {
        guard isEnabled else { return }
        closePlayer?.currentTime = 0
        closePlayer?.play()
    }
}
