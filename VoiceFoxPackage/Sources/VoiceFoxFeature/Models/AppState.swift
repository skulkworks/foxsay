import Foundation
import SwiftUI

/// Shared app state for VoiceFox
@MainActor
public class AppState: ObservableObject {
    public static let shared = AppState()

    /// Current recording state
    @Published public var isRecording = false

    /// Current transcription state
    @Published public var isTranscribing = false

    /// Last transcription result
    @Published public var lastResult: TranscriptionResult?

    /// Current error message to display
    @Published public var errorMessage: String?

    /// Whether the overlay is visible
    @Published public var isOverlayVisible = false

    /// Whether settings sheet is shown
    @Published public var showSettings = false

    /// Whether model download is in progress
    @Published public var isDownloadingModel = false

    /// Model download progress (0.0 - 1.0)
    @Published public var downloadProgress: Double = 0

    /// Current frontmost app bundle ID
    @Published public var frontmostAppBundleId: String?

    /// Whether current frontmost app is a dev app
    public var isDevAppActive: Bool {
        guard let bundleId = frontmostAppBundleId else { return false }
        return DevAppConfigManager.shared.isDevApp(bundleId: bundleId)
    }

    private init() {
        // Listen for settings notification
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("ShowSettings"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.showSettings = true
            }
        }

        // Wire up hotkey callbacks
        setupHotkeyCallbacks()
    }

    private func setupHotkeyCallbacks() {
        let hotkeyManager = HotkeyManager.shared

        hotkeyManager.onHotkeyDown = { [weak self] in
            Task { @MainActor in
                await self?.startRecording()
            }
        }

        hotkeyManager.onHotkeyUp = { [weak self] in
            Task { @MainActor in
                await self?.stopRecordingAndTranscribe()
            }
        }

        print("VoiceFox: Hotkey callbacks configured")
    }

    /// Start recording audio
    public func startRecording() async {
        guard !isRecording else { return }

        // Refresh and check microphone permission
        AudioEngine.shared.updatePermissionStatus()
        if !AudioEngine.shared.hasPermission {
            print("VoiceFox: No microphone permission - requesting...")
            await AudioEngine.shared.checkPermission()
        }

        guard AudioEngine.shared.hasPermission else {
            print("VoiceFox: Microphone permission denied")
            setError("Microphone permission required")
            return
        }

        do {
            print("VoiceFox: Starting recording...")
            try AudioEngine.shared.startRecording()
            print("VoiceFox: Recording started successfully")
            isRecording = true
            errorMessage = nil

            // Show overlay
            OverlayWindowController.shared.showOverlay()
        } catch {
            print("VoiceFox: Failed to start recording: \(error)")
            setError("Failed to start recording: \(error.localizedDescription)")
        }
    }

    /// Stop recording and transcribe
    public func stopRecordingAndTranscribe() async {
        guard isRecording else { return }

        print("VoiceFox: Stopping recording...")
        let audioBuffer = AudioEngine.shared.stopRecording()
        isRecording = false

        guard !audioBuffer.isEmpty else {
            print("VoiceFox: No audio recorded")
            return
        }

        print("VoiceFox: Audio buffer size: \(audioBuffer.count) samples")

        // Start transcription
        isTranscribing = true

        do {
            // Check if model is ready
            guard EngineManager.shared.isModelReady else {
                print("VoiceFox: Model not downloaded")
                setError("Speech model not downloaded")
                isTranscribing = false
                return
            }

            print("VoiceFox: Starting transcription...")
            var result = try await EngineManager.shared.transcribe(audioBuffer: audioBuffer)

            // Apply corrections if in a dev app
            let isDevApp = AppDetector.shared.isDevApp
            if isDevApp {
                print("VoiceFox: Applying dev corrections...")
                result = await CorrectionPipeline.shared.process(result, isDevApp: isDevApp)
            }

            print("VoiceFox: Transcription result: \(result.text)")
            lastResult = result
            isTranscribing = false

            // Inject text into active app or copy to clipboard
            if !result.text.isEmpty {
                let copyOnly = TextInjector.shared.copyToClipboardOnly
                NSLog("VoiceFox: Output text: '%@', copyToClipboardOnly: %d", result.text, copyOnly ? 1 : 0)
                if copyOnly {
                    NSLog("VoiceFox: Copying text to clipboard only...")
                    TextInjector.shared.copyToClipboard(result.text)
                } else {
                    NSLog("VoiceFox: Injecting text at cursor...")
                    try await TextInjector.shared.injectText(result.text)
                }
            } else {
                NSLog("VoiceFox: No text to output (empty result)")
            }

            // Hide overlay after a brief delay to show result
            Task {
                try? await Task.sleep(nanoseconds: 800_000_000)  // 0.8 seconds
                await MainActor.run {
                    OverlayWindowController.shared.hideOverlay()
                    // Ensure hotkey tap is still active
                    HotkeyManager.shared.ensureEventTapActive()
                }
            }

        } catch {
            print("VoiceFox: Transcription failed: \(error)")
            setError("Transcription failed: \(error.localizedDescription)")
            isTranscribing = false

            // Hide overlay on error too
            Task {
                try? await Task.sleep(nanoseconds: 1_500_000_000)  // 1.5 seconds to show error
                await MainActor.run {
                    OverlayWindowController.shared.hideOverlay()
                    // Ensure hotkey tap is still active
                    HotkeyManager.shared.ensureEventTapActive()
                }
            }
        }
    }

    /// Manual trigger for recording (for UI button)
    public func toggleRecording() async {
        if isRecording {
            await stopRecordingAndTranscribe()
        } else {
            await startRecording()
        }
    }

    public func setRecording(_ recording: Bool) {
        isRecording = recording
        if recording {
            errorMessage = nil
        }
    }

    public func setTranscribing(_ transcribing: Bool) {
        isTranscribing = transcribing
    }

    public func setResult(_ result: TranscriptionResult) {
        lastResult = result
    }

    public func setError(_ message: String) {
        errorMessage = message
    }

    public func clearError() {
        errorMessage = nil
    }
}
