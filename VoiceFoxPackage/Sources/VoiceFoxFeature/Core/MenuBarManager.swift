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
        print("VoiceFox: MenuBarManager initializing...")
        setupMenuBar()
        observeUserDefaults()
        print("VoiceFox: MenuBarManager initialized")
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
            // Use SF Symbol for icon
            let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)
            let icon = NSImage(
                systemSymbolName: "waveform.circle",
                accessibilityDescription: "VoiceFox"
            )?.withSymbolConfiguration(config)

            button.image = icon
            button.image?.isTemplate = true
            button.target = self
            button.action = #selector(menuBarButtonClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        updateMenuBarVisibility()
    }

    @objc private func menuBarButtonClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent!

        if event.type == .rightMouseUp {
            showContextMenu()
        } else {
            toggleOverlay()
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()

        menu.addItem(
            NSMenuItem(
                title: "Settings...",
                action: #selector(openSettings),
                keyEquivalent: ","
            ))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(
            NSMenuItem(
                title: "Quit VoiceFox",
                action: #selector(quitApp),
                keyEquivalent: "q"
            ))

        for item in menu.items {
            item.target = self
        }

        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }

    private func toggleOverlay() {
        AppState.shared.isOverlayVisible.toggle()

        // Activate app if showing overlay
        if AppState.shared.isOverlayVisible {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    @objc private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.post(name: NSNotification.Name("ShowSettings"), object: nil)
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

        let symbolName: String
        switch iconState {
        case .idle:
            symbolName = "waveform.circle"
        case .recording:
            symbolName = "waveform.circle.fill"
        case .processing:
            symbolName = "ellipsis.circle"
        }

        let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        let icon = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: "VoiceFox"
        )?.withSymbolConfiguration(config)

        button.image = icon
        button.image?.isTemplate = true
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
