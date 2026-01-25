import SwiftUI

/// Settings view for VoiceFox
public struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var engineManager = EngineManager.shared
    @ObservedObject private var hotkeyManager = HotkeyManager.shared
    @ObservedObject private var devAppConfig = DevAppConfigManager.shared
    @ObservedObject private var correctionPipeline = CorrectionPipeline.shared
    @ObservedObject private var llmManager = LLMModelManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var showAddAppSheet = false
    @State private var newAppBundleId = ""
    @State private var newAppName = ""

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Header with close button
            HStack {
                Text("Settings")
                    .font(.headline)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.title2)
                }
                .buttonStyle(.plain)
            }
            .padding()

            TabView {
                generalTab
                    .tabItem {
                        Label("General", systemImage: "gear")
                    }

                engineTab
                    .tabItem {
                        Label("Engine", systemImage: "waveform")
                    }

                devAppsTab
                    .tabItem {
                        Label("Dev Apps", systemImage: "terminal")
                    }

                correctionsTab
                    .tabItem {
                        Label("Corrections", systemImage: "text.badge.checkmark")
                    }
            }
        }
        .frame(width: 500, height: 450)
    }

    // MARK: - General Tab

    private var generalTab: some View {
        Form {
            Section("Hotkey") {
                Picker("Hold key to record", selection: $hotkeyManager.selectedModifier) {
                    ForEach(HotkeyManager.HotkeyModifier.allCases) { modifier in
                        Text(modifier.displayName).tag(modifier)
                    }
                }
                .pickerStyle(.menu)

                if !HotkeyManager.checkAccessibilityPermission() {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("Accessibility permission required")
                            .font(.caption)
                        Spacer()
                        Button("Grant") {
                            HotkeyManager.requestAccessibilityPermission()
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }

            Section("Appearance") {
                Toggle("Show in menu bar", isOn: .init(
                    get: { UserDefaults.standard.bool(forKey: "showInMenuBar") },
                    set: { UserDefaults.standard.set($0, forKey: "showInMenuBar") }
                ))
            }

            Section("Audio") {
                HStack {
                    Text("Microphone")
                    Spacer()
                    if AudioEngine.shared.hasPermission {
                        Label("Granted", systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    } else {
                        Button("Request Permission") {
                            Task {
                                await AudioEngine.shared.checkPermission()
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }

            Section("Output") {
                Toggle("Copy to clipboard only", isOn: .init(
                    get: { UserDefaults.standard.bool(forKey: "copyToClipboardOnly") },
                    set: { UserDefaults.standard.set($0, forKey: "copyToClipboardOnly") }
                ))
                Text("When enabled, transcribed text is copied to clipboard instead of pasting into active app")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Engine Tab

    private var engineTab: some View {
        Form {
            Section("Transcription Engine") {
                Picker("Engine", selection: Binding(
                    get: { engineManager.currentEngineType },
                    set: { type in
                        Task {
                            await engineManager.selectEngine(type)
                        }
                    }
                )) {
                    ForEach(EngineType.allCases) { type in
                        VStack(alignment: .leading) {
                            Text(type.displayName)
                            Text(type.description)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .tag(type)
                    }
                }
                .pickerStyle(.radioGroup)
            }

            Section("Model") {
                modelStatusView
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var modelStatusView: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(engineManager.currentEngineType.displayName)
                    .font(.headline)

                if engineManager.isDownloading {
                    ProgressView(value: engineManager.downloadProgress)
                        .progressViewStyle(.linear)
                    Text("Downloading... \(Int(engineManager.downloadProgress * 100))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else if engineManager.isModelReady {
                    Label("Model ready", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }

            Spacer()

            if engineManager.isDownloading {
                Button("Cancel") {
                    engineManager.cancelDownload()
                }
                .buttonStyle(.bordered)
            } else if !engineManager.isModelReady {
                Button("Download Model") {
                    Task {
                        try? await engineManager.downloadCurrentModel()
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }

        if let error = engineManager.downloadError {
            Text(error)
                .font(.caption)
                .foregroundColor(.red)
        }
    }

    // MARK: - Dev Apps Tab

    private var devAppsTab: some View {
        Form {
            Section("Developer Applications") {
                Text("Transcriptions in these apps will be corrected for developer terminology.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                ForEach(devAppConfig.apps) { app in
                    HStack {
                        Toggle(app.displayName, isOn: .init(
                            get: { app.isEnabled },
                            set: { enabled in
                                devAppConfig.setEnabled(enabled, for: app.bundleId)
                            }
                        ))

                        Spacer()

                        Button(role: .destructive) {
                            devAppConfig.removeApp(bundleId: app.bundleId)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }

            Section {
                Button("Add Application...") {
                    showAddAppSheet = true
                }

                Button("Reset to Defaults") {
                    devAppConfig.resetToDefaults()
                }
                .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showAddAppSheet) {
            addAppSheet
        }
    }

    private var addAppSheet: some View {
        VStack(spacing: 16) {
            Text("Add Developer Application")
                .font(.headline)

            Form {
                TextField("Bundle ID", text: $newAppBundleId)
                    .textFieldStyle(.roundedBorder)

                TextField("Display Name", text: $newAppName)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Button("Cancel") {
                    showAddAppSheet = false
                    newAppBundleId = ""
                    newAppName = ""
                }
                .buttonStyle(.bordered)

                Button("Add") {
                    let config = DevAppConfig(
                        bundleId: newAppBundleId,
                        displayName: newAppName
                    )
                    devAppConfig.addApp(config)
                    showAddAppSheet = false
                    newAppBundleId = ""
                    newAppName = ""
                }
                .buttonStyle(.borderedProminent)
                .disabled(newAppBundleId.isEmpty || newAppName.isEmpty)
            }
        }
        .padding()
        .frame(width: 350)
    }

    // MARK: - Corrections Tab

    private var correctionsTab: some View {
        Form {
            Section("Correction Settings") {
                Toggle("Enable dev corrections", isOn: $correctionPipeline.devCorrectionEnabled)

                Toggle("Use LLM for corrections", isOn: $correctionPipeline.llmCorrectionEnabled)
                    .disabled(!llmManager.isModelReady)

                if correctionPipeline.llmCorrectionEnabled && llmManager.isModelReady {
                    Toggle("Always apply LLM", isOn: $correctionPipeline.llmAlwaysApply)

                    Text(correctionPipeline.llmAlwaysApply
                         ? "LLM processes all transcriptions in dev apps"
                         : "LLM only processes text with detected code patterns")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Section("LLM Model") {
                llmModelStatusView
            }

            Section("LLM Prompt") {
                llmPromptEditorView
            }

            Section("Preview") {
                Text("Sample corrections:")
                    .font(.caption)
                    .foregroundColor(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    correctionExample("git status dash dash short", "git status --short")
                    correctionExample("dot js", ".js")
                    correctionExample("equals equals", "==")
                    correctionExample("open paren close paren", "()")
                }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var llmModelStatusView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Qwen2.5 Coder 1.5B")
                    .font(.headline)

                Text("\(LLMModelManager.modelSizeMB) MB - 4-bit quantized")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if llmManager.isDownloading {
                    ProgressView(value: llmManager.downloadProgress)
                        .progressViewStyle(.linear)
                    Text("Downloading... \(Int(llmManager.downloadProgress * 100))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else if llmManager.isPreloading {
                    HStack(spacing: 4) {
                        ProgressView()
                            .scaleEffect(0.6)
                        Text("Loading model...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else if llmManager.isModelReady {
                    Label("Model ready", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }

            Spacer()

            if llmManager.isDownloading {
                Button("Cancel") {
                    llmManager.cancelDownload()
                }
                .buttonStyle(.bordered)
            } else if !llmManager.isModelReady {
                Button("Download") {
                    Task {
                        try? await llmManager.downloadModel()
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }

        if let error = llmManager.downloadError {
            Text(error)
                .font(.caption)
                .foregroundColor(.red)
        }
    }

    @ViewBuilder
    private var llmPromptEditorView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("System Prompt")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Spacer()

                if llmManager.isUsingCustomPrompt {
                    Button("Reset to Default") {
                        llmManager.resetPromptToDefault()
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                }
            }

            Text("Use {input} as placeholder for the transcribed text")
                .font(.caption)
                .foregroundColor(.secondary)

            TextEditor(text: $llmManager.customPrompt)
                .font(.system(.caption, design: .monospaced))
                .frame(minHeight: 120, maxHeight: 200)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )

            if llmManager.isUsingCustomPrompt {
                Label("Using custom prompt", systemImage: "pencil.circle.fill")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
    }

    private func correctionExample(_ input: String, _ output: String) -> some View {
        HStack {
            Text(input)
                .foregroundColor(.secondary)
            Image(systemName: "arrow.right")
                .foregroundColor(.blue)
            Text(output)
                .fontWeight(.medium)
        }
        .font(.caption)
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppState.shared)
}
