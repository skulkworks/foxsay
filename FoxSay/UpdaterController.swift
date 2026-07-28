import Combine
import Foundation
import FoxSayFeature
import Sparkle

/// Controller for managing Sparkle updates
@MainActor
final class UpdaterController: ObservableObject {
    static let shared = UpdaterController()

    let updaterController: SPUStandardUpdaterController

    @Published var canCheckForUpdates = false

    private var cancellables = Set<AnyCancellable>()

    private init() {
        // Create the updater controller with default UI
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )

        // Observe canCheckForUpdates property
        updaterController.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)

        // Hand the updater to the package, where the About pane's "Check for
        // Updates…" button lives (the package never links Sparkle).
        UpdateCheckBridge.shared.action = { [weak self] in self?.checkForUpdates() }
        updaterController.updater.publisher(for: \.canCheckForUpdates)
            .sink { value in
                Task { @MainActor in UpdateCheckBridge.shared.canCheck = value }
            }
            .store(in: &cancellables)
    }

    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }
}
