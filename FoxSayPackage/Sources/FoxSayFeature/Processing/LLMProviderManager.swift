import Foundation
import os.log

private let providerLog = OSLog(subsystem: "com.foxsay", category: "LLM-PROVIDER")

/// Result of a connection test to a remote provider
public enum ConnectionTestResult: Equatable {
    case idle
    case testing
    case success([String])
    case failure(String)
}

/// Central coordinator for LLM providers (local and remote)
@MainActor
public class LLMProviderManager: ObservableObject {
    public static let shared = LLMProviderManager()

    // MARK: - UserDefaults Keys

    private static let providerTypeKey = "llmProviderType"
    private static let remoteProvidersKey = "llmRemoteProviders"
    private static let selectedRemoteProviderIdKey = "llmSelectedRemoteProviderId"

    // MARK: - Published Properties

    /// The type of provider currently selected
    @Published public var providerType: LLMProviderType {
        didSet {
            UserDefaults.standard.set(providerType.rawValue, forKey: Self.providerTypeKey)
            os_log(.info, log: providerLog, "Provider type changed to: %{public}@", providerType.rawValue)
        }
    }

    /// List of configured remote providers
    @Published public var remoteProviders: [RemoteProvider] {
        didSet {
            saveRemoteProviders()
        }
    }

    /// ID of the currently selected remote provider
    @Published public var selectedRemoteProviderId: UUID? {
        didSet {
            if let id = selectedRemoteProviderId {
                UserDefaults.standard.set(id.uuidString, forKey: Self.selectedRemoteProviderIdKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.selectedRemoteProviderIdKey)
            }
        }
    }

    /// Connection test result for each provider (keyed by UUID)
    @Published public var connectionTestResults: [UUID: ConnectionTestResult] = [:]

    // MARK: - Computed Properties

    /// Whether ANY provider is ready to use (local model OR remote provider)
    public var isReady: Bool {
        isLocalReady || isRemoteReady
    }

    /// Whether a local model is ready
    public var isLocalReady: Bool {
        AIModelManager.shared.isModelReady
    }

    /// Whether a remote provider is ready
    public var isRemoteReady: Bool {
        guard let selectedId = selectedRemoteProviderId,
              let provider = remoteProviders.first(where: { $0.id == selectedId }),
              provider.isEnabled else {
            return false
        }
        return true
    }

    /// The actual active provider type (based on what's configured, not the tab)
    public var activeProviderType: LLMProviderType? {
        if isLocalReady { return .local }
        if isRemoteReady { return .remote }
        return nil
    }

    /// Get the currently selected remote provider
    public var selectedRemoteProvider: RemoteProvider? {
        guard let id = selectedRemoteProviderId else { return nil }
        return remoteProviders.first { $0.id == id }
    }

    // MARK: - Initialization

    private init() {
        // Load provider type
        if let typeString = UserDefaults.standard.string(forKey: Self.providerTypeKey),
           let type = LLMProviderType(rawValue: typeString) {
            providerType = type
        } else {
            providerType = .local
        }

        // Load remote providers
        if let data = UserDefaults.standard.data(forKey: Self.remoteProvidersKey),
           let providers = try? JSONDecoder().decode([RemoteProvider].self, from: data) {
            remoteProviders = providers
        } else {
            // Initialize with presets
            remoteProviders = RemoteProvider.presets.map { $0.createCopy() }
        }

        // Load selected remote provider ID
        if let idString = UserDefaults.standard.string(forKey: Self.selectedRemoteProviderIdKey),
           let id = UUID(uuidString: idString) {
            selectedRemoteProviderId = id
        }

        os_log(.info, log: providerLog, "LLMProviderManager initialized: type=%{public}@, providers=%d",
               providerType.rawValue, remoteProviders.count)
    }

    // MARK: - Provider Management

    /// Get the appropriate transformer based on what's actually active
    public func getTransformer() async -> (any TextTransformer)? {
        // Check what's actually active (local takes priority if both are somehow configured)
        if isLocalReady {
            return LocalLLMTransformer.shared
        }
        if isRemoteReady, let provider = selectedRemoteProvider, provider.isEnabled {
            return RemoteLLMService(provider: provider)
        }
        return nil
    }

    /// Add a new remote provider
    public func addProvider(_ provider: RemoteProvider) {
        remoteProviders.append(provider)
    }

    /// Update an existing remote provider
    public func updateProvider(_ provider: RemoteProvider) {
        if let index = remoteProviders.firstIndex(where: { $0.id == provider.id }) {
            remoteProviders[index] = provider
        }
    }

    /// Delete a remote provider
    public func deleteProvider(_ provider: RemoteProvider) {
        remoteProviders.removeAll { $0.id == provider.id }
        if selectedRemoteProviderId == provider.id {
            selectedRemoteProviderId = nil
        }
        connectionTestResults.removeValue(forKey: provider.id)
    }

    /// Select a remote provider (also switches to remote mode and deactivates local model)
    public func selectProvider(_ provider: RemoteProvider) {
        // Deactivate local model when switching to remote
        AIModelManager.shared.deactivateModel()

        selectedRemoteProviderId = provider.id
        providerType = .remote
        os_log(.info, log: providerLog, "Selected remote provider: %{public}@", provider.name)
    }

    /// Activate local mode (deactivates remote provider)
    public func activateLocalMode() {
        selectedRemoteProviderId = nil
        providerType = .local
        os_log(.info, log: providerLog, "Switched to local mode")
    }

    /// Deactivate all providers (both local and remote)
    public func deactivate() {
        // Deactivate local model if active
        if AIModelManager.shared.isModelReady {
            AIModelManager.shared.deactivateModel()
        }
        // Deselect remote provider if selected
        if selectedRemoteProviderId != nil {
            selectedRemoteProviderId = nil
        }
        os_log(.info, log: providerLog, "All providers deactivated")
    }

    /// Test connection to a remote provider
    public func testConnection(for provider: RemoteProvider) async {
        connectionTestResults[provider.id] = .testing

        let service = RemoteLLMService(provider: provider)
        let result = await service.testConnection()

        switch result {
        case .success(let models):
            connectionTestResults[provider.id] = .success(models)
            os_log(.info, log: providerLog, "Connection test succeeded for %{public}@: %d models",
                   provider.name, models.count)
        case .failure(let error):
            connectionTestResults[provider.id] = .failure(error.localizedDescription)
            os_log(.error, log: providerLog, "Connection test failed for %{public}@: %{public}@",
                   provider.name, error.localizedDescription)
        }
    }

    /// Reset connection test result for a provider
    public func resetConnectionTest(for provider: RemoteProvider) {
        connectionTestResults[provider.id] = .idle
    }

    // MARK: - Persistence

    private func saveRemoteProviders() {
        if let data = try? JSONEncoder().encode(remoteProviders) {
            UserDefaults.standard.set(data, forKey: Self.remoteProvidersKey)
        }
    }
}
