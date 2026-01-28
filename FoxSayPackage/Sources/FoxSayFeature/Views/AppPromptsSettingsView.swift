import SwiftUI
import UniformTypeIdentifiers

/// App Prompts settings view for assigning default prompts to applications
public struct AppPromptsSettingsView: View {
    @ObservedObject private var appPromptManager = AppPromptManager.shared
    @ObservedObject private var promptManager = PromptManager.shared

    @State private var showAddAppSheet = false
    @State private var dragOver = false

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                Text("App Prompts")
                    .font(.title2)
                    .fontWeight(.bold)
                    .padding(.bottom, 8)

                Text("Assign default prompts to specific applications. When you switch to an app with an assigned prompt, it will automatically activate.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                // App list
                if appPromptManager.assignments.isEmpty {
                    emptyStateView
                } else {
                    GroupBox {
                        VStack(spacing: 0) {
                            ForEach(appPromptManager.assignments) { assignment in
                                appRow(assignment)

                                if assignment.id != appPromptManager.assignments.last?.id {
                                    Divider()
                                }
                            }
                        }
                        .padding(8)
                    }
                }

                // Add app button
                HStack {
                    Button {
                        showAddAppSheet = true
                    } label: {
                        Label("Add Application", systemImage: "plus")
                    }
                    .buttonStyle(.bordered)
                }

                // How it works
                howItWorksSection

                Spacer()
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDrop(of: [.fileURL], isTargeted: $dragOver) { providers in
            handleDrop(providers: providers)
        }
        .sheet(isPresented: $showAddAppSheet) {
            AddAppSheet { bundleId, displayName, iconData in
                appPromptManager.addApp(bundleId: bundleId, displayName: displayName, iconData: iconData)
            }
        }
    }

    private var emptyStateView: some View {
        GroupBox {
            VStack(spacing: 12) {
                Image(systemName: "app.badge")
                    .font(.largeTitle)
                    .foregroundColor(.secondary)

                Text("No Apps Configured")
                    .font(.headline)

                Text("Add applications to assign default prompts. Drag an app from Finder or use the Add button.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(24)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(dragOver ? Color.accentColor : Color.clear, lineWidth: 2)
        )
    }

    private func appRow(_ assignment: AppPromptAssignment) -> some View {
        HStack(spacing: 12) {
            // App icon
            if let icon = assignment.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 32, height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                Image(systemName: "app")
                    .font(.title)
                    .frame(width: 32, height: 32)
                    .foregroundColor(.secondary)
            }

            // App name
            VStack(alignment: .leading, spacing: 2) {
                Text(assignment.displayName)
                    .fontWeight(.medium)
                Text(assignment.bundleId)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            // Prompt picker
            Picker("", selection: Binding(
                get: { assignment.defaultPromptId },
                set: { newId in
                    appPromptManager.assignPrompt(newId, to: assignment)
                }
            )) {
                Text("None").tag(nil as UUID?)
                Divider()
                ForEach(promptManager.prompts) { prompt in
                    Text(prompt.displayName).tag(prompt.id as UUID?)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 150)

            // Delete button
            Button(role: .destructive) {
                appPromptManager.removeApp(assignment)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 8)
    }

    private var howItWorksSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Label("How It Works", systemImage: "info.circle")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 6) {
                    Text("1. Add applications you frequently use for writing or coding")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("2. Assign a default prompt to each app")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("3. When you switch to that app, the prompt automatically activates")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("4. Your transcriptions will be transformed using that prompt")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.leading, 4)

                Text("You can always manually activate a different prompt or turn prompts off with voice commands.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 4)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil),
                  url.pathExtension == "app" else {
                return
            }

            // Get bundle info
            let bundleUrl = url
            if let bundle = Bundle(url: bundleUrl),
               let bundleId = bundle.bundleIdentifier {

                let displayName = FileManager.default.displayName(atPath: bundleUrl.path)

                // Get icon
                var iconData: Data?
                if let icon = NSWorkspace.shared.icon(forFile: bundleUrl.path).tiffRepresentation {
                    iconData = icon
                }

                DispatchQueue.main.async {
                    appPromptManager.addApp(
                        bundleId: bundleId,
                        displayName: displayName,
                        iconData: iconData
                    )
                }
            }
        }

        return true
    }
}

/// Sheet for adding an app
struct AddAppSheet: View {
    let onAdd: (String, String, Data?) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var bundleId = ""
    @State private var displayName = ""
    @State private var runningApps: [NSRunningApplication] = []

    var body: some View {
        VStack(spacing: 20) {
            Text("Add Application")
                .font(.headline)

            // Running apps list
            if !runningApps.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Running Applications")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ScrollView {
                        VStack(spacing: 4) {
                            ForEach(runningApps, id: \.bundleIdentifier) { app in
                                Button {
                                    bundleId = app.bundleIdentifier ?? ""
                                    displayName = app.localizedName ?? ""
                                } label: {
                                    HStack {
                                        if let icon = app.icon {
                                            Image(nsImage: icon)
                                                .resizable()
                                                .frame(width: 20, height: 20)
                                        }
                                        Text(app.localizedName ?? app.bundleIdentifier ?? "Unknown")
                                            .foregroundColor(.primary)
                                        Spacer()
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(bundleId == app.bundleIdentifier ? Color.accentColor.opacity(0.2) : Color.clear)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .frame(maxHeight: 150)
                }
            }

            Divider()

            // Manual entry
            VStack(alignment: .leading, spacing: 8) {
                Text("Or enter manually")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField("Bundle ID (e.g., com.apple.Safari)", text: $bundleId)
                    .textFieldStyle(.roundedBorder)

                TextField("Display Name (e.g., Safari)", text: $displayName)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Add") {
                    var iconData: Data?
                    if let app = runningApps.first(where: { $0.bundleIdentifier == bundleId }),
                       let icon = app.icon {
                        iconData = icon.tiffRepresentation
                    }
                    onAdd(bundleId, displayName, iconData)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(bundleId.isEmpty || displayName.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 400)
        .onAppear {
            loadRunningApps()
        }
    }

    private func loadRunningApps() {
        runningApps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }
}

#Preview {
    AppPromptsSettingsView()
        .frame(width: 500, height: 600)
}
