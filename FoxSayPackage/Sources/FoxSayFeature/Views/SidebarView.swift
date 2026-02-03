import SwiftUI

/// Sidebar navigation view
public struct SidebarView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var modelManager = ModelManager.shared
    @ObservedObject private var aiModelManager = AIModelManager.shared
    @ObservedObject private var audioEngine = AudioEngine.shared

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
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            statusFooter
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
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
                .foregroundStyle(iconColor(for: item))
        }
        .tag(item)
    }

    private func iconColor(for item: SidebarItem) -> Color {
        .secondary
    }

    private var statusFooter: some View {
        HStack(spacing: 8) {
            // Mic status
            statusDot(
                isActive: audioEngine.hasPermission,
                activeColor: .accentColor,
                inactiveColor: .secondary,
                icon: audioEngine.hasPermission ? "mic.fill" : "mic.slash"
            )

            // Auto-paste status (Accessibility permission)
            statusDot(
                isActive: HotkeyManager.checkAccessibilityPermission(),
                activeColor: .accentColor,
                inactiveColor: .secondary,
                icon: HotkeyManager.checkAccessibilityPermission() ? "doc.on.clipboard.fill" : "doc.on.clipboard"
            )

            // Transcription model status
            modelStatusDot

            // AI model status
            aiModelStatusDot

            Spacer()

            // Version
            Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(8)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func statusDot(isActive: Bool, activeColor: Color, inactiveColor: Color, icon: String) -> some View {
        Image(systemName: icon)
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(isActive ? activeColor : inactiveColor)
            .frame(width: 20, height: 20)
            .background((isActive ? activeColor : inactiveColor).opacity(0.15))
            .clipShape(Circle())
    }

    @ViewBuilder
    private var modelStatusDot: some View {
        if modelManager.isModelLoaded {
            statusDot(isActive: true, activeColor: .accentColor, inactiveColor: .accentColor, icon: "checkmark.circle.fill")
        } else if modelManager.isPreloading {
            SpinningStatusDot(icon: "arrow.trianglehead.2.clockwise.rotate.90", color: .secondary)
        } else if modelManager.isModelReady {
            statusDot(isActive: false, activeColor: .accentColor, inactiveColor: .secondary, icon: "hourglass")
        } else {
            statusDot(isActive: false, activeColor: .accentColor, inactiveColor: .secondary, icon: "arrow.down.circle")
        }
    }

    @ViewBuilder
    private var aiModelStatusDot: some View {
        if aiModelManager.isModelLoaded {
            statusDot(isActive: true, activeColor: .accentColor, inactiveColor: .accentColor, icon: "brain")
        } else if aiModelManager.isPreloading {
            // Use rotating arrow icon during loading (brain is too symmetric to show rotation)
            SpinningStatusDot(icon: "arrow.trianglehead.2.clockwise.rotate.90", color: .secondary)
        } else if aiModelManager.isModelReady {
            statusDot(isActive: false, activeColor: .accentColor, inactiveColor: .secondary, icon: "brain")
        } else {
            // No AI model selected/downloaded - gray
            statusDot(isActive: false, activeColor: .accentColor, inactiveColor: .secondary, icon: "brain")
        }
    }
}

/// Spinning status dot for loading states
private struct SpinningStatusDot: View {
    let icon: String
    let color: Color

    var body: some View {
        TimelineView(.animation) { timeline in
            let rotation = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.0) * 360

            Image(systemName: icon)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(color)
                .rotationEffect(.degrees(rotation))
                .frame(width: 20, height: 20)
                .background(color.opacity(0.15))
                .clipShape(Circle())
        }
    }
}

#Preview {
    SidebarView()
        .environmentObject(AppState.shared)
        .frame(width: 200, height: 400)
}
