import SwiftUI

/// Replaces AppKit's stock about panel: the "About FoxSay" menu item routes here so
/// the version and the update check live in the main window with everything else.
public struct AboutView: View {
    @ObservedObject private var updateBridge = UpdateCheckBridge.shared

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                identityCard

                updateCard

                linksCard

                Text(Self.copyright)
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Identity

    private var identityCard: some View {
        VStack(spacing: 8) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)

            Text("FoxSay")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Version \(Self.appVersion) (\(Self.appBuild))")
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .cardSurface()
    }

    // MARK: - Updates

    private var updateCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsSectionHeader("Updates", systemImage: "arrow.down.circle")

            // FoxSay ships direct, so the update check belongs somewhere visible.
            // Greyed out until the app shell's Sparkle updater registers itself.
            Button("Check for Updates…") {
                updateBridge.check()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!updateBridge.canCheck)

            Text("FoxSay turns speech into text on your Mac — transcription, AI cleanup and custom prompts. Nothing is uploaded unless you point it at a remote model; every local model runs on-device.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    // MARK: - Links

    private var linksCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsSectionHeader("Links", systemImage: "link")

            VStack(spacing: 0) {
                ForEach(Self.links, id: \.title) { link in
                    Link(link.title, destination: link.url)
                        .foregroundStyle(Color.accentColor)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)

                    if link.title != Self.links.last?.title {
                        Divider()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private static let links: [(title: String, url: URL)] = [
        ("FoxSay on skulkworks.dev", URL(string: "https://skulkworks.dev/foxsay")!),
        ("Release notes", URL(string: "https://github.com/skulkworks/foxsay/releases")!),
        ("Source on GitHub", URL(string: "https://github.com/skulkworks/foxsay")!),
        ("Privacy policy", URL(string: "https://skulkworks.dev/privacy")!),
    ]

    // MARK: - Bundle info

    private static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-"
    }

    private static var appBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "-"
    }

    private static var copyright: String {
        Bundle.main.infoDictionary?["NSHumanReadableCopyright"] as? String
            ?? "© \(Calendar.current.component(.year, from: .now)) SkulkWorks"
    }
}

#Preview {
    AboutView()
        .frame(width: 600, height: 700)
}
