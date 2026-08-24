import AppKit
import ServiceManagement
import SwiftUI

/// General settings view
public struct GeneralSettingsView: View {
    @ObservedObject private var hotkeyManager = HotkeyManager.shared
    @ObservedObject private var audioEngine = AudioEngine.shared
    @ObservedObject private var correctionPipeline = CorrectionPipeline.shared
    @ObservedObject private var providerManager = LLMProviderManager.shared
    @EnvironmentObject private var appState: AppState

    @State private var isTestingHotkey = false

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SettingsPaneHeader(
                    "General",
                    description: "Recording keys, audio input, and where transcribed text goes."
                )

                keyboardControlsSection
                textProcessingSection
                inputSection
                outputSection
                appearanceSection

                Spacer()
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Keyboard Controls

    private var keyboardControlsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsSectionHeader("Keyboard Controls", systemImage: "keyboard")

            // Activation Keys Row
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Activation Keys")

                    Spacer()

                    // Activation mode picker
                    Menu {
                        ForEach(HotkeyManager.ActivationMode.allCases) { mode in
                            Button {
                                hotkeyManager.activationMode = mode
                            } label: {
                                HStack {
                                    Text(mode.displayName)
                                    if hotkeyManager.activationMode == mode {
                                        Spacer()
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        StyledMenuLabel(hotkeyManager.activationMode.displayName)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 140)

                    // Key picker
                    Menu {
                        Section("Right Side") {
                            ForEach(HotkeyManager.HotkeyModifier.rightSideModifiers) { modifier in
                                Button {
                                    hotkeyManager.selectedModifier = modifier
                                } label: {
                                    HStack {
                                        Text(modifier.shortName)
                                        if hotkeyManager.selectedModifier == modifier {
                                            Spacer()
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        }
                        Section("Left Side") {
                            ForEach(HotkeyManager.HotkeyModifier.leftSideModifiers) { modifier in
                                Button {
                                    hotkeyManager.selectedModifier = modifier
                                } label: {
                                    HStack {
                                        Text(modifier.shortName)
                                        if hotkeyManager.selectedModifier == modifier {
                                            Spacer()
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        }
                        Section("Other") {
                            Button {
                                hotkeyManager.selectedModifier = .fn
                            } label: {
                                HStack {
                                    Text(HotkeyManager.HotkeyModifier.fn.shortName)
                                    if hotkeyManager.selectedModifier == .fn {
                                        Spacer()
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        StyledMenuLabel(hotkeyManager.selectedModifier.shortName)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 120)
                }

                Text(activationModeDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            // Escape to cancel
            HStack {
                Image(systemName: "escape")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 20)

                Text("Use Escape to cancel recording")

                Spacer()

                Toggle("", isOn: $hotkeyManager.escapeToCancel)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }

            Divider()

            tryYourKeysSection
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private var activationModeDescription: String {
        switch hotkeyManager.activationMode {
        case .holdOrToggle:
            return "Auto-detects: quick tap to toggle recording, hold to record while pressed."
        case .toggle:
            return "Tap once to start recording, tap again to stop and transcribe."
        case .hold:
            return "Record while key is pressed, transcribe when released."
        case .doubleTap:
            return "Double-tap quickly to start recording, double-tap again to stop."
        }
    }

    private var accessibilityWarning: some View {
        SettingsWarningBanner(
            title: "Accessibility permission required",
            message: "FoxSay needs accessibility access to paste text into other apps.",
            actionTitle: "Grant Access"
        ) {
            HotkeyManager.requestAccessibilityPermission()
        }
    }

    private var tryYourKeysSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Try Your Keys")
                .font(.subheadline)
                .fontWeight(.medium)

            HStack(spacing: 8) {
                Image(systemName: hotkeyManager.isHotkeyPressed ? "checkmark.circle.fill" : "keyboard")
                    .font(.system(size: 12))
                    .foregroundStyle(hotkeyManager.isHotkeyPressed ? Color.accentColor : Color.secondary)

                Text(hotkeyManager.isHotkeyPressed
                    ? "Key detected — recording would start now"
                    : "Press \(hotkeyManager.selectedModifier.shortName) to test")
                    .font(.caption)
                    .foregroundStyle(hotkeyManager.isHotkeyPressed ? .primary : .secondary)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(hotkeyManager.isHotkeyPressed
                        ? Color.accentColor.opacity(0.1)
                        : Color.primary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(
                        hotkeyManager.isHotkeyPressed
                            ? Color.accentColor.opacity(0.45)
                            : Color.primary.opacity(0.08),
                        lineWidth: 1
                    )
            )
            .animation(.easeOut(duration: 0.18), value: hotkeyManager.isHotkeyPressed)
        }
    }

    // MARK: - Text Processing Section

    private var textProcessingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsSectionHeader("Text Processing", systemImage: "text.bubble")

            // Prompt selector hotkey
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Prompt Selector Hotkey")
                    Text("Open overlay to quickly select an AI prompt")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Toggle("", isOn: $hotkeyManager.promptSelectorEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }

            if hotkeyManager.promptSelectorEnabled {
                HStack {
                    Spacer()

                    Menu {
                        Section("Right Side") {
                            ForEach(HotkeyManager.HotkeyModifier.rightSideModifiers) { modifier in
                                Button {
                                    hotkeyManager.promptSelectorModifier = modifier
                                } label: {
                                    HStack {
                                        Text(modifier.shortName)
                                        if hotkeyManager.promptSelectorModifier == modifier {
                                            Spacer()
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        }
                        Section("Left Side") {
                            ForEach(HotkeyManager.HotkeyModifier.leftSideModifiers) { modifier in
                                Button {
                                    hotkeyManager.promptSelectorModifier = modifier
                                } label: {
                                    HStack {
                                        Text(modifier.shortName)
                                        if hotkeyManager.promptSelectorModifier == modifier {
                                            Spacer()
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        }
                        Section("Other") {
                            Button {
                                hotkeyManager.promptSelectorModifier = .fn
                            } label: {
                                HStack {
                                    Text(HotkeyManager.HotkeyModifier.fn.shortName)
                                    if hotkeyManager.promptSelectorModifier == .fn {
                                        Spacer()
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        StyledMenuLabel(hotkeyManager.promptSelectorModifier.shortName)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 140)
                }

                if hotkeyManager.promptSelectorModifier == hotkeyManager.selectedModifier {
                    Text("Choose a different key than the recording hotkey")
                        .font(.caption)
                        .foregroundStyle(Color.statusWarning)
                }
            }

            Divider()

            // Spoken punctuation
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Spoken Punctuation")
                    Text("Say \"comma\", \"question mark\", or \"quote … unquote\" to insert the marks")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Toggle("", isOn: $correctionPipeline.spokenPunctuationEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }

            if correctionPipeline.spokenPunctuationEnabled {
                Text("Words like \"period\" and \"quote\" become punctuation, even when you meant the word itself")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            // Vocal corrections
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Vocal Corrections")
                    Text("Use AI to clean up spoken self-corrections and false starts")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Toggle("", isOn: $correctionPipeline.vocalCorrectionsEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(!providerManager.isReady)
            }

            if !providerManager.isReady && !correctionPipeline.vocalCorrectionsEnabled {
                Text("Requires an AI model to be enabled")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    // MARK: - Input Section

    @State private var showOverlay: Bool = UserDefaults.standard.object(forKey: "showInputOverlay") as? Bool ?? true
    @State private var enableSoundEffects: Bool = UserDefaults.standard.object(forKey: "enableSoundEffects") as? Bool ?? false
    @State private var inputAmplitude: Double = {
        let stored = UserDefaults.standard.double(forKey: "inputAmplitude")
        return stored > 0 ? stored : 10.0
    }()
    @State private var visualizationStyle: VisualizationStyle = {
        let stored = UserDefaults.standard.string(forKey: "visualizationStyle") ?? "scrolling"
        return VisualizationStyle(rawValue: stored) ?? .scrolling
    }()

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsSectionHeader("Input", systemImage: "mic")

            // Microphone picker
            HStack {
                Text("Microphone")

                Spacer()

                Menu {
                    ForEach(audioEngine.availableDevices) { device in
                        Button {
                            audioEngine.selectedDeviceUID = device.uid
                        } label: {
                            HStack {
                                Text(device.name)
                                if audioEngine.selectedDeviceUID == device.uid {
                                    Spacer()
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    StyledMenuLabel(audioEngine.availableDevices.first { $0.uid == audioEngine.selectedDeviceUID }?.name ?? "Select...")
                }
                .buttonStyle(.plain)
                .frame(maxWidth: 200)

                RowActionButton("arrow.clockwise", help: "Refresh device list") {
                    audioEngine.refreshAvailableDevices()
                }
            }

            // Permission status
            if !audioEngine.hasPermission {
                HStack {
                    Text("Permission")
                    Spacer()
                    Button("Request Access") {
                        Task {
                            await audioEngine.checkPermission()
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            Divider()

            // Mute while recording
            HStack {
                Text("Mute while recording")

                Spacer()

                Toggle("", isOn: $audioEngine.muteWhileRecording)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }

            // Show overlay toggle
            HStack {
                Text("Show recording overlay")

                Spacer()

                Toggle("", isOn: Binding(
                    get: { showOverlay },
                    set: { newValue in
                        showOverlay = newValue
                        UserDefaults.standard.set(newValue, forKey: "showInputOverlay")
                    }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
            }

            // Overlay settings (only show if overlay enabled)
            if showOverlay {
                // Visualization style picker
                HStack {
                    Text("Visualization style")

                    Spacer()

                    Menu {
                        ForEach(VisualizationStyle.allCases) { style in
                            Button {
                                visualizationStyle = style
                                UserDefaults.standard.set(style.rawValue, forKey: "visualizationStyle")
                            } label: {
                                HStack {
                                    Text(style.displayName)
                                    if visualizationStyle == style {
                                        Spacer()
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        StyledMenuLabel(visualizationStyle.displayName)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 120)
                }

                // Visual amplitude slider. Continuous range keeps the track
                // clean; the setter rounds so the stored value stays integral.
                HStack {
                    Text("Visual amplitude")

                    Spacer()

                    Slider(value: Binding(
                        get: { inputAmplitude },
                        set: { newValue in
                            let rounded = newValue.rounded()
                            guard rounded != inputAmplitude else { return }
                            inputAmplitude = rounded
                            UserDefaults.standard.set(rounded, forKey: "inputAmplitude")
                        }
                    ), in: 5...20)
                    .controlSize(.small)
                    .frame(width: 140)

                    Text("\(Int(inputAmplitude))×")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .frame(width: 30, alignment: .trailing)
                }
            }

            // Sound effects toggle
            HStack {
                Text("Sound effects")

                Spacer()

                Toggle("", isOn: Binding(
                    get: { enableSoundEffects },
                    set: { newValue in
                        enableSoundEffects = newValue
                        UserDefaults.standard.set(newValue, forKey: "enableSoundEffects")
                    }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    // MARK: - Output Section

    @State private var pasteToActiveApp: Bool = UserDefaults.standard.object(forKey: "pasteToActiveApp") as? Bool ?? true
    @State private var copyToClipboard: Bool = UserDefaults.standard.bool(forKey: "copyToClipboard")
    @State private var saveToHistory: Bool = UserDefaults.standard.object(forKey: "saveToHistory") as? Bool ?? true

    /// Check if disabling this option would leave no options enabled
    private func canDisable(paste: Bool? = nil, copy: Bool? = nil, history: Bool? = nil) -> Bool {
        let newPaste = paste ?? pasteToActiveApp
        let newCopy = copy ?? copyToClipboard
        let newHistory = history ?? saveToHistory
        return newPaste || newCopy || newHistory
    }

    private var outputSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsSectionHeader("Output", systemImage: "doc.on.clipboard")

            HStack {
                Text("Paste into active app")
                Spacer()
                Toggle("", isOn: Binding(
                    get: { pasteToActiveApp },
                    set: { newValue in
                        if !newValue && !canDisable(paste: false) { return }
                        pasteToActiveApp = newValue
                        UserDefaults.standard.set(newValue, forKey: "pasteToActiveApp")
                    }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
            }

            HStack {
                Text("Copy to clipboard")
                Spacer()
                Toggle("", isOn: Binding(
                    get: { copyToClipboard },
                    set: { newValue in
                        if !newValue && !canDisable(copy: false) { return }
                        copyToClipboard = newValue
                        UserDefaults.standard.set(newValue, forKey: "copyToClipboard")
                    }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
            }

            HStack {
                Text("Save to history")
                Spacer()
                Toggle("", isOn: Binding(
                    get: { saveToHistory },
                    set: { newValue in
                        if !newValue && !canDisable(history: false) { return }
                        saveToHistory = newValue
                        UserDefaults.standard.set(newValue, forKey: "saveToHistory")
                    }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
            }

            Text(outputBehaviorDescription)
                .font(.caption)
                .foregroundStyle(.secondary)

            // Accessibility warning if paste is enabled but permission not granted
            if pasteToActiveApp && !HotkeyManager.checkAccessibilityPermission() {
                accessibilityWarning
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private var outputBehaviorDescription: String {
        var actions: [String] = []
        if pasteToActiveApp { actions.append("pasted at cursor") }
        if copyToClipboard { actions.append("copied to clipboard") }
        if saveToHistory { actions.append("saved to history") }

        if actions.isEmpty {
            return "At least one option must be enabled"
        } else if actions.count == 1 {
            return "Text will be \(actions[0])"
        } else {
            let last = actions.removeLast()
            return "Text will be \(actions.joined(separator: ", ")) and \(last)"
        }
    }

    // MARK: - Appearance Section

    @State private var showInMenuBar: Bool = UserDefaults.standard.bool(forKey: "showInMenuBar")
    @State private var showInDock: Bool = UserDefaults.standard.object(forKey: "showInDock") as? Bool ?? true
    @State private var launchAtLogin: Bool = SMAppService.mainApp.status == .enabled
    @State private var hideWindowOnLaunch: Bool = UserDefaults.standard.bool(forKey: "hideWindowOnLaunch")

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsSectionHeader("Appearance", systemImage: "paintbrush")

            HStack {
                Text("Launch at login")
                Spacer()
                Toggle("", isOn: Binding(
                    get: { launchAtLogin },
                    set: { newValue in
                        do {
                            if newValue {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                            launchAtLogin = newValue
                        } catch {
                            print("Failed to update launch at login: \(error)")
                        }
                    }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
            }

            HStack {
                Text("Hide window on launch")
                Spacer()
                Toggle("", isOn: Binding(
                    get: { hideWindowOnLaunch },
                    set: { newValue in
                        hideWindowOnLaunch = newValue
                        UserDefaults.standard.set(newValue, forKey: "hideWindowOnLaunch")
                    }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
            }

            HStack {
                Text("Show in menu bar")
                Spacer()
                Toggle("", isOn: Binding(
                    get: { showInMenuBar },
                    set: { newValue in
                        // Prevent disabling both
                        if !newValue && !showInDock {
                            return
                        }
                        showInMenuBar = newValue
                        UserDefaults.standard.set(newValue, forKey: "showInMenuBar")
                    }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
            }

            HStack {
                Text("Show in Dock")
                Spacer()
                Toggle("", isOn: Binding(
                    get: { showInDock },
                    set: { newValue in
                        // Prevent disabling both
                        if !newValue && !showInMenuBar {
                            return
                        }
                        showInDock = newValue
                        UserDefaults.standard.set(newValue, forKey: "showInDock")
                        updateDockVisibility(newValue)
                    }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
            }

            if !showInMenuBar || !showInDock {
                Text("At least one must be enabled to access the app")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private func updateDockVisibility(_ show: Bool) {
        NSApp.setActivationPolicy(show ? .regular : .accessory)
    }
}

#Preview {
    GeneralSettingsView()
        .environmentObject(AppState.shared)
        .frame(width: 450, height: 700)
}
