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

/// Represents an audio input device
public struct AudioInputDevice: Identifiable, Equatable, Hashable, Sendable {
    public let id: AudioDeviceID
    public let name: String
    public let uid: String

    public static let defaultDevice = AudioInputDevice(id: 0, name: "Default", uid: "default")
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
    @Published public private(set) var availableDevices: [AudioInputDevice] = []

    @Published public var selectedDeviceUID: String {
        didSet {
            UserDefaults.standard.set(selectedDeviceUID, forKey: "selectedAudioInputDevice")
            if isRecording {
                // Restart recording with new device
                let buffer = stopRecording()
                // Note: buffer will be lost, but this is expected behavior when switching devices
                _ = buffer
                try? startRecording()
            }
        }
    }

    private var levelUpdateTimer: Timer?
    private var recordingStartTime: Date?

    private init() {
        // Load saved preferences
        selectedDeviceUID = UserDefaults.standard.string(forKey: "selectedAudioInputDevice") ?? "default"
        muteWhileRecording = UserDefaults.standard.bool(forKey: "muteWhileRecording")

        // Only check status on init, don't request permission
        updatePermissionStatus()

        // Enumerate available devices
        refreshAvailableDevices()

        // Listen for device changes
        setupDeviceChangeNotification()
    }

    // MARK: - Device Management

    /// Refresh the list of available audio input devices
    public func refreshAvailableDevices() {
        var devices: [AudioInputDevice] = [.defaultDevice]

        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize
        )

        guard status == noErr else {
            print("VoiceFox: Failed to get audio devices data size")
            availableDevices = devices
            return
        }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)

        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceIDs
        )

        guard status == noErr else {
            print("VoiceFox: Failed to get audio devices")
            availableDevices = devices
            return
        }

        for deviceID in deviceIDs {
            // Check if device has input channels
            var inputChannelsAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreamConfiguration,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )

            var inputChannelsSize: UInt32 = 0
            status = AudioObjectGetPropertyDataSize(deviceID, &inputChannelsAddress, 0, nil, &inputChannelsSize)

            if status == noErr && inputChannelsSize > 0 {
                let bufferListPointer = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: 1)
                defer { bufferListPointer.deallocate() }

                status = AudioObjectGetPropertyData(deviceID, &inputChannelsAddress, 0, nil, &inputChannelsSize, bufferListPointer)

                if status == noErr {
                    var inputChannels: UInt32 = 0

                    // Use UnsafeMutableAudioBufferListPointer for proper iteration
                    let audioBufferList = UnsafeMutableAudioBufferListPointer(bufferListPointer)
                    for buffer in audioBufferList {
                        inputChannels += buffer.mNumberChannels
                    }

                    if inputChannels > 0 {
                        // This is an input device
                        if let name = getDeviceName(deviceID), let uid = getDeviceUID(deviceID) {
                            devices.append(AudioInputDevice(id: deviceID, name: name, uid: uid))
                        }
                    }
                }
            }
        }

        availableDevices = devices
        print("VoiceFox: Found \(devices.count) audio input devices")
    }

    private func getDeviceName(_ deviceID: AudioDeviceID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var name: CFString?
        var dataSize = UInt32(MemoryLayout<CFString?>.size)

        let status = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &dataSize, &name)

        if status == noErr, let name = name {
            return name as String
        }
        return nil
    }

    private func getDeviceUID(_ deviceID: AudioDeviceID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var uid: CFString?
        var dataSize = UInt32(MemoryLayout<CFString?>.size)

        let status = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &dataSize, &uid)

        if status == noErr, let uid = uid {
            return uid as String
        }
        return nil
    }

    private func getDeviceID(forUID uid: String) -> AudioDeviceID? {
        if uid == "default" {
            return nil  // Use system default
        }

        for device in availableDevices {
            if device.uid == uid {
                return device.id
            }
        }
        return nil
    }

    private func setupDeviceChangeNotification() {
        // Set up notification for device changes
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            DispatchQueue.main
        ) { [weak self] _, _ in
            Task { @MainActor in
                self?.refreshAvailableDevices()
            }
        }
    }

    /// Get the currently selected device name for display
    public var selectedDeviceName: String {
        if selectedDeviceUID == "default" {
            return "Default"
        }
        return availableDevices.first { $0.uid == selectedDeviceUID }?.name ?? "Default"
    }

    // MARK: - System Audio Muting

    @Published public var muteWhileRecording: Bool {
        didSet {
            UserDefaults.standard.set(muteWhileRecording, forKey: "muteWhileRecording")
        }
    }

    private var previousSystemVolume: Float?

    private func muteSystemAudio() {
        guard muteWhileRecording else { return }

        // Get default output device
        var defaultOutputDeviceID = AudioDeviceID()
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &defaultOutputDeviceID
        )

        guard status == noErr else {
            print("VoiceFox: Failed to get default output device")
            return
        }

        // Get current volume
        var volumeAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        var currentVolume: Float32 = 0
        dataSize = UInt32(MemoryLayout<Float32>.size)

        let volumeStatus = AudioObjectGetPropertyData(
            defaultOutputDeviceID,
            &volumeAddress,
            0,
            nil,
            &dataSize,
            &currentVolume
        )

        if volumeStatus == noErr {
            previousSystemVolume = currentVolume

            // Set volume to 0
            var newVolume: Float32 = 0
            AudioObjectSetPropertyData(
                defaultOutputDeviceID,
                &volumeAddress,
                0,
                nil,
                dataSize,
                &newVolume
            )
            print("VoiceFox: Muted system audio (was \(currentVolume))")
        }
    }

    private func restoreSystemAudio() {
        guard muteWhileRecording, let previousVolume = previousSystemVolume else { return }

        // Get default output device
        var defaultOutputDeviceID = AudioDeviceID()
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &defaultOutputDeviceID
        )

        guard status == noErr else { return }

        // Restore volume
        var volumeAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        var volume = previousVolume
        dataSize = UInt32(MemoryLayout<Float32>.size)

        AudioObjectSetPropertyData(
            defaultOutputDeviceID,
            &volumeAddress,
            0,
            nil,
            dataSize,
            &volume
        )

        previousSystemVolume = nil
        print("VoiceFox: Restored system audio to \(previousVolume)")
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

        // Mute system audio if enabled
        muteSystemAudio()

        // Create audio engine
        audioEngine = AVAudioEngine()
        guard let engine = audioEngine else {
            restoreSystemAudio()
            throw AudioEngineError.engineCreationFailed
        }

        // Set input device if not using default
        if selectedDeviceUID != "default", let deviceID = getDeviceID(forUID: selectedDeviceUID) {
            setInputDevice(deviceID, for: engine)
        }

        inputNode = engine.inputNode
        guard let node = inputNode else {
            restoreSystemAudio()
            throw AudioEngineError.noInputNode
        }

        // Get input format - check for valid format
        let inputFormat = node.outputFormat(forBus: 0)
        print("VoiceFox: Input format - sampleRate: \(inputFormat.sampleRate), channels: \(inputFormat.channelCount), device: \(selectedDeviceName)")

        // Validate input format
        guard inputFormat.sampleRate > 0 && inputFormat.channelCount > 0 else {
            print("VoiceFox: Invalid input format")
            restoreSystemAudio()
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
            restoreSystemAudio()
            throw error
        }
    }

    private func setInputDevice(_ deviceID: AudioDeviceID, for engine: AVAudioEngine) {
        var deviceID = deviceID
        let inputUnit = engine.inputNode.audioUnit!

        let status = AudioUnitSetProperty(
            inputUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &deviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )

        if status != noErr {
            print("VoiceFox: Failed to set input device: \(status)")
        } else {
            print("VoiceFox: Set input device to ID \(deviceID)")
        }
    }

    private func startLevelUpdateTimer() {
        levelUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.025, repeats: true) { [weak self] _ in
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

        // Restore system audio
        restoreSystemAudio()

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
