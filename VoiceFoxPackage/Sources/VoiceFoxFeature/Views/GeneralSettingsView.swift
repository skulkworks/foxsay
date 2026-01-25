import SwiftUI

/// General settings view
public struct GeneralSettingsView: View {
    @ObservedObject private var hotkeyManager = HotkeyManager.shared
    @ObservedObject private var audioEngine = AudioEngine.shared

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                Text("General")
                    .font(.title2)
                    .fontWeight(.bold)
                    .padding(.bottom, 8)

                // Hotkey Section
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Hotkey", systemImage: "keyboard")
                            .font(.headline)

                        Picker("Hold key to record", selection: $hotkeyManager.selectedModifier) {
                            ForEach(HotkeyManager.HotkeyModifier.allCases) { modifier in
                                Text(modifier.displayName).tag(modifier)
                            }
                        }
                        .pickerStyle(.menu)

                        if !HotkeyManager.checkAccessibilityPermission() {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                Text("Accessibility permission required for hotkey")
                                    .font(.caption)
                                Spacer()
                                Button("Grant") {
                                    HotkeyManager.requestAccessibilityPermission()
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                            .padding(8)
                            .background(Color.orange.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    .padding(4)
                }

                // Audio Section
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Microphone", systemImage: "mic")
                            .font(.headline)

                        HStack {
                            Text("Permission")
                            Spacer()
                            if audioEngine.hasPermission {
                                Label("Granted", systemImage: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                            } else {
                                Button("Request Permission") {
                                    Task {
                                        await audioEngine.checkPermission()
                                    }
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                    }
                    .padding(4)
                }

                // Output Section
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Output", systemImage: "doc.on.clipboard")
                            .font(.headline)

                        Toggle("Copy to clipboard only", isOn: .init(
                            get: { UserDefaults.standard.bool(forKey: "copyToClipboardOnly") },
                            set: { UserDefaults.standard.set($0, forKey: "copyToClipboardOnly") }
                        ))

                        Text("When enabled, transcribed text is copied to clipboard instead of being pasted into the active app")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(4)
                }

                // Appearance Section
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Appearance", systemImage: "paintbrush")
                            .font(.headline)

                        Toggle("Show in menu bar", isOn: .init(
                            get: { UserDefaults.standard.bool(forKey: "showInMenuBar") },
                            set: { UserDefaults.standard.set($0, forKey: "showInMenuBar") }
                        ))
                    }
                    .padding(4)
                }

                Spacer()
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    GeneralSettingsView()
        .frame(width: 450, height: 500)
}
