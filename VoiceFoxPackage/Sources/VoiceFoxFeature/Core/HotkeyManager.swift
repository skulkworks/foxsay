@preconcurrency import AppKit
@preconcurrency import Carbon.HIToolbox
import Foundation

/// Manages global hotkey for hold-to-talk functionality
@MainActor
public class HotkeyManager: ObservableObject {
    public static let shared = HotkeyManager()

    public enum HotkeyModifier: String, CaseIterable, Identifiable, Codable {
        case rightCommand = "rightCommand"
        case leftCommand = "leftCommand"
        case rightOption = "rightOption"
        case leftOption = "leftOption"
        case rightControl = "rightControl"
        case leftControl = "leftControl"
        case fn = "fn"

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .rightCommand: return "Right Command (⌘)"
            case .leftCommand: return "Left Command (⌘)"
            case .rightOption: return "Right Option (⌥)"
            case .leftOption: return "Left Option (⌥)"
            case .rightControl: return "Right Control (⌃)"
            case .leftControl: return "Left Control (⌃)"
            case .fn: return "Fn"
            }
        }

        var keyCode: CGKeyCode? {
            switch self {
            case .rightCommand: return 54  // kVK_RightCommand
            case .leftCommand: return 55   // kVK_Command
            case .rightOption: return 61   // kVK_RightOption
            case .leftOption: return 58    // kVK_Option
            case .rightControl: return 62  // kVK_RightControl
            case .leftControl: return 59   // kVK_Control
            case .fn: return 63            // kVK_Function
            }
        }

        var cgEventFlags: CGEventFlags {
            switch self {
            case .rightCommand, .leftCommand: return .maskCommand
            case .rightOption, .leftOption: return .maskAlternate
            case .rightControl, .leftControl: return .maskControl
            case .fn: return .maskSecondaryFn
            }
        }
    }

    @Published public var selectedModifier: HotkeyModifier {
        didSet {
            UserDefaults.standard.set(selectedModifier.rawValue, forKey: "hotkeyModifier")
            restartMonitoring()
        }
    }

    @Published public private(set) var isHotkeyPressed = false
    @Published public private(set) var isEnabled = true

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var lastKeyDown: CGKeyCode?

    /// Callback when hotkey is pressed
    public var onHotkeyDown: (() -> Void)?

    /// Callback when hotkey is released
    public var onHotkeyUp: (() -> Void)?

    private init() {
        let savedModifier = UserDefaults.standard.string(forKey: "hotkeyModifier") ?? "rightOption"
        selectedModifier = HotkeyModifier(rawValue: savedModifier) ?? .rightOption
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

        if type == .flagsChanged {
            // Check if our specific modifier key was pressed/released
            guard let targetKeyCode = selectedModifier.keyCode else { return }

            // For modifier keys, we need to check if our specific key is being held
            // flagsChanged fires for both press and release
            let isModifierActive = flags.contains(selectedModifier.cgEventFlags)

            // Debug: log events for our target key
            if keyCode == targetKeyCode {
                NSLog("VoiceFox: Target key event - keyCode: %d, isModifierActive: %d, isHotkeyPressed: %d, hasDownCallback: %d, hasUpCallback: %d",
                      keyCode, isModifierActive ? 1 : 0, isHotkeyPressed ? 1 : 0, onHotkeyDown != nil ? 1 : 0, onHotkeyUp != nil ? 1 : 0)
            }

            // Track if this specific key was pressed
            if keyCode == targetKeyCode {
                if isModifierActive && !isHotkeyPressed {
                    NSLog("VoiceFox: Hotkey DOWN detected (keyCode: %d)", keyCode)
                    isHotkeyPressed = true
                    lastKeyDown = keyCode
                    onHotkeyDown?()
                } else if !isModifierActive && isHotkeyPressed && lastKeyDown == keyCode {
                    NSLog("VoiceFox: Hotkey UP detected (keyCode: %d)", keyCode)
                    isHotkeyPressed = false
                    lastKeyDown = nil
                    onHotkeyUp?()
                }
            }
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
