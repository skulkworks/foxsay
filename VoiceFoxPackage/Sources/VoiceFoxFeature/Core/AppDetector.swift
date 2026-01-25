@preconcurrency import AppKit
import Foundation

/// Monitors frontmost app for developer app detection
@MainActor
public class AppDetector: ObservableObject {
    public static let shared = AppDetector()

    @Published public private(set) var frontmostAppBundleId: String?
    @Published public private(set) var frontmostAppName: String?

    private var observer: NSObjectProtocol?

    private init() {
        updateFrontmostApp()
        startObserving()
    }

    // Note: Observer cleanup happens when app terminates
    // Cannot access MainActor-isolated properties from deinit

    private func startObserving() {
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self else { return }
            if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication
            {
                // Wrap all MainActor-isolated property mutations in Task
                Task { @MainActor in
                    self.frontmostAppBundleId = app.bundleIdentifier
                    self.frontmostAppName = app.localizedName
                    AppState.shared.frontmostAppBundleId = app.bundleIdentifier
                }
            }
        }
    }

    private func updateFrontmostApp() {
        if let app = NSWorkspace.shared.frontmostApplication {
            frontmostAppBundleId = app.bundleIdentifier
            frontmostAppName = app.localizedName
            AppState.shared.frontmostAppBundleId = app.bundleIdentifier
        }
    }

    /// Check if the current frontmost app is a developer app
    public var isDevApp: Bool {
        guard let bundleId = frontmostAppBundleId else { return false }
        return DevAppConfigManager.shared.isDevApp(bundleId: bundleId)
    }

    /// Get the frontmost app that is NOT VoiceFox
    public func getPreviousFrontmostApp() -> NSRunningApplication? {
        let voiceFoxBundleId = Bundle.main.bundleIdentifier

        // Get all running apps and find the most recently activated one that isn't VoiceFox
        for app in NSWorkspace.shared.runningApplications {
            guard app.activationPolicy == .regular,
                app.bundleIdentifier != voiceFoxBundleId,
                app.isActive == false
            else { continue }

            return app
        }

        return nil
    }
}
