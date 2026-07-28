import AppKit
import SwiftUI

/// Presents the "What's New" window: a native `ChangelogView` over FoxSay's
/// published changelog feed. The window is created once and re-fronted on later
/// presents. Also owns the once-per-update auto-present: call `presentIfUpdated`
/// at launch and the window appears exactly once after each version change
/// (never on a fresh install, where nothing is "new" to the user).
///
/// Vendored from the shared `den` package, so the behaviour matches Magpie and
/// Riffle.
@MainActor
final class ChangelogWindowPresenter {
    private let appName: String
    private let feedURL: URL
    private var window: NSWindow?

    /// The UserDefaults key recording the last version the user has seen.
    static let lastSeenVersionKey = "FoxSay.LastSeenVersion"

    init(appName: String, feedURL: URL) {
        self.appName = appName
        self.feedURL = feedURL
    }

    func present() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }

        let hosting = NSHostingController(
            rootView: ChangelogView(feedURL: feedURL).frame(minWidth: 400, minHeight: 320))
        let window = NSWindow(contentViewController: hosting)
        window.title = "What's New in \(appName)"
        // Tagged so the code that hunts for "the main window" (opening About,
        // handling OpenMainWindow) can tell this one apart. It is titled and
        // canBecomeMain, so it would otherwise be a candidate.
        window.identifier = FoxSayChangelog.windowIdentifier
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 480, height: 560))
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window

        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    /// Whether a launch with `currentVersion` should auto-present, given the last
    /// version the user saw. Pure so the rule pins down in tests: never on first
    /// launch (no recorded version), once after any version change.
    static func shouldAutoPresent(lastSeen: String?, currentVersion: String) -> Bool {
        guard let lastSeen else { return false }
        return lastSeen != currentVersion
    }

    /// Call once at launch: records `currentVersion` as seen and presents the
    /// window if this launch is the first on a new version.
    func presentIfUpdated(currentVersion: String, defaults: UserDefaults = .standard) {
        let lastSeen = defaults.string(forKey: Self.lastSeenVersionKey)
        defaults.set(currentVersion, forKey: Self.lastSeenVersionKey)
        if Self.shouldAutoPresent(lastSeen: lastSeen, currentVersion: currentVersion) {
            present()
        }
    }
}

/// FoxSay's "What's New" window: the changelog view over FoxSay's published feed.
/// Opened from the Help menu and from About, and automatically exactly once after
/// each update (Sparkle relaunches into the new version; the next launch shows
/// what changed).
@MainActor
public enum FoxSayChangelog {
    /// Identifies the What's New window so window-hunting code can skip it.
    public static let windowIdentifier = NSUserInterfaceItemIdentifier("FoxSayWhatsNew")

    /// True when `window` is the What's New window rather than a main window.
    public static func isChangelogWindow(_ window: NSWindow) -> Bool {
        window.identifier == windowIdentifier
    }

    /// The published feed, unless `FOXSAY_CHANGELOG_FEED_URL` overrides it — which
    /// lets a development build read a local or staged feed without a code change,
    /// the same way the apps feed works.
    static let feedURL: URL = {
        if let override = ProcessInfo.processInfo.environment["FOXSAY_CHANGELOG_FEED_URL"],
           let url = URL(string: override) {
            return url
        }
        return URL(string: "https://updates.skulkworks.dev/foxsay/changelog.json")!
    }()

    static let presenter = ChangelogWindowPresenter(appName: "FoxSay", feedURL: feedURL)

    /// Opens the window, or brings it forward if it is already open.
    public static func present() {
        presenter.present()
    }

    /// Call once at launch (applicationDidFinishLaunching).
    public static func presentIfUpdated() {
        guard let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString") as? String else { return }
        presenter.presentIfUpdated(currentVersion: version)
    }
}
