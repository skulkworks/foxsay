import SwiftUI

/// The native changelog list: every published version, newest first, with a
/// colored badge per section type and the bullet items rendered from their
/// inline Markdown. Loads the feed when it appears; shows a spinner while
/// loading and a retry button on failure.
///
/// Vendored from the shared `den` package, and deliberately kept looking the
/// same as Magpie's and Riffle's so "What's New" reads identically across the
/// apps.
struct ChangelogView: View {
    private let feedURL: URL

    private enum LoadState {
        case loading
        case failed(String)
        case loaded(ChangelogFeed)
    }

    @State private var state: LoadState = .loading

    init(feedURL: URL) {
        self.feedURL = feedURL
    }

    var body: some View {
        Group {
            switch state {
            case .loading:
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

            case let .failed(message):
                VStack(spacing: 12) {
                    Image(systemName: "wifi.exclamationmark")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)

                    Text("Couldn't load the changelog")
                        .font(.headline)

                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    Button("Try Again") {
                        state = .loading
                        Task { await load() }
                    }
                }
                .padding(32)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            case let .loaded(feed):
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 24) {
                        ForEach(feed.versions) { entry in
                            versionBlock(entry, isLatest: entry.id == feed.versions.first?.id)
                        }
                    }
                    .padding(20)
                }
            }
        }
        .task { await load() }
    }

    private func load() async {
        do {
            state = .loaded(try await ChangelogLoader.load(from: feedURL))
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    @ViewBuilder
    private func versionBlock(_ entry: ChangelogFeed.Entry, isLatest: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(entry.version)
                    .font(.title3.bold())

                if isLatest {
                    Text("Latest")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.tint.opacity(0.15), in: Capsule())
                        .foregroundStyle(.tint)
                }

                Spacer()

                Text(entry.displayDate)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            ForEach(Array(entry.sections.enumerated()), id: \.offset) { _, section in
                sectionBlock(section)
            }

            Divider()
                .padding(.top, 6)
        }
    }

    @ViewBuilder
    private func sectionBlock(_ section: ChangelogFeed.Section) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(section.name)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(badgeColor(for: section.type).opacity(0.16), in: Capsule())
                .foregroundStyle(badgeColor(for: section.type))

            ForEach(Array(section.items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Circle()
                        .fill(.tertiary)
                        .frame(width: 4, height: 4)
                        .alignmentGuide(.firstTextBaseline) { _ in 3 }

                    Text(markdown(item))
                        .font(.callout)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private func badgeColor(for type: String) -> Color {
        switch type {
        case "new": return .green
        case "improved": return .blue
        case "fixed": return .orange
        default: return .secondary
        }
    }

    /// Bullet items are Markdown (inline code, bold, links); render inline syntax
    /// and fall back to the raw text if parsing fails.
    private func markdown(_ item: String) -> AttributedString {
        (try? AttributedString(
            markdown: item,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(item)
    }
}
