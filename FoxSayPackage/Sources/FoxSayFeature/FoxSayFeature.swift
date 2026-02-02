// FoxSay - Speech-to-Text for Developers
// MIT License

@_exported import Foundation
@_exported import SwiftUI

// Re-export public types
public typealias FoxSayAppState = AppState
public typealias FoxSayTranscriptionResult = TranscriptionResult

/// Main coordinator for FoxSay functionality
@MainActor
public class FoxSayCoordinator: ObservableObject {
    public static let shared = FoxSayCoordinator()

    private let audioEngine = AudioEngine.shared
    private let engineManager = EngineManager.shared
    private let hotkeyManager = HotkeyManager.shared
    private let appDetector = AppDetector.shared
    private let correctionPipeline = CorrectionPipeline.shared
    private let textInjector = TextInjector.shared
    private let menuBarManager = MenuBarManager.shared
    private let appState = AppState.shared

    private init() {
        setupHotkeyCallbacks()
    }

    /// Initialize and start FoxSay
    public func start() async {
        // Request permissions
        await audioEngine.checkPermission()

        // Check accessibility (needed for auto-paste)
        if !HotkeyManager.checkAccessibilityPermission() {
            print("FoxSay: Accessibility permission not granted - auto-paste will not work")
        }
    }

    private func setupHotkeyCallbacks() {
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
    }

    /// Start recording audio
    public func startRecording() async {
        guard audioEngine.hasPermission else {
            appState.setError("Microphone permission not granted")
            return
        }

        do {
            try audioEngine.startRecording()
            appState.setRecording(true)
            menuBarManager.setRecording(true)
        } catch {
            appState.setError(error.localizedDescription)
        }
    }

    /// Stop recording and transcribe
    public func stopRecordingAndTranscribe() async {
        guard audioEngine.isRecording else { return }

        // Stop recording
        let audioBuffer = audioEngine.stopRecording()
        appState.setRecording(false)
        menuBarManager.setRecording(false)

        // Check if we have enough audio
        guard audioBuffer.count > Int(AudioEngine.targetSampleRate * 0.3) else {
            // Less than 300ms of audio, ignore
            return
        }

        // Start transcription
        appState.setTranscribing(true)
        menuBarManager.setProcessing(true)

        defer {
            appState.setTranscribing(false)
            menuBarManager.setProcessing(false)
        }

        do {
            // Transcribe
            var result = try await engineManager.transcribe(audioBuffer: audioBuffer)

            // Apply processing pipeline
            result = await correctionPipeline.process(result)

            // Update state
            appState.setResult(result)

            // Inject text
            try await textInjector.injectText(result.text)

        } catch {
            appState.setError(error.localizedDescription)
        }
    }

    /// Cancel any ongoing operation
    public func cancel() async {
        if audioEngine.isRecording {
            _ = audioEngine.stopRecording()
            appState.setRecording(false)
            menuBarManager.setRecording(false)
        }

        await engineManager.cancelTranscription()
        appState.setTranscribing(false)
        menuBarManager.setProcessing(false)
    }
}
