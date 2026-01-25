import SwiftUI
import VoiceFoxFeature
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("VoiceFox: applicationDidFinishLaunching")

        // Initialize MenuBarManager on main thread
        Task { @MainActor in
            _ = MenuBarManager.shared
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep app running even when all windows are closed (menu bar app behavior)
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        print("VoiceFox: applicationWillTerminate")

        // Clean up resources
        Task { @MainActor in
            await ModelManager.shared.cleanup()
        }
    }
}

@main
struct VoiceFoxApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState.shared
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

        if defaults.object(forKey: "selectedEngine") == nil {
            defaults.set("whisperkit", forKey: "selectedEngine")
        }

        if defaults.object(forKey: "hotkeyModifier") == nil {
            defaults.set("rightCommand", forKey: "hotkeyModifier")
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
        .defaultSize(width: 650, height: 500)
        .commands {
            // Remove the default "New Window" command
            CommandGroup(replacing: .newItem) {}

            CommandGroup(replacing: .appSettings) {
                Button("Settings...") {
                    appState.showSettings = true
                }
                .keyboardShortcut(",", modifiers: .command)
            }

            CommandGroup(replacing: .help) {
                Button("VoiceFox Help") {
                    if let url = URL(string: "https://voicefox.app") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .keyboardShortcut("?", modifiers: .command)
            }
        }
    }
}
