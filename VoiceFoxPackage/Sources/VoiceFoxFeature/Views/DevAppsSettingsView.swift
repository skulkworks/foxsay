import SwiftUI

/// Dev Apps settings view
public struct DevAppsSettingsView: View {
    @ObservedObject private var devAppConfig = DevAppConfigManager.shared

    @State private var showAddAppSheet = false
    @State private var newAppBundleId = ""
    @State private var newAppName = ""

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                Text("Developer Apps")
                    .font(.title2)
                    .fontWeight(.bold)
                    .padding(.bottom, 8)

                Text("Transcriptions in these apps will be processed for developer terminology, converting spoken programming terms to their written form.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                // App List
                GroupBox {
                    VStack(spacing: 0) {
                        ForEach(devAppConfig.apps) { app in
                            HStack {
                                Text(app.displayName)

                                Spacer()

                                Toggle("", isOn: .init(
                                    get: { app.isEnabled },
                                    set: { enabled in
                                        devAppConfig.setEnabled(enabled, for: app.bundleId)
                                    }
                                ))
                                .labelsHidden()
                                .toggleStyle(.switch)

                                Button(role: .destructive) {
                                    devAppConfig.removeApp(bundleId: app.bundleId)
                                } label: {
                                    Image(systemName: "trash")
                                        .foregroundColor(.red)
                                }
                                .buttonStyle(.borderless)
                            }
                            .padding(.vertical, 8)

                            if app.id != devAppConfig.apps.last?.id {
                                Divider()
                            }
                        }

                        if devAppConfig.apps.isEmpty {
                            Text("No developer apps configured")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding()
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Actions
                HStack {
                    Button {
                        showAddAppSheet = true
                    } label: {
                        Label("Add Application", systemImage: "plus")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        devAppConfig.resetToDefaults()
                    } label: {
                        Label("Reset to Defaults", systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(.bordered)
                    .foregroundColor(.secondary)
                }

                // Info
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("How it works", systemImage: "info.circle")
                            .font(.headline)

                        Text("When you dictate in a developer app, VoiceFox will convert spoken programming terms:")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        VStack(alignment: .leading, spacing: 4) {
                            correctionExample("dash dash", "--")
                            correctionExample("equals equals", "==")
                            correctionExample("open paren close paren", "()")
                            correctionExample("dot js", ".js")
                        }
                        .padding(.top, 4)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Spacer()
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showAddAppSheet) {
            addAppSheet
        }
    }

    private var addAppSheet: some View {
        VStack(spacing: 20) {
            Text("Add Developer Application")
                .font(.headline)

            VStack(alignment: .leading, spacing: 12) {
                TextField("Bundle ID (e.g., com.apple.dt.Xcode)", text: $newAppBundleId)
                    .textFieldStyle(.roundedBorder)

                TextField("Display Name (e.g., Xcode)", text: $newAppName)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Button("Cancel") {
                    showAddAppSheet = false
                    newAppBundleId = ""
                    newAppName = ""
                }
                .buttonStyle(.bordered)

                Spacer()

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
        .padding(24)
        .frame(width: 400)
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
    DevAppsSettingsView()
        .frame(width: 450, height: 500)
}
