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

                // Sound Section (Microphone)
                soundSection

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

                // Accessibility warning if needed
                if !HotkeyManager.checkAccessibilityPermission() {
                    accessibilityWarning
                }

                // Activation Keys Row
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Activation Keys")
                            .foregroundStyle(.primary)

                        Spacer()

                        // Activation mode picker
                        Picker("", selection: $hotkeyManager.activationMode) {
                            ForEach(HotkeyManager.ActivationMode.allCases) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 140)

                        // Key picker
                        Picker("", selection: $hotkeyManager.selectedModifier) {
                            Section("Right Side") {
                                ForEach(HotkeyManager.HotkeyModifier.rightSideModifiers) { modifier in
                                    Text(modifier.shortName).tag(modifier)
                                }
                            }
                            Section("Left Side") {
                                ForEach(HotkeyManager.HotkeyModifier.leftSideModifiers) { modifier in
                                    Text(modifier.shortName).tag(modifier)
                                }
                            }
                            Section("Other") {
                                Text(HotkeyManager.HotkeyModifier.fn.shortName).tag(HotkeyManager.HotkeyModifier.fn)
                            }
                        }
                        .pickerStyle(.menu)
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
            Text("Accessibility permission required")
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
                        .fill(hotkeyManager.isHotkeyPressed ? Color.green.opacity(0.2) : Color(.textBackgroundColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(hotkeyManager.isHotkeyPressed ? Color.green : Color.secondary.opacity(0.3), lineWidth: 1)
                        )

                    HStack(spacing: 8) {
                        Image(systemName: hotkeyManager.isHotkeyPressed ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(hotkeyManager.isHotkeyPressed ? .green : .secondary)

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

    // MARK: - Sound Section

    private var soundSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Label("Sound", systemImage: "speaker.wave.2")
                    .font(.headline)

                // Microphone picker
                HStack {
                    Text("Microphone")

                    Spacer()

                    Picker("", selection: $audioEngine.selectedDeviceUID) {
                        ForEach(audioEngine.availableDevices) { device in
                            Text(device.name).tag(device.uid)
                        }
                    }
                    .pickerStyle(.menu)
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
                    Text("Mute While Recording")

                    Spacer()

                    Toggle("", isOn: $audioEngine.muteWhileRecording)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }

                Text("Mute system audio during recording to prevent feedback")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
