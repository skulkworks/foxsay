import SwiftUI

/// Step-by-step setup wizard for first launch
public struct SetupWizardView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var audioEngine = AudioEngine.shared
    @ObservedObject private var engineManager = EngineManager.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    public enum SetupStep: Int, CaseIterable {
        case welcome
        case microphone
        case accessibility
        case modelDownload
        case complete

        var title: String {
            switch self {
            case .welcome: return "Welcome to FoxSay"
            case .microphone: return "Microphone Access"
            case .accessibility: return "Accessibility Access"
            case .modelDownload: return "Download Model"
            case .complete: return "Setup Complete"
            }
        }
    }

    @State private var currentStep: SetupStep = .welcome
    @State private var isDownloading = false
    @State private var downloadError: String?
    @State private var refreshTrigger = false  // Used to force view refresh

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Progress indicators
            HStack(spacing: 8) {
                ForEach(SetupStep.allCases, id: \.rawValue) { step in
                    Circle()
                        .fill(step.rawValue <= currentStep.rawValue ? Color.accentColor : Color.gray.opacity(0.3))
                        .frame(width: 10, height: 10)
                }
            }
            .padding(.top, 20)

            Spacer()

            // Content for current step
            stepContent
                .padding(.horizontal, 40)

            Spacer()

            // Navigation buttons
            HStack {
                if currentStep != .welcome && currentStep != .complete {
                    Button("Back") {
                        withAnimation {
                            goToPreviousStep()
                        }
                    }
                    .buttonStyle(.bordered)
                }

                Spacer()

                if currentStep == .complete {
                    Button("Get Started") {
                        markSetupComplete()
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button(nextButtonTitle) {
                        withAnimation {
                            handleNextAction()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isNextDisabled)
                }
            }
            .padding(20)
        }
        .frame(width: 500, height: 450)
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                // Refresh permission states when app becomes active
                refreshTrigger.toggle()
            }
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch currentStep {
        case .welcome:
            welcomeStep
        case .microphone:
            microphoneStep
        case .accessibility:
            accessibilityStep
        case .modelDownload:
            modelDownloadStep
        case .complete:
            completeStep
        }
    }

    private var welcomeStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(.accentColor)

            Text("Welcome to FoxSay")
                .font(.title)
                .fontWeight(.bold)

            Text("FoxSay lets you dictate text anywhere on your Mac using speech-to-text. Hold a key to record, release to transcribe.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Text("Let's set up a few things to get started.")
                .font(.callout)
                .foregroundColor(.secondary)
        }
    }

    private var microphoneStep: some View {
        VStack(spacing: 20) {
            Image(systemName: audioEngine.hasPermission ? "mic.circle.fill" : "mic.slash")
                .font(.system(size: 64))
                .foregroundColor(audioEngine.hasPermission ? .secondaryAccent : .orange)

            Text("Microphone Access")
                .font(.title2)
                .fontWeight(.bold)

            Text("FoxSay needs access to your microphone to transcribe your speech.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            if audioEngine.hasPermission {
                Label("Microphone access granted", systemImage: "checkmark.circle.fill")
                    .foregroundColor(.secondaryAccent)
            } else {
                Button("Grant Microphone Access") {
                    Task {
                        await audioEngine.checkPermission()
                    }
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var accessibilityStep: some View {
        let hasAccess = HotkeyManager.checkAccessibilityPermission()

        return VStack(spacing: 20) {
            Image(systemName: hasAccess ? "hand.raised.circle.fill" : "hand.raised.slash")
                .font(.system(size: 64))
                .foregroundColor(hasAccess ? .secondaryAccent : .orange)

            Text("Accessibility Access")
                .font(.title2)
                .fontWeight(.bold)

            Text("FoxSay needs accessibility access to automatically paste transcribed text into your active application.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            if hasAccess {
                Label("Accessibility access granted", systemImage: "checkmark.circle.fill")
                    .foregroundColor(.secondaryAccent)
            } else {
                VStack(spacing: 12) {
                    Button("Open System Settings") {
                        HotkeyManager.requestAccessibilityPermission()
                    }
                    .buttonStyle(.bordered)

                    Text("Enable FoxSay in the list, then return here")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("If already enabled, you may need to restart the app")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                }
            }
        }
        .id(refreshTrigger)  // Force view recreation when refreshTrigger changes
        .onAppear {
            print("VoiceFox: Accessibility check = \(HotkeyManager.checkAccessibilityPermission())")
        }
    }

    private var modelDownloadStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(.accentColor)

            Text("Download Speech Model")
                .font(.title2)
                .fontWeight(.bold)

            Text("FoxSay uses a local AI model for transcription. This needs to be downloaded once (~150 MB).")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 8) {
                Text("WhisperKit (base.en)")
                    .font(.headline)

                if isDownloading {
                    ProgressView(value: engineManager.downloadProgress)
                        .progressViewStyle(.linear)
                        .tint(.secondaryAccent)
                        .frame(width: 200)

                    Text("Downloading... \(Int(engineManager.downloadProgress * 100))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else if let error = downloadError {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.tertiaryAccent)

                    Button("Retry") {
                        startDownload()
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button("Download Model") {
                        startDownload()
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding()
            .background(Color(.textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private var completeStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(.secondaryAccent)

            Text("You're All Set!")
                .font(.title)
                .fontWeight(.bold)

            VStack(alignment: .leading, spacing: 12) {
                Label("Microphone ready", systemImage: "checkmark.circle.fill")
                    .foregroundColor(.secondaryAccent)
                Label("Auto-paste enabled", systemImage: "checkmark.circle.fill")
                    .foregroundColor(.secondaryAccent)
                Label("Model downloaded", systemImage: "checkmark.circle.fill")
                    .foregroundColor(.secondaryAccent)
            }
            .padding()

            Text("Hold your activation key to start recording. Release to transcribe and paste.")
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var nextButtonTitle: String {
        switch currentStep {
        case .welcome:
            return "Continue"
        case .microphone:
            return audioEngine.hasPermission ? "Continue" : "Skip"
        case .accessibility:
            return HotkeyManager.checkAccessibilityPermission() ? "Continue" : "Skip"
        case .modelDownload:
            return "Skip"
        case .complete:
            return "Get Started"
        }
    }

    private var isNextDisabled: Bool {
        if currentStep == .modelDownload && isDownloading {
            return true
        }
        return false
    }

    private func handleNextAction() {
        switch currentStep {
        case .welcome:
            currentStep = .microphone
        case .microphone:
            currentStep = .accessibility
        case .accessibility:
            currentStep = .modelDownload
        case .modelDownload:
            currentStep = .complete
        case .complete:
            break
        }
    }

    private func goToPreviousStep() {
        switch currentStep {
        case .welcome:
            break
        case .microphone:
            currentStep = .welcome
        case .accessibility:
            currentStep = .microphone
        case .modelDownload:
            currentStep = .accessibility
        case .complete:
            currentStep = .modelDownload
        }
    }

    private func startDownload() {
        isDownloading = true
        downloadError = nil

        Task {
            do {
                try await engineManager.downloadCurrentModel()
                await MainActor.run {
                    isDownloading = false
                    // Auto-advance to complete step
                    currentStep = .complete
                }
            } catch {
                await MainActor.run {
                    isDownloading = false
                    downloadError = error.localizedDescription
                }
            }
        }
    }

    private func markSetupComplete() {
        UserDefaults.standard.set(true, forKey: "setupComplete")
    }

    public static var needsSetup: Bool {
        !UserDefaults.standard.bool(forKey: "setupComplete")
    }
}

#Preview {
    SetupWizardView()
        .environmentObject(AppState.shared)
}
