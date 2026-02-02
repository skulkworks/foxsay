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
        let hideWindowOnLaunch = UserDefaults.standard.bool(forKey: "hideWindowOnLaunch")
        if hideWindowOnLaunch {
            DispatchQueue.main.async {
                for window in NSApp.windows {
                    window.close()
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
        WindowGroup {
            MainWindowView()
                .environmentObject(appState)
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
