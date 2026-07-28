import Foundation

/// Lets package-side UI (the About pane's "Check for Updates…" button) trigger the
/// Sparkle updater, which lives in the app shell — the package never links Sparkle.
/// The shell's `UpdaterController` registers `action` and mirrors `canCheck` at
/// launch; both stay false/empty under `swift test` and in previews.
@MainActor
public final class UpdateCheckBridge: ObservableObject {
    public static let shared = UpdateCheckBridge()

    /// Mirrors Sparkle's `canCheckForUpdates` — false while a check is running, and
    /// permanently false when the updater never started, which keeps the button
    /// correctly greyed out.
    @Published public var canCheck = false

    /// Registered by the app shell; runs `SPUUpdater.checkForUpdates()`.
    public var action: (() -> Void)?

    private init() {}

    public func check() {
        action?()
    }
}
