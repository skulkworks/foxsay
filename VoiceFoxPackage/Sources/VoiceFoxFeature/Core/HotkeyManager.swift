@preconcurrency import AppKit
@preconcurrency import Carbon.HIToolbox
import Foundation

/// Manages global hotkey for hold-to-talk functionality
@MainActor
public class HotkeyManager: ObservableObject {
    public static let shared = HotkeyManager()

    // MARK: - Activation Mode

    public enum ActivationMode: String, CaseIterable, Identifiable, Codable {
        case holdOrToggle = "holdOrToggle"
        case toggle = "toggle"
        case hold = "hold"
        case doubleTap = "doubleTap"

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .holdOrToggle: return "Hold or Toggle"
            case .toggle: return "Toggle"
            case .hold: return "Hold"
            case .doubleTap: return "Double Tap"
            }
        }

        public var description: String {
            switch self {
            case .holdOrToggle: return "Auto-detects based on duration"
            case .toggle: return "Tap to start/stop"
            case .hold: return "Record while pressed"
            case .doubleTap: return "Tap twice quickly"
            }
        }
    }

    // MARK: - Hotkey Modifier

    public enum HotkeyModifier: String, CaseIterable, Identifiable, Codable {
        case rightCommand = "rightCommand"
        case rightOption = "rightOption"
        case rightShift = "rightShift"
        case rightControl = "rightControl"
        case leftCommand = "leftCommand"
        case leftOption = "leftOption"
        case leftShift = "leftShift"
        case leftControl = "leftControl"
        case fn = "fn"

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .rightCommand: return "Right ⌘"
            case .rightOption: return "Right ⌥"
            case .rightShift: return "Right ⇧"
            case .rightControl: return "Right ⌃"
            case .leftCommand: return "Left ⌘"
            case .leftOption: return "Left ⌥"
            case .leftShift: return "Left ⇧"
            case .leftControl: return "Left ⌃"
            case .fn: return "Fn"
            }
        }

        public var shortName: String {
            switch self {
            case .rightCommand: return "Right ⌘"
            case .rightOption: return "Right ⌥"
            case .rightShift: return "Right ⇧"
            case .rightControl: return "Right ⌃"
            case .leftCommand: return "Left ⌘"
            case .leftOption: return "Left ⌥"
            case .leftShift: return "Left ⇧"
            case .leftControl: return "Left ⌃"
            case .fn: return "Fn"
            }
        }

        public var symbol: String {
            switch self {
            case .rightCommand, .leftCommand: return "⌘"
            case .rightOption, .leftOption: return "⌥"
            case .rightShift, .leftShift: return "⇧"
            case .rightControl, .leftControl: return "⌃"
            case .fn: return "Fn"
            }
        }

        public var side: String {
            switch self {
            case .rightCommand, .rightOption, .rightShift, .rightControl: return "Right"
            case .leftCommand, .leftOption, .leftShift, .leftControl: return "Left"
            case .fn: return ""
            }
        }

        var keyCode: CGKeyCode? {
            switch self {
            case .rightCommand: return 54  // kVK_RightCommand
            case .leftCommand: return 55   // kVK_Command
            case .rightOption: return 61   // kVK_RightOption
            case .leftOption: return 58    // kVK_Option
            case .rightShift: return 60    // kVK_RightShift
            case .leftShift: return 56     // kVK_Shift
            case .rightControl: return 62  // kVK_RightControl
            case .leftControl: return 59   // kVK_Control
            case .fn: return 63            // kVK_Function
            }
        }

        var cgEventFlags: CGEventFlags {
            switch self {
            case .rightCommand, .leftCommand: return .maskCommand
            case .rightOption, .leftOption: return .maskAlternate
            case .rightShift, .leftShift: return .maskShift
            case .rightControl, .leftControl: return .maskControl
            case .fn: return .maskSecondaryFn
            }
        }

        /// Group modifiers by side for better UI organization
        public static var rightSideModifiers: [HotkeyModifier] {
            [.rightCommand, .rightOption, .rightShift, .rightControl]
        }

        public static var leftSideModifiers: [HotkeyModifier] {
            [.leftCommand, .leftOption, .leftShift, .leftControl]
        }
    }

    // MARK: - Published Properties

    @Published public var selectedModifier: HotkeyModifier {
        didSet {
            UserDefaults.standard.set(selectedModifier.rawValue, forKey: "hotkeyModifier")
            restartMonitoring()
        }
    }

    @Published public var activationMode: ActivationMode {
        didSet {
            UserDefaults.standard.set(activationMode.rawValue, forKey: "hotkeyActivationMode")
        }
    }

    @Published public var escapeToCancel: Bool {
        didSet {
            UserDefaults.standard.set(escapeToCancel, forKey: "hotkeyEscapeToCancel")
        }
    }

    @Published public private(set) var isHotkeyPressed = false
    @Published public private(set) var isEnabled = true

    // For double-tap detection
    private var lastTapTime: Date?
    private let doubleTapThreshold: TimeInterval = 0.3

    // For hold-or-toggle auto-detection
    private var keyDownTime: Date?
    private let holdThreshold: TimeInterval = 0.3  // If held longer than this, it's a hold

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var lastKeyDown: CGKeyCode?

    /// Callback when hotkey is pressed (start recording)
    public var onHotkeyDown: (() -> Void)?

    /// Callback when hotkey is released (stop recording)
    public var onHotkeyUp: (() -> Void)?

    /// Callback when recording is cancelled (e.g., escape key)
    public var onCancel: (() -> Void)?

    private init() {
        let savedModifier = UserDefaults.standard.string(forKey: "hotkeyModifier") ?? "rightOption"
        selectedModifier = HotkeyModifier(rawValue: savedModifier) ?? .rightOption

        let savedMode = UserDefaults.standard.string(forKey: "hotkeyActivationMode") ?? "hold"
        activationMode = ActivationMode(rawValue: savedMode) ?? .hold

        escapeToCancel = UserDefaults.standard.object(forKey: "hotkeyEscapeToCancel") as? Bool ?? true

        startMonitoring()
    }

    // Note: deinit cannot call MainActor-isolated methods
    // Cleanup is handled when the app terminates

    public func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if enabled {
            startMonitoring()
        } else {
            stopMonitoring()
        }
    }

    private func startMonitoring() {
        guard eventTap == nil else { return }

        // Create event tap to monitor key events
        let eventMask =
            (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)

        // Store self reference for callback
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { _, type, event, userInfo -> Unmanaged<CGEvent>? in
                guard let userInfo = userInfo else { return Unmanaged.passUnretained(event) }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userInfo).takeUnretainedValue()

                // Handle synchronously to avoid async issues
                let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
                let flags = event.flags

                // Debug: log all flagsChanged events (only for modifier keys we care about)
                if type == .flagsChanged && (keyCode == 54 || keyCode == 55 || keyCode == 58 || keyCode == 61 || keyCode == 59 || keyCode == 62 || keyCode == 63) {
                    NSLog("VoiceFox: Event tap flagsChanged - keyCode: %d, flags: %lu", keyCode, flags.rawValue)
                }

                DispatchQueue.main.async {
                    manager.handleEventSync(type: type, keyCode: keyCode, flags: flags)
                }

                return Unmanaged.passUnretained(event)
            },
            userInfo: selfPointer
        )

        guard let tap = eventTap else {
            NSLog("VoiceFox: Failed to create event tap - accessibility permission may be required")
            return
        }

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        NSLog("VoiceFox: Hotkey monitoring started for %@ (expecting keyCode: %d)", selectedModifier.displayName, selectedModifier.keyCode ?? 0)
    }

    private func stopMonitoring() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }

        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }

        eventTap = nil
        runLoopSource = nil
        isHotkeyPressed = false

        print("VoiceFox: Hotkey monitoring stopped")
    }

    private func restartMonitoring() {
        stopMonitoring()
        if isEnabled {
            startMonitoring()
        }
    }

    private func handleEventSync(type: CGEventType, keyCode: CGKeyCode, flags: CGEventFlags) {
        guard isEnabled else { return }

        // Handle Escape key to cancel recording
        if escapeToCancel && type == .keyDown && keyCode == 53 {  // 53 = Escape
            if isHotkeyPressed {
                NSLog("VoiceFox: Escape pressed - cancelling recording")
                isHotkeyPressed = false
                lastKeyDown = nil
                keyDownTime = nil
                lastTapTime = nil
                onCancel?()
            }
            return
        }

        if type == .flagsChanged {
            // Check if our specific modifier key was pressed/released
            guard let targetKeyCode = selectedModifier.keyCode else { return }

            // For modifier keys, we need to check if our specific key is being held
            // flagsChanged fires for both press and release
            let isModifierActive = flags.contains(selectedModifier.cgEventFlags)

            // Debug: log events for our target key
            if keyCode == targetKeyCode {
                NSLog("VoiceFox: Target key event - keyCode: %d, isModifierActive: %d, isHotkeyPressed: %d, mode: %@",
                      keyCode, isModifierActive ? 1 : 0, isHotkeyPressed ? 1 : 0, activationMode.rawValue)
            }

            // Handle based on activation mode
            if keyCode == targetKeyCode {
                switch activationMode {
                case .hold:
                    handleHoldMode(isModifierActive: isModifierActive, keyCode: keyCode)

                case .toggle:
                    handleToggleMode(isModifierActive: isModifierActive, keyCode: keyCode)

                case .doubleTap:
                    handleDoubleTapMode(isModifierActive: isModifierActive, keyCode: keyCode)

                case .holdOrToggle:
                    handleHoldOrToggleMode(isModifierActive: isModifierActive, keyCode: keyCode)
                }
            }
        }
    }

    // MARK: - Activation Mode Handlers

    private func handleHoldMode(isModifierActive: Bool, keyCode: CGKeyCode) {
        if isModifierActive && !isHotkeyPressed {
            NSLog("VoiceFox: [Hold] Hotkey DOWN")
            isHotkeyPressed = true
            onHotkeyDown?()
        } else if !isModifierActive && isHotkeyPressed {
            // Release when modifier is no longer active, regardless of which key triggered the event
            NSLog("VoiceFox: [Hold] Hotkey UP")
            isHotkeyPressed = false
            onHotkeyUp?()
        }
    }

    private func handleToggleMode(isModifierActive: Bool, keyCode: CGKeyCode) {
        // Only trigger on key down (press)
        if isModifierActive && lastKeyDown != keyCode {
            lastKeyDown = keyCode
            if !isHotkeyPressed {
                NSLog("VoiceFox: [Toggle] Starting recording")
                isHotkeyPressed = true
                onHotkeyDown?()
            } else {
                NSLog("VoiceFox: [Toggle] Stopping recording")
                isHotkeyPressed = false
                onHotkeyUp?()
            }
        } else if !isModifierActive {
            lastKeyDown = nil
        }
    }

    private func handleDoubleTapMode(isModifierActive: Bool, keyCode: CGKeyCode) {
        // Only trigger on key down (press)
        if isModifierActive && lastKeyDown != keyCode {
            lastKeyDown = keyCode
            let now = Date()

            if let lastTap = lastTapTime, now.timeIntervalSince(lastTap) < doubleTapThreshold {
                // Double tap detected
                if !isHotkeyPressed {
                    NSLog("VoiceFox: [DoubleTap] Starting recording")
                    isHotkeyPressed = true
                    onHotkeyDown?()
                } else {
                    NSLog("VoiceFox: [DoubleTap] Stopping recording")
                    isHotkeyPressed = false
                    onHotkeyUp?()
                }
                lastTapTime = nil
            } else {
                // First tap
                lastTapTime = now
            }
        } else if !isModifierActive {
            lastKeyDown = nil
        }
    }

    private func handleHoldOrToggleMode(isModifierActive: Bool, keyCode: CGKeyCode) {
        if isModifierActive && lastKeyDown != keyCode {
            // Key pressed
            lastKeyDown = keyCode
            keyDownTime = Date()

            if !isHotkeyPressed {
                NSLog("VoiceFox: [HoldOrToggle] Key down - starting recording")
                isHotkeyPressed = true
                onHotkeyDown?()
            }
        } else if !isModifierActive && lastKeyDown == keyCode {
            // Key released
            lastKeyDown = nil

            if isHotkeyPressed {
                let holdDuration = keyDownTime.map { Date().timeIntervalSince($0) } ?? 0
                keyDownTime = nil

                if holdDuration < holdThreshold {
                    // Short press - toggle mode (keep recording)
                    NSLog("VoiceFox: [HoldOrToggle] Short press (%.2fs) - toggle mode, continuing", holdDuration)
                    // Don't stop recording - user needs to tap again
                } else {
                    // Long press - hold mode (stop recording)
                    NSLog("VoiceFox: [HoldOrToggle] Long hold (%.2fs) - hold mode, stopping", holdDuration)
                    isHotkeyPressed = false
                    onHotkeyUp?()
                }
            } else {
                // Recording was stopped by a previous toggle tap
                keyDownTime = nil
            }
        } else if !isModifierActive && isHotkeyPressed && lastKeyDown == nil {
            // This handles the case where we're in toggle mode and user taps again to stop
            // (The key was pressed while we were already recording)
        }
    }

    /// Stop recording if in toggle/double-tap mode (called when user taps again)
    public func stopToggleRecording() {
        if isHotkeyPressed && (activationMode == .toggle || activationMode == .doubleTap || activationMode == .holdOrToggle) {
            NSLog("VoiceFox: Manually stopping toggle recording")
            isHotkeyPressed = false
            onHotkeyUp?()
        }
    }

    /// Check if accessibility permissions are granted (does NOT show prompt)
    @MainActor
    public static func checkAccessibilityPermission() -> Bool {
        // Use prompt: false to just check status without showing system dialog
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: false] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Request accessibility permissions (opens System Settings)
    @MainActor
    public static func requestAccessibilityPermission() {
        // Open System Settings directly to accessibility
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Check if the event tap is still active and re-enable if needed
    public func ensureEventTapActive() {
        if let tap = eventTap {
            let isEnabled = CGEvent.tapIsEnabled(tap: tap)
            if !isEnabled {
                NSLog("VoiceFox: Event tap was disabled, re-enabling...")
                CGEvent.tapEnable(tap: tap, enable: true)
            }
        } else {
            NSLog("VoiceFox: Event tap is nil, restarting monitoring...")
            startMonitoring()
        }
    }
}
