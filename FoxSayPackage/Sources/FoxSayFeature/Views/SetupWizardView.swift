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
            HStack(spacing: 6) {
                ForEach(SetupStep.allCases, id: \.rawValue) { step in
                    Capsule()
                        .fill(step.rawValue <= currentStep.rawValue
                            ? Color.accentColor
                            : Color.primary.opacity(0.15))
                        .frame(width: step == currentStep ? 20 : 8, height: 5)
                }
            }
            .padding(.top, 20)
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: currentStep)

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

    /// Large glyph at the top of a step. Neutral by default; status color only
    /// when a permission is still missing.
    private func stepGlyph(_ systemName: String, isBlocked: Bool = false) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 52, weight: .light))
            .foregroundStyle(isBlocked ? Color.statusWarning : Color.accentColor)
    }

    private var welcomeStep: some View {
        VStack(spacing: 18) {
            // Brand moment: the app icon over a soft wash of the icon's own
            // coral gradient. The only place the gradient appears in settings.
            ZStack {
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(LinearGradient.brandCoral)
                    .frame(width: 124, height: 124)
                    .opacity(0.18)
                    .blur(radius: 14)

                Image("AppIconImage")
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 88, height: 88)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .shadow(color: Color.brandSlateDeep.opacity(0.25), radius: 10, y: 5)
            }

            VStack(spacing: 8) {
                Text("Welcome to FoxSay")
                    .font(.title)
                    .fontWeight(.semibold)

                Text("Dictate text anywhere on your Mac. Hold a key to record, release to transcribe.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Text("Let's set up a few things to get started.")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var microphoneStep: some View {
        VStack(spacing: 18) {
            stepGlyph(
                audioEngine.hasPermission ? "mic.circle" : "mic.slash.circle",
                isBlocked: !audioEngine.hasPermission
            )

            Text("Microphone Access")
                .font(.title2)
                .fontWeight(.semibold)

            Text("FoxSay needs access to your microphone to transcribe your speech.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if audioEngine.hasPermission {
                Label("Microphone access granted", systemImage: "checkmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(Color.statusOK)
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

        return VStack(spacing: 18) {
            stepGlyph(
                hasAccess ? "hand.raised.circle" : "hand.raised.slash",
                isBlocked: !hasAccess
            )

            Text("Accessibility Access")
                .font(.title2)
                .fontWeight(.semibold)

            Text("FoxSay needs accessibility access to paste transcribed text into your active application.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if hasAccess {
                Label("Accessibility access granted", systemImage: "checkmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(Color.statusOK)
            } else {
                VStack(spacing: 10) {
                    Button("Open System Settings") {
                        HotkeyManager.requestAccessibilityPermission()
                    }
                    .buttonStyle(.bordered)

                    Text("Enable FoxSay in the list, then return here")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("If it is already enabled, you may need to restart the app")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .id(refreshTrigger)  // Force view recreation when refreshTrigger changes
        .onAppear {
            print("FoxSay: Accessibility check = \(HotkeyManager.checkAccessibilityPermission())")
        }
    }

    private var modelDownloadStep: some View {
        VStack(spacing: 18) {
            stepGlyph("arrow.down.circle")

            Text("Download Speech Model")
                .font(.title2)
                .fontWeight(.semibold)

            Text("FoxSay transcribes locally. Choose a model and download it.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 10) {
                // Model picker
                Menu {
                    Button {
                        Task { await engineManager.selectModel(.parakeetV2) }
                    } label: {
                        HStack {
                            Text("Parakeet V2 (English)")
                            if engineManager.currentModelType == .parakeetV2 {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    Button {
                        Task { await engineManager.selectModel(.parakeetV3) }
                    } label: {
                        HStack {
                            Text("Parakeet V3 (Multilingual)")
                            if engineManager.currentModelType == .parakeetV3 {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    Divider()
                    Button {
                        Task { await engineManager.selectModel(.whisperBase) }
                    } label: {
                        HStack {
                            Text("Whisper Base")
                            if engineManager.currentModelType == .whisperBase {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    Button {
                        Task { await engineManager.selectModel(.whisperSmall) }
                    } label: {
                        HStack {
                            Text("Whisper Small")
                            if engineManager.currentModelType == .whisperSmall {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    Button {
                        Task { await engineManager.selectModel(.whisperLargeTurbo) }
                    } label: {
                        HStack {
                            Text("Whisper Large Turbo")
                            if engineManager.currentModelType == .whisperLargeTurbo {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                } label: {
                    StyledMenuLabel(modelPickerLabel)
                }
                .buttonStyle(.plain)
                .frame(width: 240)

                Text(engineManager.currentModelType.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(height: 32)

                if isDownloading {
                    ProgressView(value: engineManager.downloadProgress)
                        .progressViewStyle(.linear)
                        .frame(width: 200)

                    Text("Downloading… \(Int(engineManager.downloadProgress * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                } else if let error = downloadError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(Color.statusError)
                        .multilineTextAlignment(.center)

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
            .frame(maxWidth: .infinity)
            .cardSurface()
        }
    }

    private var completeStep: some View {
        VStack(spacing: 18) {
            stepGlyph("checkmark.circle")

            Text("You're All Set!")
                .font(.title)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 10) {
                completeRow("Microphone ready")
                completeRow("Auto-paste enabled")
                completeRow("Model downloaded")
            }

            Text("Hold your activation key to start recording. Release to transcribe and paste.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private func completeRow(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(Color.statusOK)
            Text(text)
                .font(.subheadline)
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

    private var modelPickerLabel: String {
        switch engineManager.currentModelType {
        case .parakeetV2: return "Parakeet V2 (English)"
        case .parakeetV3: return "Parakeet V3 (Multilingual)"
        case .parakeetTdtCtc110m: return "Parakeet 110M (English)"
        case .parakeetJa: return "Parakeet (Japanese)"
        case .whisperBase, .whisperKit: return "Whisper Base"
        case .whisperSmall: return "Whisper Small"
        case .whisperLargeTurbo: return "Whisper Large Turbo"
        case .whisperTiny: return "Whisper Tiny"
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
