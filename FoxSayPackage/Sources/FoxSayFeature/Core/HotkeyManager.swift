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

    /// Prompt selector hotkey modifier
    @Published public var promptSelectorModifier: HotkeyModifier {
        didSet {
            UserDefaults.standard.set(promptSelectorModifier.rawValue, forKey: "promptSelectorModifier")
        }
    }

    /// Whether prompt selector hotkey is enabled
    @Published public var promptSelectorEnabled: Bool {
        didSet {
            UserDefaults.standard.set(promptSelectorEnabled, forKey: "promptSelectorEnabled")
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

    /// Callback when prompt selector hotkey is pressed
    public var onPromptSelector: (() -> Void)?

    private init() {
        let savedModifier = UserDefaults.standard.string(forKey: "hotkeyModifier") ?? "rightOption"
        selectedModifier = HotkeyModifier(rawValue: savedModifier) ?? .rightOption

        let savedMode = UserDefaults.standard.string(forKey: "hotkeyActivationMode") ?? "hold"
        activationMode = ActivationMode(rawValue: savedMode) ?? .hold

        escapeToCancel = UserDefaults.standard.object(forKey: "hotkeyEscapeToCancel") as? Bool ?? true

        // Prompt selector hotkey defaults
        let savedPromptModifier = UserDefaults.standard.string(forKey: "promptSelectorModifier") ?? "rightCommand"
        promptSelectorModifier = HotkeyModifier(rawValue: savedPromptModifier) ?? .rightCommand
        promptSelectorEnabled = UserDefaults.standard.object(forKey: "promptSelectorEnabled") as? Bool ?? true

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
            NSLog("FoxSay: Failed to create global event monitor")
        }

        NSLog("FoxSay: Hotkey monitoring started for %@ (expecting keyCode: %d)", selectedModifier.displayName, selectedModifier.keyCode ?? 0)
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

        NSLog("FoxSay: Hotkey monitoring stopped")
    }

    private func restartMonitoring() {
        stopMonitoring()
        if isEnabled {
            startMonitoring()
        }
    }

    private func handleFlagsChanged(keyCode: UInt16, flags: NSEvent.ModifierFlags) {
        guard isEnabled else { return }

        // Check for prompt selector hotkey (separate from recording hotkey)
        if promptSelectorEnabled,
           let promptKeyCode = promptSelectorModifier.keyCode,
           keyCode == promptKeyCode,
           promptSelectorModifier != selectedModifier {  // Don't conflict with recording hotkey
            let isPromptModifierActive = flags.contains(promptSelectorModifier.modifierFlags)
            if isPromptModifierActive {
                NSLog("FoxSay: Prompt selector hotkey pressed")
                onPromptSelector?()
            }
            return  // Don't process as recording hotkey
        }

        // Check if our specific modifier key was pressed/released
        guard let targetKeyCode = selectedModifier.keyCode else { return }

        // For modifier keys, we need to check if our specific key is being held
        // flagsChanged fires for both press and release
        let isModifierActive = flags.contains(selectedModifier.modifierFlags)

        // Handle based on activation mode
        if keyCode == targetKeyCode {
            NSLog("FoxSay: Target key event - keyCode: %d, isModifierActive: %d, isHotkeyPressed: %d, mode: %@",
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
        NSLog("FoxSay: Escape pressed - cancelling recording")
        isHotkeyPressed = false
        lastKeyDown = nil
        keyDownTime = nil
        lastTapTime = nil
        onCancel?()
    }

    // MARK: - Activation Mode Handlers

    private func handleHoldMode(isModifierActive: Bool, keyCode: UInt16) {
        if isModifierActive && !isHotkeyPressed {
            NSLog("FoxSay: [Hold] Hotkey DOWN")
            isHotkeyPressed = true
            onHotkeyDown?()
        } else if !isModifierActive && isHotkeyPressed {
            // Release when modifier is no longer active, regardless of which key triggered the event
            NSLog("FoxSay: [Hold] Hotkey UP")
            isHotkeyPressed = false
            onHotkeyUp?()
        }
    }

    private func handleToggleMode(isModifierActive: Bool, keyCode: UInt16) {
        // Only trigger on key down (press)
        if isModifierActive && lastKeyDown != keyCode {
            lastKeyDown = keyCode
            if !isHotkeyPressed {
                NSLog("FoxSay: [Toggle] Starting recording")
                isHotkeyPressed = true
                onHotkeyDown?()
            } else {
                NSLog("FoxSay: [Toggle] Stopping recording")
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
                    NSLog("FoxSay: [DoubleTap] Starting recording")
                    isHotkeyPressed = true
                    onHotkeyDown?()
                } else {
                    NSLog("FoxSay: [DoubleTap] Stopping recording")
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
                NSLog("FoxSay: [HoldOrToggle] Key down - starting recording")
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
                    NSLog("FoxSay: [HoldOrToggle] Short press (%.2fs) - toggle mode, continuing", holdDuration)
                    // Don't stop recording - user needs to tap again
                } else {
                    // Long press - hold mode (stop recording)
                    NSLog("FoxSay: [HoldOrToggle] Long hold (%.2fs) - hold mode, stopping", holdDuration)
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
            NSLog("FoxSay: Manually stopping toggle recording")
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

    /// Request accessibility permissions or open Settings if already enabled.
    /// Note: Accessibility is needed for auto-paste (text injection), not for hotkey detection.
    /// On macOS Sonoma+, apps cannot auto-add to Accessibility list - user must add manually.
    @MainActor
    public static func requestAccessibilityPermission() {
        let trusted = checkAccessibilityPermission()

        if trusted {
            // Already enabled - just open Settings so user can manage it
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        } else {
            // Show alert with instructions
            let alert = NSAlert()
            alert.messageText = "Accessibility Permission Required"
            alert.informativeText = "To enable Auto-Paste, you need to add FoxSay to the Accessibility list:\n\n1. Click 'Open Settings' below\n2. Click the '+' button at the bottom\n3. Navigate to Applications and select FoxSay\n4. Toggle FoxSay ON"
            alert.alertStyle = .informational
            alert.addButton(withTitle: "Open Settings")
            alert.addButton(withTitle: "Cancel")

            if alert.runModal() == .alertFirstButtonReturn {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }

    /// Ensure monitoring is active, restart if needed
    public func ensureMonitoringActive() {
        if globalFlagsMonitor == nil {
            NSLog("FoxSay: Monitor was nil, restarting monitoring...")
            startMonitoring()
        }
    }
}
