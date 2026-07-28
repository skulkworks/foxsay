import SwiftUI
import FoxSayFeature
import AppKit
import Sparkle

@MainActor
extension NSWindow {
    /// A FoxSay main window: not a floating panel, and not the What's New window,
    /// which is titled and `canBecomeMain` and would otherwise be mistaken for one
    /// by the code that hides, restores, or fronts "the" window.
    var isFoxSayMainWindow: Bool {
        !(self is NSPanel) && canBecomeMain && !FoxSayChangelog.isChangelogWindow(self)
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Apply dock visibility setting
        let showInDock = UserDefaults.standard.object(forKey: "showInDock") as? Bool ?? true
        NSApp.setActivationPolicy(showInDock ? .regular : .accessory)

        // Initialize MenuBarManager on main thread
        Task { @MainActor in
            _ = MenuBarManager.shared
            // Starting the updater is also what registers UpdateCheckBridge, which the
            // About pane's button drives — don't leave it to the scene's lazy init.
            _ = UpdaterController.shared

            // First launch on a new version shows the What's New window once.
            FoxSayChangelog.presentIfUpdated()
        }

        // Hide window on launch if setting is enabled
        // In accessory mode (no dock icon), we need to be careful not to destroy the window
        let hideWindowOnLaunch = UserDefaults.standard.bool(forKey: "hideWindowOnLaunch")
        if hideWindowOnLaunch && showInDock {
            // Only hide if we have a dock icon (regular mode)
            // In accessory mode, closing/hiding windows destroys them in SwiftUI
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(300))
                for window in NSApp.windows where window.isFoxSayMainWindow {
                    window.orderOut(nil)
                }
            }
        } else if hideWindowOnLaunch && !showInDock {
            // In accessory mode, just push window to back - don't hide it
            // The window needs to exist for openWindow to work later
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(300))
                for window in NSApp.windows where window.isFoxSayMainWindow {
                    window.orderBack(nil)
                    window.resignMain()
                    window.resignKey()
                }
            }
        }

        // Listen for request to open main window (from menubar settings)
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("OpenMainWindow"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                // Find and show the main window
                for window in NSApp.windows where window.isFoxSayMainWindow {
                    window.makeKeyAndOrderFront(nil)
                    return
                }
                // No suitable window found, create one manually
                self.createMainWindowIfNeeded()
            }
        }

        // Listen for window close to restore accessory mode if needed
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let window = notification.object as? NSWindow else { return }
            // Check panel type synchronously (not main-actor isolated)
            guard !(window is NSPanel) else { return }

            Task { @MainActor in
                // Check the rest on main actor
                guard window.isFoxSayMainWindow else { return }
                // Small delay to allow window to fully close
                try? await Task.sleep(for: .milliseconds(200))
                // Check if there are no more main windows visible
                let hasVisibleMainWindow = NSApp.windows.contains { w in
                    w.isFoxSayMainWindow && w.isVisible
                }
                if !hasVisibleMainWindow {
                    MenuBarManager.restoreAccessoryModeIfNeeded()
                }
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep app running even when all windows are closed (menu bar app behavior)
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Clean up resources
        Task { @MainActor in
            await ModelManager.shared.cleanup()
        }
    }
}

/// Singleton to store window opening action for use from non-SwiftUI code
@MainActor
class WindowOpener {
    static let shared = WindowOpener()
    var openWindowAction: ((String) -> Void)?

    private init() {
        // Listen for requests to open main window
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("OpenMainWindow"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.openWindowAction?("main")
            }
        }
    }
}

/// Helper view to capture and store the openWindow environment action
struct WindowOpenerCapture: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                WindowOpener.shared.openWindowAction = { id in
                    openWindow(id: id)
                }
            }
    }
}

@main
struct FoxSayApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState.shared
    @StateObject private var updaterController = UpdaterController.shared
    @State private var showSetupWizard = false

    init() {
        setupDefaultUserDefaults()
    }

    private func setupDefaultUserDefaults() {
        let defaults = UserDefaults.standard

        // Register default values
        if defaults.object(forKey: "showInMenuBar") == nil {
            defaults.set(true, forKey: "showInMenuBar")
        }

        if defaults.object(forKey: "showInDock") == nil {
            defaults.set(true, forKey: "showInDock")
        }

        if defaults.object(forKey: "selectedEngine") == nil && defaults.object(forKey: "selectedModel") == nil {
            defaults.set("parakeet", forKey: "selectedModel")
        }

        if defaults.object(forKey: "hotkeyModifier") == nil {
            defaults.set("rightCommand", forKey: "hotkeyModifier")
        }
    }

    /// Brings the main window forward on the About pane. FoxSay can be running as a
    /// menu bar accessory with no visible window, so the window has to be raised
    /// before the selection means anything.
    private func showAbout() {
        appState.selectedSidebarItem = .about
        NSApp.activate(ignoringOtherApps: true)

        // Raise an existing window rather than posting OpenMainWindow: WindowOpener
        // also observes that notification and calls openWindow(id:), which spawns a
        // second window in a WindowGroup rather than reusing the one already there.
        for window in NSApp.windows where window.isFoxSayMainWindow {
            window.makeKeyAndOrderFront(nil)
            return
        }
        NotificationCenter.default.post(name: NSNotification.Name("OpenMainWindow"), object: nil)
    }

    private func resetToDefaults() {
        let alert = NSAlert()
        alert.messageText = "Reset to Defaults?"
        alert.informativeText = "This will clear all settings and restart FoxSay. The setup wizard will run again on next launch."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Reset & Restart")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            // Clear all UserDefaults for this app
            if let bundleId = Bundle.main.bundleIdentifier {
                UserDefaults.standard.removePersistentDomain(forName: bundleId)
                UserDefaults.standard.synchronize()
            }

            // Relaunch the app
            let url = URL(fileURLWithPath: Bundle.main.resourcePath!)
            let path = url.deletingLastPathComponent().deletingLastPathComponent().absoluteString
            let task = Process()
            task.launchPath = "/usr/bin/open"
            task.arguments = [path]
            task.launch()

            // Quit current instance
            NSApp.terminate(nil)
        }
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            MainWindowView()
                .environmentObject(appState)
                .background(WindowOpenerCapture())
                .onAppear {
                    // Initialize managers
                    Task { @MainActor in
                        _ = MenuBarManager.shared
                        _ = HotkeyManager.shared
                    }

                    // Check if first launch
                    if SetupWizardView.needsSetup {
                        showSetupWizard = true
                    }
                }
                .sheet(isPresented: $showSetupWizard) {
                    SetupWizardView()
                        .environmentObject(appState)
                }
        }
        .windowToolbarStyle(.unified)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 650, height: 600)
        .commands {
            // Remove the default "New Window" command
            CommandGroup(replacing: .newItem) {}

            // Route About into the main window so the version, the update check and
            // the app list live with the rest of the UI instead of a stock panel.
            CommandGroup(replacing: .appInfo) {
                Button("About FoxSay") {
                    showAbout()
                }
            }

            CommandGroup(replacing: .appSettings) {
                Button("Settings...") {
                    appState.showSettings = true
                }
                .keyboardShortcut(",", modifiers: .command)

                Divider()

                Button("Reset to Defaults...") {
                    resetToDefaults()
                }
            }

            CommandGroup(replacing: .help) {
                Button("FoxSay Help") {
                    if let url = URL(string: "https://skulkworks.dev/foxsay") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .keyboardShortcut("?", modifiers: .command)

                Divider()

                Button("What's New…") {
                    FoxSayChangelog.present()
                }
            }
        }

    }
}

// MARK: - Manual Window Creation for Accessory Mode

extension AppDelegate {
    /// Creates a new main window manually when SwiftUI has deallocated all windows
    /// This is needed in accessory mode where SwiftUI doesn't maintain windows
    @MainActor
    func createMainWindowIfNeeded() {
        // Check if a main window already exists
        let hasMainWindow = NSApp.windows.contains { $0.isFoxSayMainWindow }

        if hasMainWindow {
            return
        }

        // Create a new window with the SwiftUI view
        let contentView = MainWindowView()
            .environmentObject(AppState.shared)

        let hostingController = NSHostingController(rootView: contentView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 650, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = hostingController
        window.title = "FoxSay"
        window.center()
        window.setFrameAutosaveName("FoxSayMainWindow")

        // Make it visible
        window.makeKeyAndOrderFront(nil)
    }
}
