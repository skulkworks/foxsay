import SwiftUI

/// Sidebar navigation view
public struct SidebarView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var modelManager = ModelManager.shared
    @ObservedObject private var audioEngine = AudioEngine.shared

    public init() {}

    public var body: some View {
        List(selection: $appState.selectedSidebarItem) {
            Section {
                ForEach([SidebarItem.status]) { item in
                    sidebarRow(item)
                }
            }

            Section("Settings") {
                ForEach([SidebarItem.general, .models, .devApps, .corrections]) { item in
                    sidebarRow(item)
                }
            }

            Section("Data") {
                ForEach([SidebarItem.history]) { item in
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
        switch item {
        case .status:
            if appState.isRecording {
                return .red
            } else if appState.isTranscribing {
                return .orange
            }
            return .accentColor
        case .models:
            return modelManager.isModelLoaded ? .green : .orange
        default:
            return .secondary
        }
    }

    private var statusFooter: some View {
        HStack(spacing: 8) {
            // Mic status
            statusDot(
                isActive: audioEngine.hasPermission,
                activeColor: .green,
                inactiveColor: .orange,
                icon: audioEngine.hasPermission ? "mic.fill" : "mic.slash"
            )

            // Accessibility status
            statusDot(
                isActive: HotkeyManager.checkAccessibilityPermission(),
                activeColor: .green,
                inactiveColor: .orange,
                icon: HotkeyManager.checkAccessibilityPermission() ? "hand.raised.fill" : "hand.raised.slash"
            )

            // Model status
            modelStatusDot

            Spacer()

            // Version
            Text("v1.0")
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
            statusDot(isActive: true, activeColor: .green, inactiveColor: .green, icon: "checkmark.circle.fill")
        } else if modelManager.isPreloading {
            SpinningStatusDot(icon: "arrow.trianglehead.2.clockwise.rotate.90", color: .blue)
        } else if modelManager.isModelReady {
            statusDot(isActive: false, activeColor: .green, inactiveColor: .blue, icon: "hourglass")
        } else {
            statusDot(isActive: false, activeColor: .green, inactiveColor: .orange, icon: "arrow.down.circle")
        }
    }
}

/// Spinning status dot for loading states
private struct SpinningStatusDot: View {
    let icon: String
    let color: Color
    @State private var rotation: Double = 0

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(color)
            .rotationEffect(.degrees(rotation))
            .frame(width: 20, height: 20)
            .background(color.opacity(0.15))
            .clipShape(Circle())
            .onAppear {
                withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            }
    }
}

#Preview {
    SidebarView()
        .environmentObject(AppState.shared)
        .frame(width: 200, height: 400)
}
