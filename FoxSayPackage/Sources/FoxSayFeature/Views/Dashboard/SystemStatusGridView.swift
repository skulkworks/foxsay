import SwiftUI

/// Grid of system status cards
struct SystemStatusGridView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var audioEngine = AudioEngine.shared
    @ObservedObject private var modelManager = ModelManager.shared
    @ObservedObject private var aiModelManager = AIModelManager.shared
    @ObservedObject private var providerManager = LLMProviderManager.shared

    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible())
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            // Microphone
            SystemStatusCard(
                icon: audioEngine.hasPermission ? "mic.fill" : "mic.slash",
                label: "Microphone",
                value: microphoneValue,
                statusColor: audioEngine.hasPermission ? .dashboardBlue : .dashboardAmber,
                isLoading: false
            ) {
                openMicrophoneSettings()
            }

            // Accessibility
            SystemStatusCard(
                icon: accessibilityEnabled ? "hand.raised.fill" : "hand.raised",
                label: "Accessibility",
                value: accessibilityEnabled ? "Enabled" : "Permission Required",
                statusColor: accessibilityEnabled ? .dashboardBlue : .dashboardAmber,
                isLoading: false
            ) {
                HotkeyManager.requestAccessibilityPermission()
            }

            // Speech Model
            SystemStatusCard(
                icon: speechModelIcon,
                label: "Speech Model",
                value: speechModelValue,
                statusColor: speechModelStatusColor,
                isLoading: modelManager.isPreloading
            ) {
                appState.selectedSidebarItem = .models
            }

            // AI Model
            SystemStatusCard(
                icon: aiModelIcon,
                label: "AI Model",
                value: aiModelValue,
                statusColor: aiModelStatusColor,
                isLoading: aiModelManager.isPreloading
            ) {
                appState.selectedSidebarItem = .aiModels
            }
        }
    }

    // MARK: - Microphone

    private var microphoneValue: String {
        guard audioEngine.hasPermission else { return "Permission Required" }
        // Return a shortened device name
        let deviceName = audioEngine.selectedDeviceName
        if deviceName.count > 25 {
            return String(deviceName.prefix(22)) + "..."
        }
        return deviceName
    }

    private func openMicrophoneSettings() {
        if audioEngine.hasPermission {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                NSWorkspace.shared.open(url)
            }
        } else {
            Task {
                await audioEngine.checkPermission()
            }
        }
    }

    // MARK: - Accessibility

    private var accessibilityEnabled: Bool {
        HotkeyManager.checkAccessibilityPermission()
    }

    // MARK: - Speech Model

    private var speechModelIcon: String {
        if modelManager.isModelLoaded {
            return "waveform"
        } else if modelManager.isPreloading {
            return "arrow.trianglehead.2.clockwise.rotate.90"
        } else if modelManager.isModelReady {
            return "waveform"
        } else {
            return "arrow.down.circle"
        }
    }

    private var speechModelValue: String {
        if modelManager.isModelLoaded {
            return modelManager.currentModelType.shortName
        } else if modelManager.isPreloading {
            return "Loading..."
        } else if modelManager.isModelReady {
            return modelManager.currentModelType.shortName
        } else {
            return "Download Required"
        }
    }

    private var speechModelStatusColor: Color {
        if modelManager.isModelLoaded {
            return .dashboardBlue
        } else if modelManager.isPreloading {
            return .dashboardBlue
        } else if modelManager.isModelReady {
            return .dashboardBlue
        } else {
            return .dashboardAmber
        }
    }

    // MARK: - AI Model

    private var aiModelIcon: String {
        // Check remote provider first
        if providerManager.providerType == .remote && providerManager.isRemoteReady {
            return "globe"
        }
        // Then check local
        if aiModelManager.isModelLoaded {
            return "brain"
        } else if aiModelManager.isPreloading {
            return "arrow.trianglehead.2.clockwise.rotate.90"
        } else if aiModelManager.isModelReady {
            return "brain"
        } else if aiModelManager.selectedModelId != nil {
            return "arrow.down.circle"
        } else {
            return "brain"
        }
    }

    private var aiModelValue: String {
        // Check remote provider first
        if providerManager.providerType == .remote && providerManager.isRemoteReady,
           let provider = providerManager.selectedRemoteProvider {
            return provider.name
        }
        // Then check local
        if aiModelManager.isModelLoaded, let model = aiModelManager.selectedModel {
            return model.shortName
        } else if aiModelManager.isPreloading {
            return "Loading..."
        } else if aiModelManager.isModelReady, let model = aiModelManager.selectedModel {
            return model.shortName
        } else if aiModelManager.selectedModelId != nil {
            return "Download Required"
        } else {
            return "Not Selected"
        }
    }

    private var aiModelStatusColor: Color {
        // Check remote provider first
        if providerManager.providerType == .remote && providerManager.isRemoteReady {
            return .dashboardBlue
        }
        // Then check local
        if aiModelManager.isModelLoaded {
            return .dashboardBlue
        } else if aiModelManager.isPreloading {
            return .dashboardBlue
        } else if aiModelManager.isModelReady {
            return .dashboardBlue
        } else if aiModelManager.selectedModelId != nil {
            return .dashboardAmber
        } else {
            return .secondary
        }
    }
}

#Preview {
    SystemStatusGridView()
        .environmentObject(AppState.shared)
        .padding()
        .frame(width: 500)
}
