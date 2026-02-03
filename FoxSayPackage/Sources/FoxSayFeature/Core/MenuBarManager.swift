import AppKit
import SwiftUI

/// Manages the menu bar status item
@MainActor
public class MenuBarManager: NSObject, ObservableObject {
    public static let shared = MenuBarManager()

    private var statusItem: NSStatusItem?

    @Published public var isMenuBarVisible = true

    /// Current icon state
    public enum IconState {
        case idle
        case recording
        case processing
    }

    @Published public var iconState: IconState = .idle {
        didSet {
            updateIcon()
        }
    }

    override private init() {
        super.init()
        print("FoxSay: MenuBarManager initializing...")
        setupMenuBar()
        observeUserDefaults()
        print("FoxSay: MenuBarManager initialized")
    }

    private func observeUserDefaults() {
        UserDefaults.standard.addObserver(
            self,
            forKeyPath: "showInMenuBar",
            options: [.new, .initial],
            context: nil
        )
    }

    override public func observeValue(
        forKeyPath keyPath: String?,
        of object: Any?,
        change: [NSKeyValueChangeKey: Any]?,
        context: UnsafeMutableRawPointer?
    ) {
        if keyPath == "showInMenuBar" {
            DispatchQueue.main.async {
                self.updateMenuBarVisibility()
            }
        }
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            let icon = NSImage(named: "MenuBarIcon")
            icon?.size = NSSize(width: 18, height: 18)
            icon?.isTemplate = true
            button.image = icon
            button.target = self
            button.action = #selector(menuBarButtonClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        updateMenuBarVisibility()
    }

    @objc private func menuBarButtonClicked(_ sender: NSStatusBarButton) {
        showMainMenu()
    }

    private func showMainMenu() {
        let menu = NSMenu()

        // Toggle Dictation with hotkey symbol
        let hotkeyManager = HotkeyManager.shared
        let dictationTitle = "Toggle Dictation (\(hotkeyManager.selectedModifier.shortName))"
        let dictationItem = NSMenuItem(
            title: dictationTitle,
            action: #selector(toggleDictation),
            keyEquivalent: ""
        )
        dictationItem.target = self
        menu.addItem(dictationItem)

        // Prompt Selector (only if enabled)
        if hotkeyManager.promptSelectorEnabled {
            let promptTitle = "Prompt Selector (\(hotkeyManager.promptSelectorModifier.shortName))"
            let promptItem = NSMenuItem(
                title: promptTitle,
                action: #selector(showPromptSelector),
                keyEquivalent: ""
            )
            promptItem.target = self
            menu.addItem(promptItem)
        }

        menu.addItem(NSMenuItem.separator())

        // Settings
        let settingsItem = NSMenuItem(
            title: "Settings...",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        // Quit
        let quitItem = NSMenuItem(
            title: "Quit FoxSay",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }

    @objc private func toggleDictation() {
        // Simulate hotkey press to toggle recording
        if AppState.shared.isRecording {
            HotkeyManager.shared.stopToggleRecording()
        } else {
            HotkeyManager.shared.onHotkeyDown?()
        }
    }

    @objc private func showPromptSelector() {
        HotkeyManager.shared.onPromptSelector?()
    }

    /// Track if we were in accessory mode before showing settings
    private static var wasAccessoryMode = false

    @objc private func openSettings() {
        // Debug: Log all windows
        print("FoxSay: openSettings - All windows: \(NSApp.windows.count)")
        for (index, window) in NSApp.windows.enumerated() {
            print("FoxSay:   Window \(index): \(type(of: window)), isVisible=\(window.isVisible), canBecomeMain=\(window.canBecomeMain), canBecomeKey=\(window.canBecomeKey), title='\(window.title)'")
        }

        // Remember if we were in accessory mode
        Self.wasAccessoryMode = NSApp.activationPolicy() == .accessory

        // Temporarily switch to regular activation policy so windows can be shown properly
        // This is needed because .accessory mode prevents normal window behavior
        if Self.wasAccessoryMode {
            print("FoxSay: Switching from accessory to regular policy temporarily")
            NSApp.setActivationPolicy(.regular)
        }

        // Bring app to foreground
        NSApp.activate(ignoringOtherApps: true)

        // Use async to let activation policy change take effect
        DispatchQueue.main.async {
            self.showMainWindow()
        }
    }

    /// Call this when the settings window is closed to restore accessory mode
    public static func restoreAccessoryModeIfNeeded() {
        if wasAccessoryMode {
            print("FoxSay: Restoring accessory mode")
            NSApp.setActivationPolicy(.accessory)
            wasAccessoryMode = false
        }
    }

    private func showMainWindow() {
        // Find a main window to show (not panels like overlays)
        let mainWindow = NSApp.windows.first { window in
            // Skip panels (overlays, etc.) - we want the main WindowGroup window
            !(window is NSPanel) && window.canBecomeMain
        }

        if let window = mainWindow {
            print("FoxSay: Found main window, isVisible=\(window.isVisible), isMiniaturized=\(window.isMiniaturized)")

            // Deminiaturize if needed (this also makes it visible)
            if window.isMiniaturized {
                print("FoxSay: Deminiaturizing window")
                window.deminiaturize(nil)
            }

            // Ensure visible
            if !window.isVisible {
                print("FoxSay: Making window visible")
                window.setIsVisible(true)
            }

            // Use orderFrontRegardless which is more aggressive
            print("FoxSay: Ordering window front regardless")
            window.orderFrontRegardless()
            window.makeKey()

            // Activate app using the newer API
            print("FoxSay: Activating app with NSRunningApplication")
            NSRunningApplication.current.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])

            // Note: We stay in .regular mode while the window is open
            // The dock icon will be visible, but it will disappear when the window is closed
            // (handled by the NSWindow.willCloseNotification observer in AppDelegate)

            // Navigate to settings after a small delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                print("FoxSay: Posting ShowSettings notification")
                NotificationCenter.default.post(name: NSNotification.Name("ShowSettings"), object: nil)
            }
        } else {
            print("FoxSay: No main window found, requesting creation")
            // No main window exists - post notification to create one via SwiftUI
            NotificationCenter.default.post(name: NSNotification.Name("OpenMainWindow"), object: nil)

            // Wait for window to be created, then show settings
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                // Activate after window creation
                NSApp.activate(ignoringOtherApps: true)
                NotificationCenter.default.post(name: NSNotification.Name("ShowSettings"), object: nil)
            }
        }
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    private func updateMenuBarVisibility() {
        let shouldShow = UserDefaults.standard.bool(forKey: "showInMenuBar")
        isMenuBarVisible = shouldShow
        statusItem?.isVisible = shouldShow
    }

    private func updateIcon() {
        guard let button = statusItem?.button else { return }

        let icon: NSImage?
        switch iconState {
        case .idle:
            icon = NSImage(named: "MenuBarIcon")
            icon?.size = NSSize(width: 18, height: 18)
            icon?.isTemplate = true
        case .recording:
            let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)
            icon = NSImage(
                systemSymbolName: "waveform.circle.fill",
                accessibilityDescription: "FoxSay Recording"
            )?.withSymbolConfiguration(config)
            icon?.isTemplate = true
        case .processing:
            let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)
            icon = NSImage(
                systemSymbolName: "ellipsis.circle",
                accessibilityDescription: "FoxSay Processing"
            )?.withSymbolConfiguration(config)
            icon?.isTemplate = true
        }

        button.image = icon
    }

    public func setRecording(_ recording: Bool) {
        iconState = recording ? .recording : .idle
    }

    public func setProcessing(_ processing: Bool) {
        if processing {
            iconState = .processing
        } else if !AppState.shared.isRecording {
            iconState = .idle
        }
    }

    deinit {
        UserDefaults.standard.removeObserver(self, forKeyPath: "showInMenuBar")
    }
}
