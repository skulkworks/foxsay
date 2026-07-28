import Foundation

// The changelog feed. Vendored from the shared `den` package for the same reason
// as the apps feed: FoxSay is a public repo and `den` is private, so a path
// dependency would leave anyone outside SkulkWorks unable to build. The wire
// format is unchanged, so FoxSay's feed stays interchangeable with Magpie's and
// Riffle's and the website reads all three the same way.

/// The published changelog feed, compiled from `changelog/*.md` by
/// `scripts/generate-changelog.sh`: newest version first, each with typed
/// sections of Markdown bullet items. The feed also carries pre-rendered HTML
/// per version for web consumers; this window renders the structured sections
/// instead, so that field is not decoded here.
struct ChangelogFeed: Codable, Equatable, Sendable {
    var schema: Int
    var app: String
    var versions: [Entry]

    struct Entry: Codable, Equatable, Sendable, Identifiable {
        var version: String
        var build: Int
        /// ISO date string (`yyyy-MM-dd`), as written in the entry's frontmatter.
        var date: String
        var sections: [Section]

        var id: String { version }

        /// The entry's date formatted for display, falling back to the raw string
        /// when it doesn't parse.
        var displayDate: String {
            let parser = DateFormatter()
            parser.dateFormat = "yyyy-MM-dd"
            parser.locale = Locale(identifier: "en_US_POSIX")
            guard let parsed = parser.date(from: date) else { return date }
            return parsed.formatted(date: .abbreviated, time: .omitted)
        }
    }

    struct Section: Codable, Equatable, Sendable {
        var name: String
        /// Stable slug for badge styling: "new", "improved", or "fixed"; free-form
        /// headings come through as other values and get a neutral badge.
        var type: String
        var items: [String]
    }
}

/// Fetches and decodes a changelog feed. The feeds are published with `no-cache`,
/// so a plain shared-session request always sees the latest release.
enum ChangelogLoader {
    struct FeedUnavailable: LocalizedError {
        let status: Int
        var errorDescription: String? {
            status == 404
                ? "The changelog hasn't been published yet."
                : "The changelog server returned an error (\(status))."
        }
    }

    static func load(from url: URL) async throws -> ChangelogFeed {
        let (data, response) = try await URLSession.shared.data(from: url)
        // Check the status before decoding: a 404 from static hosting returns an
        // HTML error page, which would otherwise surface as "the data isn't in the
        // correct format" and send you looking for a bug in the feed.
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw FeedUnavailable(status: http.statusCode)
        }
        return try JSONDecoder().decode(ChangelogFeed.self, from: data)
    }
}
