import AppKit
import SwiftUI

/// The list comes from skulkworks.dev/apps.json, so a new app reaches everyone already
/// running FoxSay without shipping a release. FoxSay leaves itself out — the slug is
/// filtered even though the feed doesn't carry FoxSay yet, so nothing changes here the
/// day the site does.
public struct OurAppsView: View {
    @ObservedObject private var catalog = AppsCatalog.shared

    public init() {}

    private var apps: [AppsFeed.Entry] { catalog.others(than: "foxsay") }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SettingsPaneHeader(
                    "Our Apps",
                    description: "More from SkulkWorks. Every app runs on your Mac."
                )

                if !apps.isEmpty {
                    LazyVStack(spacing: 10) {
                        ForEach(apps) { AppRow(app: $0) }
                    }

                    HStack(spacing: 4) {
                        Text("See them all at")
                        Link("skulkworks.dev", destination: URL(string: "https://skulkworks.dev")!)
                            .foregroundStyle(Color.accentColor)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else if let error = catalog.loadError {
                    unavailable(error)
                } else {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity, minHeight: 120)
                }

                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Refresh on every appearance: opening the pane is exactly when a stale list
        // should be corrected, and the feed's cache headers keep it cheap.
        .task { await catalog.refresh() }
    }

    /// Shown when the feed can't be reached and nothing was ever cached. Quiet by
    /// design — a pane that can't reach the network shouldn't look broken.
    @ViewBuilder
    private func unavailable(_ message: String?) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "wifi.exclamationmark")
                .font(.title)
                .foregroundStyle(.secondary)

            Text("Couldn't load the app list")
                .font(.callout)

            if let message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Link("See them at skulkworks.dev", destination: URL(string: "https://skulkworks.dev")!)
                .foregroundStyle(Color.accentColor)
                .font(.callout)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

/// One app: icon, name, one-line summary, and a hover affordance. The whole row is
/// the button, so there's no small target to hunt for. The per-app brand colour is
/// the one place FoxSay's single-accent rule gives way — these are other apps'
/// identities, and it stays confined to the arrow and a hover hairline.
private struct AppRow: View {
    let app: AppsFeed.Entry

    @State private var isHovering = false

    var body: some View {
        Button {
            NSWorkspace.shared.open(app.url)
        } label: {
            HStack(spacing: 14) {
                icon

                VStack(alignment: .leading, spacing: 3) {
                    Text(app.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)

                    Text(app.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Image(systemName: "arrow.up.forward")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(accent)
                    .opacity(isHovering ? 1 : 0.35)
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            // Same geometry as .cardSurface(), so the rows sit in FoxSay's card
            // system rather than carrying a control-background fill of their own.
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        isHovering ? accent.opacity(0.55) : Color.primary.opacity(0.07),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.18), value: isHovering)
        .help("Open \(app.name) on skulkworks.dev")
        .accessibilityLabel("\(app.name). \(app.summary)")
    }

    @ViewBuilder
    private var icon: some View {
        // URLSession's shared cache keeps these off the network after first paint.
        AsyncImage(url: app.icon) { phase in
            if let image = phase.image {
                image.resizable().interpolation(.high).scaledToFit()
            } else {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(accent.opacity(0.18))
            }
        }
        .frame(width: 48, height: 48)
        .accessibilityHidden(true)
    }

    private var accent: Color {
        Color(hex: app.color) ?? .accentColor
    }
}

#Preview {
    OurAppsView()
        .frame(width: 600, height: 700)
}
