@preconcurrency import AVFoundation
import Foundation

/// Thread-safe audio buffer storage - completely independent, no actor isolation
final class AudioBufferStorage: @unchecked Sendable {
    private var buffer: [Float] = []
    private let lock = NSLock()
    var currentLevel: Float = 0

    func append(_ samples: [Float]) {
        lock.lock()
        buffer.append(contentsOf: samples)
        lock.unlock()
    }

    func getAndClear() -> [Float] {
        lock.lock()
        let result = buffer
        buffer.removeAll()
        lock.unlock()
        return result
    }

    func clear() {
        lock.lock()
        buffer.removeAll()
        lock.unlock()
    }
}

/// Audio tap processor - handles audio on realtime thread, completely non-isolated
final class AudioTapProcessor: @unchecked Sendable {
    let storage: AudioBufferStorage
    let targetSampleRate: Double
    private var converter: AVAudioConverter?
    private var outputFormat: AVAudioFormat?

    init(storage: AudioBufferStorage, targetSampleRate: Double) {
        self.storage = storage
        self.targetSampleRate = targetSampleRate
    }

    func configure(inputFormat: AVAudioFormat) {
        outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: false
        )!

        if inputFormat.sampleRate != targetSampleRate || inputFormat.channelCount != 1 {
            converter = AVAudioConverter(from: inputFormat, to: outputFormat!)
        } else {
            converter = nil
        }
    }

    func processBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let outputFormat = outputFormat else { return }

        let samples: [Float]
        let inputFormat = buffer.format

        if let conv = converter {
            // Convert to 16kHz mono
            let frameCount = AVAudioFrameCount(
                Double(buffer.frameLength) * targetSampleRate / inputFormat.sampleRate
            )
            guard
                let convertedBuffer = AVAudioPCMBuffer(
                    pcmFormat: outputFormat,
                    frameCapacity: frameCount
                )
            else { return }

            var error: NSError?
            conv.convert(to: convertedBuffer, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }

            if error != nil { return }

            samples = Array(
                UnsafeBufferPointer(
                    start: convertedBuffer.floatChannelData?[0],
                    count: Int(convertedBuffer.frameLength)
                ))
        } else {
            // Already in correct format
            samples = Array(
                UnsafeBufferPointer(
                    start: buffer.floatChannelData?[0],
                    count: Int(buffer.frameLength)
                ))
        }

        // Calculate audio level for visualization
        let level = samples.reduce(0) { max($0, abs($1)) }

        // Update storage
        storage.append(samples)
        storage.currentLevel = level
    }
}

/// Audio engine for capturing microphone input at 16kHz mono
@MainActor
public class AudioEngine: ObservableObject {
    public static let shared = AudioEngine()

    /// Target sample rate for transcription
    public static let targetSampleRate: Double = 16000

    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?

    // Separate storage and processor that can be safely accessed from audio thread
    private let storage = AudioBufferStorage()
    private var tapProcessor: AudioTapProcessor?

    @Published public private(set) var isRecording = false
    @Published public private(set) var hasPermission = false
    @Published public private(set) var audioLevel: Float = 0
    @Published public private(set) var recordingDuration: TimeInterval = 0

    private var levelUpdateTimer: Timer?
    private var recordingStartTime: Date?

    private init() {
        // Only check status on init, don't request permission
        updatePermissionStatus()
    }

    /// Update permission status without prompting
    public func updatePermissionStatus() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            hasPermission = true
        case .notDetermined, .denied, .restricted:
            hasPermission = false
        @unknown default:
            hasPermission = false
        }
    }

    /// Request microphone permission (shows system prompt if needed)
    public func checkPermission() async {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            hasPermission = true
        case .notDetermined:
            hasPermission = await AVCaptureDevice.requestAccess(for: .audio)
        case .denied, .restricted:
            hasPermission = false
        @unknown default:
            hasPermission = false
        }
    }

    /// Start recording audio
    public func startRecording() throws {
        guard hasPermission else {
            throw AudioEngineError.noPermission
        }

        guard !isRecording else { return }

        // Clear previous buffer
        storage.clear()

        // Create audio engine
        audioEngine = AVAudioEngine()
        guard let engine = audioEngine else {
            throw AudioEngineError.engineCreationFailed
        }

        inputNode = engine.inputNode
        guard let node = inputNode else {
            throw AudioEngineError.noInputNode
        }

        // Get input format - check for valid format
        let inputFormat = node.outputFormat(forBus: 0)
        print("VoiceFox: Input format - sampleRate: \(inputFormat.sampleRate), channels: \(inputFormat.channelCount)")

        // Validate input format
        guard inputFormat.sampleRate > 0 && inputFormat.channelCount > 0 else {
            print("VoiceFox: Invalid input format")
            throw AudioEngineError.noInputNode
        }

        // Create tap processor
        let processor = AudioTapProcessor(storage: storage, targetSampleRate: Self.targetSampleRate)
        processor.configure(inputFormat: inputFormat)
        tapProcessor = processor

        // Install tap to capture audio - use nonisolated helper to avoid actor context
        Self.installAudioTap(on: node, format: inputFormat, processor: processor)

        // Start engine
        do {
            try engine.start()
            isRecording = true
            recordingStartTime = Date()
            recordingDuration = 0
            print("VoiceFox: Audio engine started successfully")

            // Start timer to poll audio level for UI updates
            startLevelUpdateTimer()
        } catch {
            print("VoiceFox: Failed to start audio engine: \(error)")
            // Clean up
            inputNode?.removeTap(onBus: 0)
            audioEngine = nil
            inputNode = nil
            tapProcessor = nil
            throw error
        }
    }

    private func startLevelUpdateTimer() {
        levelUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.audioLevel = self.storage.currentLevel
            }
        }
    }

    private func stopLevelUpdateTimer() {
        levelUpdateTimer?.invalidate()
        levelUpdateTimer = nil
    }

    /// Stop recording and return the captured audio buffer
    public func stopRecording() -> [Float] {
        guard isRecording else { return [] }

        // Calculate final duration
        if let startTime = recordingStartTime {
            recordingDuration = Date().timeIntervalSince(startTime)
        }
        recordingStartTime = nil

        stopLevelUpdateTimer()
        inputNode?.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        inputNode = nil
        tapProcessor = nil
        isRecording = false
        audioLevel = 0

        return storage.getAndClear()
    }

    /// Get the last recording duration
    public var lastRecordingDuration: TimeInterval {
        recordingDuration
    }

    /// Get the current audio buffer without stopping
    public func getCurrentBuffer() -> [Float] {
        return storage.getAndClear()
    }

    /// Install audio tap from a nonisolated context to avoid actor isolation in the callback
    nonisolated private static func installAudioTap(
        on node: AVAudioInputNode,
        format: AVAudioFormat,
        processor: AudioTapProcessor
    ) {
        node.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            processor.processBuffer(buffer)
        }
    }
}

/// Errors that can occur in AudioEngine
public enum AudioEngineError: LocalizedError {
    case noPermission
    case engineCreationFailed
    case noInputNode

    public var errorDescription: String? {
        switch self {
        case .noPermission:
            return "Microphone access not granted"
        case .engineCreationFailed:
            return "Failed to create audio engine"
        case .noInputNode:
            return "No audio input device available"
        }
    }
}
