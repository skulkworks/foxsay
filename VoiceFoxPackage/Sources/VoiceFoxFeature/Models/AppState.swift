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

    /// Currently selected sidebar item
    @Published public var selectedSidebarItem: SidebarItem = .status

    /// Whether settings sheet is shown (deprecated - for backward compatibility)
    @Published public var showSettings = false {
        didSet {
            if showSettings {
                // Navigate to general settings when old showSettings is triggered
                selectedSidebarItem = .general
                showSettings = false
            }
        }
    }

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

        hotkeyManager.onCancel = { [weak self] in
            Task { @MainActor in
                self?.cancelRecording()
            }
        }

        print("VoiceFox: Hotkey callbacks configured")
    }

    /// Cancel recording without transcribing
    public func cancelRecording() {
        guard isRecording else { return }

        NSLog("VoiceFox: Recording cancelled")
        AudioEngine.shared.stopRecording()
        isRecording = false
        isTranscribing = false
        errorMessage = nil

        // Hide overlay
        OverlayWindowController.shared.hideOverlay()

        // Clear target app
        AppDetector.shared.clearTargetApp()

        // Update menu bar
        MenuBarManager.shared.setRecording(false)
    }

    /// Start recording audio
    public func startRecording() async {
        guard !isRecording else { return }

        // Capture the target app before showing overlay (so we know where text will go)
        AppDetector.shared.captureTargetApp()

        // Refresh and check microphone permission
        AudioEngine.shared.updatePermissionStatus()
        if !AudioEngine.shared.hasPermission {
            print("VoiceFox: No microphone permission - requesting...")
            await AudioEngine.shared.checkPermission()
        }

        guard AudioEngine.shared.hasPermission else {
            print("VoiceFox: Microphone permission denied")
            setError("Microphone permission required")
            AppDetector.shared.clearTargetApp()
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
            AppDetector.shared.clearTargetApp()
        }
    }

    /// Stop recording and transcribe
    public func stopRecordingAndTranscribe() async {
        guard isRecording else { return }

        print("VoiceFox: Stopping recording...")
        let audioBuffer = AudioEngine.shared.stopRecording()
        let recordingDuration = AudioEngine.shared.lastRecordingDuration
        isRecording = false

        guard !audioBuffer.isEmpty else {
            print("VoiceFox: No audio recorded")
            return
        }

        print("VoiceFox: Audio buffer size: \(audioBuffer.count) samples, duration: \(recordingDuration)s")

        // Start transcription
        isTranscribing = true

        do {
            // Check if model is ready
            guard ModelManager.shared.isModelReady else {
                print("VoiceFox: Model not downloaded")
                setError("Speech model not downloaded")
                isTranscribing = false
                return
            }

            print("VoiceFox: Starting transcription...")
            var result = try await ModelManager.shared.transcribe(audioBuffer: audioBuffer)

            // Apply corrections if in a dev app
            let isDevApp = AppDetector.shared.isDevApp
            if isDevApp {
                print("VoiceFox: Applying dev corrections...")
                result = await CorrectionPipeline.shared.process(result, isDevApp: isDevApp)
            }

            print("VoiceFox: Transcription result: \(result.text)")

            // Hide overlay immediately — before updating state to avoid flashing the result text
            OverlayWindowController.shared.hideOverlay()
            AppDetector.shared.clearTargetApp()
            HotkeyManager.shared.ensureEventTapActive()

            lastResult = result
            isTranscribing = false

            // Save to history (with audio if text is not empty)
            if !result.text.isEmpty && TextInjector.shared.shouldSaveToHistory {
                HistoryManager.shared.addItem(
                    from: result,
                    duration: recordingDuration,
                    audioBuffer: audioBuffer
                )
            }

            // Handle output based on settings
            if !result.text.isEmpty {
                let shouldPaste = TextInjector.shared.shouldPasteToActiveApp
                let shouldCopy = TextInjector.shared.shouldCopyToClipboard
                NSLog("VoiceFox: Output text: '%@', paste: %d, copy: %d", result.text, shouldPaste ? 1 : 0, shouldCopy ? 1 : 0)

                if shouldPaste {
                    // Inject text via clipboard + Cmd+V
                    // If copy is disabled, restore previous clipboard after pasting
                    NSLog("VoiceFox: Injecting text at cursor...")
                    try await TextInjector.shared.injectText(result.text, restoreClipboard: !shouldCopy)
                } else if shouldCopy {
                    // Copy only mode
                    NSLog("VoiceFox: Copying text to clipboard only...")
                    TextInjector.shared.copyToClipboard(result.text)
                } else {
                    // History only mode - do nothing with output
                    NSLog("VoiceFox: History only mode - text saved to history")
                }
            } else {
                NSLog("VoiceFox: No text to output (empty result)")
            }

        } catch {
            print("VoiceFox: Transcription failed: \(error)")

            // Hide overlay before updating state to avoid flashing error text
            OverlayWindowController.shared.hideOverlay()
            AppDetector.shared.clearTargetApp()
            HotkeyManager.shared.ensureEventTapActive()

            setError("Transcription failed: \(error.localizedDescription)")
            isTranscribing = false
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
