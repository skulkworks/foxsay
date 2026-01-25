import SwiftUI

/// Corrections settings view for LLM configuration
public struct CorrectionsSettingsView: View {
    @ObservedObject private var correctionPipeline = CorrectionPipeline.shared
    @ObservedObject private var llmManager = LLMModelManager.shared

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                Text("Corrections")
                    .font(.title2)
                    .fontWeight(.bold)
                    .padding(.bottom, 8)

                Text("Configure how VoiceFox processes transcribed text for developer apps.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                // Correction Settings
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Settings", systemImage: "slider.horizontal.3")
                            .font(.headline)

                        HStack {
                            Text("Enable dev corrections")
                            Spacer()
                            Toggle("", isOn: $correctionPipeline.devCorrectionEnabled)
                                .labelsHidden()
                                .toggleStyle(.switch)
                        }

                        HStack {
                            Text("Use LLM for corrections")
                            Spacer()
                            Toggle("", isOn: $correctionPipeline.llmCorrectionEnabled)
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .disabled(!llmManager.isModelReady)
                        }

                        if correctionPipeline.llmCorrectionEnabled && llmManager.isModelReady {
                            HStack {
                                Text("Always apply LLM")
                                Spacer()
                                Toggle("", isOn: $correctionPipeline.llmAlwaysApply)
                                    .labelsHidden()
                                    .toggleStyle(.switch)
                            }
                            .padding(.leading, 20)

                            Text(correctionPipeline.llmAlwaysApply
                                 ? "LLM processes all transcriptions in dev apps"
                                 : "LLM only processes text with detected code patterns")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.leading, 20)
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // LLM Model
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("LLM Model", systemImage: "cpu")
                            .font(.headline)

                        llmModelStatusView
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // LLM Prompt
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label("System Prompt", systemImage: "text.bubble")
                                .font(.headline)

                            Spacer()

                            if llmManager.isUsingCustomPrompt {
                                Button("Reset to Default") {
                                    llmManager.resetPromptToDefault()
                                }
                                .font(.caption)
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }

                        Text("Use {input} as placeholder for the transcribed text")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        TextEditor(text: $llmManager.customPrompt)
                            .font(.system(.caption, design: .monospaced))
                            .frame(minHeight: 100, maxHeight: 150)
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
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Preview
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Sample Corrections", systemImage: "text.magnifyingglass")
                            .font(.headline)

                        VStack(alignment: .leading, spacing: 6) {
                            correctionExample("git status dash dash short", "git status --short")
                            correctionExample("dot js", ".js")
                            correctionExample("equals equals", "==")
                            correctionExample("open paren close paren", "()")
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Spacer()
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var llmModelStatusView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Qwen2.5 Coder 1.5B")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text("\(LLMModelManager.modelSizeMB) MB - 4-bit quantized")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if llmManager.isDownloading {
                    ProgressView(value: llmManager.downloadProgress)
                        .progressViewStyle(.linear)
                        .padding(.top, 4)
                    Text("Downloading... \(Int(llmManager.downloadProgress * 100))%")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else if llmManager.isPreloading {
                    HStack(spacing: 4) {
                        ProgressView()
                            .scaleEffect(0.6)
                        Text("Loading model...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
                .controlSize(.small)
            } else if !llmManager.isModelReady {
                Button("Download") {
                    Task {
                        try? await llmManager.downloadModel()
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }

        if let error = llmManager.downloadError {
            Text(error)
                .font(.caption)
                .foregroundColor(.red)
        }
    }

    private func correctionExample(_ input: String, _ output: String) -> some View {
        HStack {
            Text(input)
                .foregroundColor(.secondary)
                .font(.caption)
            Image(systemName: "arrow.right")
                .foregroundColor(.blue)
                .font(.caption)
            Text(output)
                .fontWeight(.medium)
                .font(.system(.caption, design: .monospaced))
        }
    }
}

#Preview {
    CorrectionsSettingsView()
        .frame(width: 450, height: 600)
}
