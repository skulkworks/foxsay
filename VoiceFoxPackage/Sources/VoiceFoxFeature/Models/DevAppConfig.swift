import Foundation

/// Configuration for developer app detection
public struct DevAppConfig: Codable, Identifiable, Sendable {
    public var id: String { bundleId }

    /// Bundle identifier of the app
    public let bundleId: String

    /// Display name of the app
    public let displayName: String

    /// Whether dev corrections are enabled for this app
    public var isEnabled: Bool

    public init(bundleId: String, displayName: String, isEnabled: Bool = true) {
        self.bundleId = bundleId
        self.displayName = displayName
        self.isEnabled = isEnabled
    }

    /// Default developer apps to detect
    public static let defaultApps: [DevAppConfig] = [
        DevAppConfig(bundleId: "com.googlecode.iterm2", displayName: "iTerm2"),
        DevAppConfig(bundleId: "com.apple.Terminal", displayName: "Terminal"),
        DevAppConfig(bundleId: "com.microsoft.VSCode", displayName: "Visual Studio Code"),
        DevAppConfig(bundleId: "com.jetbrains.PhpStorm", displayName: "PhpStorm"),
        DevAppConfig(bundleId: "com.jetbrains.WebStorm", displayName: "WebStorm"),
        DevAppConfig(bundleId: "com.jetbrains.intellij", displayName: "IntelliJ IDEA"),
        DevAppConfig(bundleId: "com.apple.dt.Xcode", displayName: "Xcode"),
        DevAppConfig(bundleId: "com.sublimehq.Sublime-Text", displayName: "Sublime Text"),
        DevAppConfig(bundleId: "dev.zed.Zed", displayName: "Zed"),
        DevAppConfig(bundleId: "com.cursor.Cursor", displayName: "Cursor"),
    ]
}

/// Manager for dev app configuration persistence
@MainActor
public class DevAppConfigManager: ObservableObject {
    public static let shared = DevAppConfigManager()

    @Published public private(set) var apps: [DevAppConfig]

    private let userDefaultsKey = "devAppConfigs"

    private init() {
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let decoded = try? JSONDecoder().decode([DevAppConfig].self, from: data)
        {
            apps = decoded
        } else {
            apps = DevAppConfig.defaultApps
        }
    }

    public func isDevApp(bundleId: String) -> Bool {
        apps.first { $0.bundleId == bundleId && $0.isEnabled } != nil
    }

    public func setEnabled(_ enabled: Bool, for bundleId: String) {
        guard let index = apps.firstIndex(where: { $0.bundleId == bundleId }) else { return }
        apps[index].isEnabled = enabled
        save()
    }

    public func addApp(_ config: DevAppConfig) {
        guard !apps.contains(where: { $0.bundleId == config.bundleId }) else { return }
        apps.append(config)
        save()
    }

    public func removeApp(bundleId: String) {
        apps.removeAll { $0.bundleId == bundleId }
        save()
    }

    public func resetToDefaults() {
        apps = DevAppConfig.defaultApps
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(apps) {
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        }
    }
}
