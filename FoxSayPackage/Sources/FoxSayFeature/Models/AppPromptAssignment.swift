import Foundation
import AppKit

/// Reference to a specific remote LLM provider for per-app model assignment
public enum ModelReference: Codable, Equatable, Sendable, Hashable {
    case remote(providerId: UUID)

    /// Display name for the model
    @MainActor
    public var displayName: String {
        switch self {
        case .remote(let providerId):
            return LLMProviderManager.shared.remoteProviders
                .first { $0.id == providerId }?.name ?? "Unknown"
        }
    }

    /// Check if this provider is available for use
    @MainActor
    public var isAvailable: Bool {
        switch self {
        case .remote(let providerId):
            return LLMProviderManager.shared.remoteProviders
                .contains { $0.id == providerId && $0.isEnabled }
        }
    }
}

/// Maps an application to its default prompt and optional model override
public struct AppPromptAssignment: Codable, Identifiable, Sendable {
    public let id: UUID
    public var bundleId: String
    public var displayName: String
    public var defaultPromptId: UUID?
    public var defaultModelRef: ModelReference?

    public init(
        id: UUID = UUID(),
        bundleId: String,
        displayName: String,
        defaultPromptId: UUID? = nil,
        defaultModelRef: ModelReference? = nil
    ) {
        self.id = id
        self.bundleId = bundleId
        self.displayName = displayName
        self.defaultPromptId = defaultPromptId
        self.defaultModelRef = defaultModelRef
    }

    // Custom Codable for backward compatibility with existing data
    private enum CodingKeys: String, CodingKey {
        case id, bundleId, displayName, defaultPromptId, defaultModelRef
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        bundleId = try container.decode(String.self, forKey: .bundleId)
        displayName = try container.decode(String.self, forKey: .displayName)
        defaultPromptId = try container.decodeIfPresent(UUID.self, forKey: .defaultPromptId)
        defaultModelRef = try container.decodeIfPresent(ModelReference.self, forKey: .defaultModelRef)
    }

    /// Create an assignment from a running application
    @MainActor
    public static func from(app: NSRunningApplication, promptId: UUID? = nil) -> AppPromptAssignment? {
        guard let bundleId = app.bundleIdentifier else { return nil }

        return AppPromptAssignment(
            bundleId: bundleId,
            displayName: app.localizedName ?? bundleId,
            defaultPromptId: promptId
        )
    }

    /// Get the app icon from the system (loaded on-demand, not persisted)
    public var icon: NSImage? {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else {
            return nil
        }
        return NSWorkspace.shared.icon(forFile: appURL.path)
    }
}
