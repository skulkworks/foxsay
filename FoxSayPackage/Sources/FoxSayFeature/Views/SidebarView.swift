import SwiftUI

/// Sidebar navigation view
public struct SidebarView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var modelManager = ModelManager.shared
    @ObservedObject private var aiModelManager = AIModelManager.shared
    @ObservedObject private var audioEngine = AudioEngine.shared
    @ObservedObject private var providerManager = LLMProviderManager.shared

    @State private var selection: SidebarItem = .status

    public init() {}

    public var body: some View {
        List(selection: $selection) {
            Section {
                ForEach([SidebarItem.status]) { item in
                    sidebarRow(item)
                }
            }

            Section("Settings") {
                ForEach([SidebarItem.general, .models, .aiModels, .prompts, .applications, .dictionary]) { item in
                    sidebarRow(item)
                }
            }

            Section("Data") {
                ForEach([SidebarItem.history]) { item in
                    sidebarRow(item)
                }
            }

            Section("Experimental") {
                ForEach([SidebarItem.experimental]) { item in
                    sidebarRow(item)
                }
            }

            Section {
                ForEach([SidebarItem.ourApps, .about]) { item in
                    sidebarRow(item)
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            statusFooter
                .padding(.bottom, 8)
        }
        .onAppear {
            selection = appState.selectedSidebarItem
        }
        .onChange(of: selection) { _, newValue in
            DispatchQueue.main.async {
                appState.selectedSidebarItem = newValue
            }
        }
        .onChange(of: appState.selectedSidebarItem) { _, newValue in
            if selection != newValue {
                selection = newValue
            }
        }
    }

    private func sidebarRow(_ item: SidebarItem) -> some View {
        Label {
            Text(item.title)
        } icon: {
            Image(systemName: item.icon)
                .foregroundStyle(.secondary)
        }
        .tag(item)
    }

    // MARK: - Status Footer

    @State private var isHoveringStatus = false

    /// The footer reports problems ("Permissions needed") but the controls that fix
    /// them are in the dashboard's System Status card, so the status itself is a
    /// link there. Only the dot and text are clickable — the version is not a link.
    private var statusFooter: some View {
        VStack(spacing: 0) {
            Divider()

            HStack(spacing: 6) {
                Button {
                    appState.showDashboard(scrollingTo: .systemStatus)
                } label: {
                    HStack(spacing: 6) {
                        if isLoading {
                            ProgressView()
                                .controlSize(.small)
                                .scaleEffect(0.65)
                                .frame(width: 12, height: 12)
                        } else {
                            StatusDot(color: statusColor)
                        }

                        Text(statusText)
                            .font(.caption)
                            .foregroundStyle(isHoveringStatus ? Color.primary : Color.secondary)
                            .lineLimit(1)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Show System Status on the dashboard")
                .onHover { hovering in
                    withAnimation(.easeOut(duration: 0.18)) {
                        isHoveringStatus = hovering
                    }
                }

                Spacer(minLength: 4)

                Text("v\(appVersion)")
                    .font(.caption2)
                    .foregroundStyle(.quaternary)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
        }
    }

    private var isLoading: Bool {
        modelManager.isPreloading || aiModelManager.isPreloading
    }

    private var permissionsGranted: Bool {
        audioEngine.hasPermission && HotkeyManager.checkAccessibilityPermission()
    }

    private var speechModelAvailable: Bool {
        modelManager.isModelLoaded || modelManager.isModelReady
    }

    private var aiModelAvailable: Bool {
        (providerManager.providerType == .remote && providerManager.isRemoteReady)
            || aiModelManager.isModelLoaded
            || aiModelManager.isModelReady
            || aiModelManager.selectedModelId == nil  // No AI model configured is a valid setup
    }

    private var statusColor: Color {
        permissionsGranted && speechModelAvailable && aiModelAvailable ? .statusOK : .statusWarning
    }

    private var statusText: String {
        if isLoading {
            return "Loading model…"
        } else if !permissionsGranted {
            return "Permissions needed"
        } else if !speechModelAvailable {
            return "Speech model needed"
        } else if !aiModelAvailable {
            return "AI model needed"
        } else {
            return "Ready"
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
}

#Preview {
    SidebarView()
        .environmentObject(AppState.shared)
        .frame(width: 200, height: 400)
}
