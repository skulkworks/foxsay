import AppKit
import ServiceManagement
import SwiftUI

/// General settings view
public struct GeneralSettingsView: View {
    @ObservedObject private var hotkeyManager = HotkeyManager.shared
    @ObservedObject private var audioEngine = AudioEngine.shared
    @EnvironmentObject private var appState: AppState

    @State private var isTestingHotkey = false

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                Text("General")
                    .font(.title2)
                    .fontWeight(.bold)

                // Keyboard Controls Section
                keyboardControlsSection

                // Text Processing Section
                textProcessingSection

                // Input Section (Microphone)
                inputSection

                // Output Section
                outputSection

                // Appearance Section
                appearanceSection

                Spacer()
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Keyboard Controls

    private var keyboardControlsSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                Label("Keyboard Controls", systemImage: "keyboard")
                    .font(.headline)

                // Activation Keys Row
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Activation Keys")
                            .foregroundStyle(.primary)

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
                        .frame(width: 24)
                        .foregroundStyle(.secondary)

                    Text("Use Escape to cancel recording")

                    Spacer()

                    Toggle("", isOn: $hotkeyManager.escapeToCancel)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }

                Divider()

                // Try Your Keys section
                tryYourKeysSection
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
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
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            Text("Accessibility permission required to paste text into apps")
                .font(.caption)
            Spacer()
            Button("Grant Access") {
                HotkeyManager.requestAccessibilityPermission()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(10)
        .background(Color.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var tryYourKeysSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Try Your Keys")
                .font(.subheadline)
                .fontWeight(.medium)

            HStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(hotkeyManager.isHotkeyPressed ? Color.secondaryAccent.opacity(0.2) : Color(.textBackgroundColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(hotkeyManager.isHotkeyPressed ? Color.secondaryAccent : Color.secondary.opacity(0.3), lineWidth: 1)
                        )

                    HStack(spacing: 8) {
                        Image(systemName: hotkeyManager.isHotkeyPressed ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(hotkeyManager.isHotkeyPressed ? .secondaryAccent : .secondary)

                        Text(hotkeyManager.isHotkeyPressed ? "Key detected! Recording..." : "Press \(hotkeyManager.selectedModifier.shortName) to test")
                            .font(.caption)
                            .foregroundStyle(hotkeyManager.isHotkeyPressed ? .primary : .secondary)
                    }
                    .padding(.horizontal, 12)
                }
                .frame(height: 36)
            }
        }
    }

    // MARK: - Text Processing Section

    private var textProcessingSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Label("Text Processing", systemImage: "text.bubble")
                    .font(.headline)

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
                            .foregroundColor(.orange)
                    }
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
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
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Label("Input", systemImage: "mic")
                    .font(.headline)

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

                    Button {
                        audioEngine.refreshAvailableDevices()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .help("Refresh device list")
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

                    // Visual amplitude slider
                    HStack {
                        Text("Visual amplitude")

                        Spacer()

                        Slider(value: Binding(
                            get: { inputAmplitude },
                            set: { newValue in
                                inputAmplitude = newValue
                                UserDefaults.standard.set(newValue, forKey: "inputAmplitude")
                            }
                        ), in: 5...20, step: 1)
                        .frame(width: 120)

                        Text("\(Int(inputAmplitude))x")
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
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
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Label("Output", systemImage: "doc.on.clipboard")
                    .font(.headline)

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

                // Accessibility warning if paste is enabled but permission not granted
                if pasteToActiveApp && !HotkeyManager.checkAccessibilityPermission() {
                    accessibilityWarning
                }

                Text(outputBehaviorDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
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
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Label("Appearance", systemImage: "paintbrush")
                    .font(.headline)

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
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
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
