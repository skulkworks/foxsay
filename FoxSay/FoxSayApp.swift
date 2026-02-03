import SwiftUI
import FoxSayFeature
import AppKit
import Sparkle

class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("FoxSay: applicationDidFinishLaunching")

        // Apply dock visibility setting
        let showInDock = UserDefaults.standard.object(forKey: "showInDock") as? Bool ?? true
        NSApp.setActivationPolicy(showInDock ? .regular : .accessory)

        // Initialize MenuBarManager on main thread
        Task { @MainActor in
            _ = MenuBarManager.shared
        }

        // Hide window on launch if setting is enabled
        // In accessory mode (no dock icon), we need to be careful not to destroy the window
        let hideWindowOnLaunch = UserDefaults.standard.bool(forKey: "hideWindowOnLaunch")
        if hideWindowOnLaunch && showInDock {
            // Only hide if we have a dock icon (regular mode)
            // In accessory mode, closing/hiding windows destroys them in SwiftUI
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                for window in NSApp.windows where !(window is NSPanel) && window.canBecomeMain {
                    print("FoxSay: Hiding window on launch (dock mode): \(window)")
                    window.orderOut(nil)
                }
            }
        } else if hideWindowOnLaunch && !showInDock {
            // In accessory mode, just push window to back - don't hide it
            // The window needs to exist for openWindow to work later
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                for window in NSApp.windows where !(window is NSPanel) && window.canBecomeMain {
                    print("FoxSay: Pushing window to back (accessory mode): \(window)")
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
            print("FoxSay: OpenMainWindow notification received")
            // Find and show the main window
            for window in NSApp.windows where !(window is NSPanel) && window.canBecomeMain {
                print("FoxSay: Found window to show: \(window)")
                window.makeKeyAndOrderFront(nil)
                return
            }
            print("FoxSay: No suitable window found, creating one manually")
            Task { @MainActor in
                self?.createMainWindowIfNeeded()
            }
        }

        // Listen for window close to restore accessory mode if needed
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let window = notification.object as? NSWindow else {
                print("FoxSay: willCloseNotification - no window in notification")
                return
            }
            print("FoxSay: Window closing: \(type(of: window)), canBecomeMain=\(window.canBecomeMain), isPanel=\(window is NSPanel)")

            guard !(window is NSPanel) && window.canBecomeMain else {
                print("FoxSay: Ignoring non-main window close")
                return
            }
            print("FoxSay: Main window closing, will check if should restore accessory mode")
            // Small delay to allow window to fully close
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                // Check if there are no more main windows visible
                let hasVisibleMainWindow = NSApp.windows.contains { w in
                    !(w is NSPanel) && w.canBecomeMain && w.isVisible
                }
                print("FoxSay: After close - hasVisibleMainWindow=\(hasVisibleMainWindow)")
                if !hasVisibleMainWindow {
                    print("FoxSay: No visible main windows, restoring accessory mode")
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
        print("FoxSay: applicationWillTerminate")

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
            print("FoxSay: WindowOpener received OpenMainWindow notification")
            Task { @MainActor in
                if let action = self?.openWindowAction {
                    print("FoxSay: Calling openWindow action")
                    action("main")
                } else {
                    print("FoxSay: No openWindow action registered!")
                }
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
                print("FoxSay: Capturing openWindow action")
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

            CommandGroup(replacing: .appSettings) {
                Button("Settings...") {
                    appState.showSettings = true
                }
                .keyboardShortcut(",", modifiers: .command)

                Divider()

                Button("Check for Updates...") {
                    updaterController.checkForUpdates()
                }
                .disabled(!updaterController.canCheckForUpdates)

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
        let hasMainWindow = NSApp.windows.contains { window in
            !(window is NSPanel) && window.canBecomeMain
        }

        if hasMainWindow {
            print("FoxSay: Main window already exists")
            return
        }

        print("FoxSay: Creating main window manually")

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

        print("FoxSay: Main window created and shown")
    }
}
