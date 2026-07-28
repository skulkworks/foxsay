import Foundation
import SwiftUI

// The SkulkWorks apps feed. Vendored rather than taken from the shared `den`
// package: FoxSay is a public repo and `den` is private, so a path dependency
// would leave anyone outside SkulkWorks unable to build. FoxSay only ever used
// the apps list — none of den's licensing or changelog code — so the copy is
// small and self-contained.

/// The published apps feed — the machine-readable form of skulkworks.dev's home
/// page app showcase, served at `https://skulkworks.dev/apps.json`.
///
/// The website is the single source of truth: adding an app there puts it in front
/// of every installed copy of every other app without shipping a release.
struct AppsFeed: Codable, Equatable, Sendable {
    var schema: Int
    var apps: [Entry]

    struct Entry: Codable, Equatable, Sendable, Identifiable {
        /// Stable lowercase identifier, matching the app's page slug ("vectorfox").
        /// This is what an app passes as `currentApp` to hide itself from the list.
        var slug: String
        var name: String
        /// One-line summary, for a compact row.
        var tagline: String
        /// The full description, for a roomier layout.
        var description: String
        /// The app's page on skulkworks.dev, which routes on to the App Store or a
        /// direct download as appropriate — so the feed never carries store URLs.
        var url: URL
        var icon: URL?
        /// Brand colour as a CSS hex string ("#E22771"); may be empty.
        var color: String

        var id: String { slug }

        // Tolerant decoding: a future site change that drops or adds a field must
        // not blank out the pane in already-shipped copies of FoxSay.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            slug = try c.decode(String.self, forKey: .slug)
            name = try c.decode(String.self, forKey: .name)
            tagline = try c.decodeIfPresent(String.self, forKey: .tagline) ?? ""
            description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
            url = try c.decode(URL.self, forKey: .url)
            icon = try c.decodeIfPresent(URL.self, forKey: .icon)
            color = try c.decodeIfPresent(String.self, forKey: .color) ?? ""
        }

        /// The line to show under the name, preferring the short form.
        var summary: String { tagline.isEmpty ? description : tagline }
    }
}

/// Fetches the apps feed, keeping a last-good copy on disk.
///
/// The disk copy is what makes the pane usable offline and on first paint: a cold
/// launch with no network shows the previous list instead of an empty box or a
/// spinner that never resolves.
enum AppsLoader {
    /// The published feed, unless `FOXSAY_APPS_FEED_URL` overrides it — which lets a
    /// development build read a local or staged feed without a code change.
    static let defaultFeedURL: URL = {
        if let override = ProcessInfo.processInfo.environment["FOXSAY_APPS_FEED_URL"],
           let url = URL(string: override) {
            return url
        }
        return URL(string: "https://skulkworks.dev/apps.json")!
    }()

    /// Fetches the feed and updates the on-disk cache. Throws on network or decode
    /// failure; callers should fall back to ``cached()``.
    static func load(from url: URL = defaultFeedURL) async throws -> AppsFeed {
        var request = URLRequest(url: url)
        // The feed is served with a short max-age; honour it rather than hitting
        // the site on every visit to the pane.
        request.timeoutInterval = 10
        let (data, _) = try await URLSession.shared.data(for: request)
        let feed = try JSONDecoder().decode(AppsFeed.self, from: data)
        writeCache(data)
        return feed
    }

    /// The last successfully fetched feed, or nil if one was never stored.
    static func cached() -> AppsFeed? {
        guard let url = cacheURL(), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(AppsFeed.self, from: data)
    }

    // MARK: - Cache

    private static func writeCache(_ data: Data) {
        guard let url = cacheURL() else { return }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try? data.write(to: url, options: .atomic)
    }

    /// `~/Library/Caches/<bundle id>/skulkworks-apps.json`. Caches rather than
    /// Application Support: it is re-fetchable and the system may reclaim it freely.
    private static func cacheURL() -> URL? {
        guard let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        else { return nil }
        let bundle = Bundle.main.bundleIdentifier ?? "dev.skulkworks.foxsay"
        return base.appendingPathComponent(bundle, isDirectory: true)
            .appendingPathComponent("skulkworks-apps.json")
    }
}

/// The app's in-memory copy of the published feed. A single shared store rather
/// than a fetch per view: it publishes the cached list immediately and refreshes
/// in the background, so the pane is never empty on first open.
@MainActor
final class AppsCatalog: ObservableObject {
    static let shared = AppsCatalog()

    /// Every app in the feed, in publication order.
    @Published private(set) var apps: [AppsFeed.Entry] = []
    /// Set when the last refresh failed and nothing was cached.
    @Published private(set) var loadError: String?

    private var isLoading = false

    private init() {
        apps = AppsLoader.cached()?.apps ?? []
    }

    /// Everything but the host app, which should never advertise itself. Matching is
    /// case-insensitive.
    func others(than currentApp: String) -> [AppsFeed.Entry] {
        let me = currentApp.lowercased()
        return apps.filter { $0.slug.lowercased() != me }
    }

    /// Fetches the feed, keeping the current list on screen if the fetch fails.
    func refresh(from url: URL = AppsLoader.defaultFeedURL) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let feed = try await AppsLoader.load(from: url)
            apps = feed.apps
            loadError = nil
        } catch {
            // A failed refresh must not empty a list we already have — offline, the
            // previously cached apps stay put.
            loadError = apps.isEmpty ? error.localizedDescription : nil
        }
    }
}

extension Color {
    /// Parses a CSS hex string ("#E22771" or "E22771"). Returns nil for anything
    /// else so callers can fall back to FoxSay's own accent colour.
    init?(hex: String) {
        var value = hex.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6, let rgb = UInt32(value, radix: 16) else { return nil }
        self.init(
            .sRGB,
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }
}
