import Foundation
import Sparkle

/// Controller for managing Sparkle updates
@MainActor
final class UpdaterController: ObservableObject {
    static let shared = UpdaterController()

    let updaterController: SPUStandardUpdaterController

    @Published var canCheckForUpdates = false

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
    }

    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }
}
