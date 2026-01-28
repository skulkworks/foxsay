@preconcurrency import AppKit
@preconcurrency import Carbon.HIToolbox
import Foundation

/// Manages global hotkey for hold-to-talk functionality.
/// Uses NSEvent monitors (not CGEventTap) to avoid requiring Accessibility permission for hotkey detection.
/// Accessibility permission is only needed for text injection (auto-paste), which is a legitimate accessibility use.
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

        var keyCode: UInt16? {
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

        var modifierFlags: NSEvent.ModifierFlags {
            switch self {
            case .rightCommand, .leftCommand: return .command
            case .rightOption, .leftOption: return .option
            case .rightShift, .leftShift: return .shift
            case .rightControl, .leftControl: return .control
            case .fn: return .function
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

    private var globalFlagsMonitor: Any?
    private var localMonitor: Any?
    private var lastKeyDown: UInt16?

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
        guard globalFlagsMonitor == nil else { return }

        // Global monitor for modifier key changes - does NOT require Accessibility permission.
        // NSEvent.addGlobalMonitorForEvents monitors events destined for other applications.
        globalFlagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self else { return }
            let keyCode = event.keyCode
            let flags = event.modifierFlags
            DispatchQueue.main.async {
                self.handleFlagsChanged(keyCode: keyCode, flags: flags)
            }
        }

        // Local monitor for when app/overlay is frontmost - handles both modifier keys and Escape.
        // addLocalMonitorForEvents does NOT require any special permissions.
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            guard let self else { return event }
            if event.type == .flagsChanged {
                let keyCode = event.keyCode
                let flags = event.modifierFlags
                DispatchQueue.main.async {
                    self.handleFlagsChanged(keyCode: keyCode, flags: flags)
                }
            } else if event.type == .keyDown && event.keyCode == 53 {  // 53 = Escape
                DispatchQueue.main.async {
                    self.handleEscapeKey()
                }
            }
            return event
        }

        if globalFlagsMonitor == nil {
            NSLog("VoiceFox: Failed to create global event monitor")
        }

        NSLog("VoiceFox: Hotkey monitoring started for %@ (expecting keyCode: %d)", selectedModifier.displayName, selectedModifier.keyCode ?? 0)
    }

    private func stopMonitoring() {
        if let monitor = globalFlagsMonitor {
            NSEvent.removeMonitor(monitor)
            globalFlagsMonitor = nil
        }
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
        isHotkeyPressed = false

        NSLog("VoiceFox: Hotkey monitoring stopped")
    }

    private func restartMonitoring() {
        stopMonitoring()
        if isEnabled {
            startMonitoring()
        }
    }

    private func handleFlagsChanged(keyCode: UInt16, flags: NSEvent.ModifierFlags) {
        guard isEnabled else { return }

        // Check if our specific modifier key was pressed/released
        guard let targetKeyCode = selectedModifier.keyCode else { return }

        // For modifier keys, we need to check if our specific key is being held
        // flagsChanged fires for both press and release
        let isModifierActive = flags.contains(selectedModifier.modifierFlags)

        // Handle based on activation mode
        if keyCode == targetKeyCode {
            NSLog("VoiceFox: Target key event - keyCode: %d, isModifierActive: %d, isHotkeyPressed: %d, mode: %@",
                  keyCode, isModifierActive ? 1 : 0, isHotkeyPressed ? 1 : 0, activationMode.rawValue)

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

    private func handleEscapeKey() {
        guard isEnabled, escapeToCancel, isHotkeyPressed else { return }
        NSLog("VoiceFox: Escape pressed - cancelling recording")
        isHotkeyPressed = false
        lastKeyDown = nil
        keyDownTime = nil
        lastTapTime = nil
        onCancel?()
    }

    // MARK: - Activation Mode Handlers

    private func handleHoldMode(isModifierActive: Bool, keyCode: UInt16) {
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

    private func handleToggleMode(isModifierActive: Bool, keyCode: UInt16) {
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

    private func handleDoubleTapMode(isModifierActive: Bool, keyCode: UInt16) {
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

    private func handleHoldOrToggleMode(isModifierActive: Bool, keyCode: UInt16) {
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

    /// Check if accessibility permissions are granted (does NOT show prompt).
    /// Note: Accessibility is needed for auto-paste (text injection), not for hotkey detection.
    @MainActor
    public static func checkAccessibilityPermission() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: false] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Request accessibility permissions (opens System Settings).
    /// Note: Accessibility is needed for auto-paste (text injection), not for hotkey detection.
    @MainActor
    public static func requestAccessibilityPermission() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Ensure monitoring is active, restart if needed
    public func ensureMonitoringActive() {
        if globalFlagsMonitor == nil {
            NSLog("VoiceFox: Monitor was nil, restarting monitoring...")
            startMonitoring()
        }
    }
}
