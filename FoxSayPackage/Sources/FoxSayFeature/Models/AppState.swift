import Foundation
import SwiftUI

/// Structured overlay error for display in the recording overlay
public struct OverlayError: Equatable {
    public let icon: String
    public let title: String
    public let subtitle: String

    public init(icon: String, title: String, subtitle: String) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
    }
}

/// Shared app state for FoxSay
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

    /// Structured error to display briefly in the overlay (auto-dismisses)
    @Published public var overlayError: OverlayError?

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
    @Published public var frontmostAppBundleId: String? {
        didSet {
            handleAppChange(from: oldValue, to: frontmostAppBundleId)
        }
    }

    /// Previous prompt ID before auto-switch (for manual override tracking)
    private var previousPromptIdBeforeAutoSwitch: UUID?

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

        hotkeyManager.onPromptSelector = { [weak self] in
            Task { @MainActor in
                self?.togglePromptSelector()
            }
        }

        print("FoxSay: Hotkey callbacks configured")
    }

    /// Cancel recording without transcribing
    public func cancelRecording() {
        guard isRecording else { return }

        NSLog("FoxSay: Recording cancelled")
        _ = AudioEngine.shared.stopRecording()
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
            print("FoxSay: No microphone permission - requesting...")
            await AudioEngine.shared.checkPermission()
        }

        guard AudioEngine.shared.hasPermission else {
            print("FoxSay: Microphone permission denied")
            showOverlayError(OverlayError(
                icon: "mic.slash.fill",
                title: "Microphone Permission Required",
                subtitle: "Grant microphone access in System Settings"
            ))
            AppDetector.shared.clearTargetApp()
            return
        }

        // Refresh model state from disk and check readiness
        await ModelManager.shared.refreshModelReadyState()
        guard ModelManager.shared.isModelReady else {
            print("FoxSay: Speech model not available on disk")
            showOverlayError(OverlayError(
                icon: "waveform.badge.exclamationmark",
                title: "No Speech Model Available",
                subtitle: "Download a model in Settings to use FoxSay"
            ))
            AppDetector.shared.clearTargetApp()
            return
        }

        do {
            print("FoxSay: Starting recording...")
            try AudioEngine.shared.startRecording()
            print("FoxSay: Recording started successfully")
            isRecording = true
            errorMessage = nil

            // Show overlay
            OverlayWindowController.shared.showOverlay()
        } catch let error as AudioEngineError where error == .noMicrophoneDetected {
            print("FoxSay: No microphone detected")
            showOverlayError(OverlayError(
                icon: "mic.slash.fill",
                title: "No Microphone Detected",
                subtitle: "Connect a microphone and try again"
            ))
            AppDetector.shared.clearTargetApp()
        } catch {
            print("FoxSay: Failed to start recording: \(error)")
            showOverlayError(OverlayError(
                icon: "exclamationmark.triangle.fill",
                title: "Recording Failed",
                subtitle: error.localizedDescription
            ))
            AppDetector.shared.clearTargetApp()
        }
    }

    /// Stop recording and transcribe
    public func stopRecordingAndTranscribe() async {
        guard isRecording else { return }

        print("FoxSay: Stopping recording...")
        let audioBuffer = AudioEngine.shared.stopRecording()
        let recordingDuration = AudioEngine.shared.lastRecordingDuration
        isRecording = false

        guard !audioBuffer.isEmpty else {
            print("FoxSay: No audio recorded")
            OverlayWindowController.shared.hideOverlay()
            AppDetector.shared.clearTargetApp()
            HotkeyManager.shared.ensureMonitoringActive()
            showOverlayError(OverlayError(
                icon: "waveform.slash",
                title: "No Audio Detected",
                subtitle: "Hold the key longer to record"
            ))
            return
        }

        print("FoxSay: Audio buffer size: \(audioBuffer.count) samples, duration: \(recordingDuration)s")

        // Start transcription
        isTranscribing = true

        do {
            // Check if model is ready
            guard ModelManager.shared.isModelReady else {
                print("FoxSay: Model not downloaded")
                OverlayWindowController.shared.hideOverlay()
                AppDetector.shared.clearTargetApp()
                HotkeyManager.shared.ensureMonitoringActive()
                showOverlayError(OverlayError(
                    icon: "waveform.badge.exclamationmark",
                    title: "No Speech Model Available",
                    subtitle: "Download a model in Settings to use FoxSay"
                ))
                isTranscribing = false
                return
            }

            print("FoxSay: Starting transcription...")
            var result = try await ModelManager.shared.transcribe(audioBuffer: audioBuffer)

            // Apply processing pipeline (markdown preprocessing, prompts, etc.)
            print("FoxSay: Processing transcription...")
            result = await CorrectionPipeline.shared.process(result)

            print("FoxSay: Transcription result: \(result.text)")

            // Hide overlay immediately — before updating state to avoid flashing the result text
            OverlayWindowController.shared.hideOverlay()
            AppDetector.shared.clearTargetApp()
            HotkeyManager.shared.ensureMonitoringActive()

            lastResult = result
            isTranscribing = false

            // Save to history (with audio if text is not empty)
            if !result.text.isEmpty && TextInjector.shared.shouldSaveToHistory {
                HistoryManager.shared.addItem(
                    from: result,
                    duration: recordingDuration,
                    audioBuffer: audioBuffer
                )
                // Record session for dashboard statistics
                // Create a temporary HistoryItem for statistics (without audio file reference)
                let statsItem = HistoryItem(
                    text: result.text,
                    originalText: result.originalText,
                    duration: recordingDuration,
                    processingTime: result.processingTime,
                    confidence: result.confidence,
                    wasDevCorrected: result.wasDevCorrected
                )
                StatisticsManager.shared.recordSession(from: statsItem)
            }

            // Handle output based on settings
            if !result.text.isEmpty {
                let shouldPaste = TextInjector.shared.shouldPasteToActiveApp
                let shouldCopy = TextInjector.shared.shouldCopyToClipboard
                NSLog("FoxSay: Output text: '%@', paste: %d, copy: %d", result.text, shouldPaste ? 1 : 0, shouldCopy ? 1 : 0)

                if shouldPaste {
                    // Inject text via clipboard + Cmd+V
                    // If copy is disabled, restore previous clipboard after pasting
                    NSLog("FoxSay: Injecting text at cursor...")
                    try await TextInjector.shared.injectText(result.text, restoreClipboard: !shouldCopy)
                } else if shouldCopy {
                    // Copy only mode
                    NSLog("FoxSay: Copying text to clipboard only...")
                    TextInjector.shared.copyToClipboard(result.text)
                } else {
                    // History only mode - do nothing with output
                    NSLog("FoxSay: History only mode - text saved to history")
                }
            } else {
                NSLog("FoxSay: No text to output (empty result)")
            }

        } catch {
            print("FoxSay: Transcription failed: \(error)")

            // Hide overlay before showing error to avoid flashing
            OverlayWindowController.shared.hideOverlay()
            AppDetector.shared.clearTargetApp()
            HotkeyManager.shared.ensureMonitoringActive()

            isTranscribing = false
            showOverlayError(OverlayError(
                icon: "exclamationmark.triangle.fill",
                title: "Transcription Failed",
                subtitle: error.localizedDescription
            ))
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

    /// Show a structured error briefly in the overlay, then auto-dismiss
    public func showOverlayError(_ error: OverlayError) {
        overlayError = error
        OverlayWindowController.shared.showOverlay()

        // Auto-dismiss after 3 seconds
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            overlayError = nil
            OverlayWindowController.shared.hideOverlay()
        }
    }

    // MARK: - App-based Prompt Auto-switching

    /// Handle app changes for automatic prompt switching
    private func handleAppChange(from oldBundleId: String?, to newBundleId: String?) {
        guard let newBundleId = newBundleId else { return }

        // Check if the new app has a default prompt assigned
        if let defaultPrompt = AppPromptManager.shared.getDefaultPrompt(forBundleId: newBundleId) {
            let promptManager = PromptManager.shared

            // Only auto-switch if the user hasn't manually overridden
            if promptManager.activePromptId != defaultPrompt.id {
                // Store previous prompt to detect manual override
                previousPromptIdBeforeAutoSwitch = promptManager.activePromptId
                promptManager.activatePrompt(id: defaultPrompt.id)
                print("FoxSay: Auto-switched to prompt '\(defaultPrompt.displayName)' for app \(newBundleId)")
            }
        }
    }

    /// Show the prompt selector overlay
    public func showPromptSelector() {
        PromptSelectorWindowController.shared.showSelector()
    }

    /// Hide the prompt selector overlay
    public func hidePromptSelector() {
        PromptSelectorWindowController.shared.hideSelector()
    }

    /// Toggle the prompt selector overlay
    public func togglePromptSelector() {
        PromptSelectorWindowController.shared.toggleSelector()
    }
}
