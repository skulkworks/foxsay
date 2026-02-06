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
        setupMenuBar()
        observeUserDefaults()
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

        #if DEBUG
        menu.addItem(NSMenuItem.separator())

        let simNoMic = AudioEngine.shared.simulateNoMicrophone
        let simItem = NSMenuItem(
            title: "Simulate No Microphone",
            action: #selector(toggleSimulateNoMicrophone),
            keyEquivalent: ""
        )
        simItem.target = self
        simItem.state = simNoMic ? .on : .off
        menu.addItem(simItem)
        #endif

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

    #if DEBUG
    @objc private func toggleSimulateNoMicrophone() {
        AudioEngine.shared.simulateNoMicrophone.toggle()
        print("FoxSay: Simulate no microphone = \(AudioEngine.shared.simulateNoMicrophone)")
    }
    #endif

    /// Track if we were in accessory mode before showing settings
    private static var wasAccessoryMode = false

    @objc private func openSettings() {
        // Remember if we were in accessory mode
        Self.wasAccessoryMode = NSApp.activationPolicy() == .accessory

        // Temporarily switch to regular activation policy so windows can be shown properly
        // This is needed because .accessory mode prevents normal window behavior
        if Self.wasAccessoryMode {
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
            // Deminiaturize if needed (this also makes it visible)
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }

            // Ensure visible
            if !window.isVisible {
                window.setIsVisible(true)
            }

            // Use orderFrontRegardless which is more aggressive
            window.orderFrontRegardless()
            window.makeKey()

            // Activate app using the newer API
            NSRunningApplication.current.activate()

            // Note: We stay in .regular mode while the window is open
            // The dock icon will be visible, but it will disappear when the window is closed
            // (handled by the NSWindow.willCloseNotification observer in AppDelegate)

            // Navigate to settings after a small delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                NotificationCenter.default.post(name: NSNotification.Name("ShowSettings"), object: nil)
            }
        } else {
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
