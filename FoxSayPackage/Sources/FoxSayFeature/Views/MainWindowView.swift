import SwiftUI

/// Main window view with sidebar navigation
public struct MainWindowView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var modelManager = ModelManager.shared

    @State private var isSidebarVisible = true
    private let sidebarWidth: CGFloat = 200

    public init() {}

    public var body: some View {
        HStack(spacing: 0) {
            // Sidebar with animated width
            SidebarView()
                .frame(width: sidebarWidth)
                .frame(width: isSidebarVisible ? sidebarWidth : 0, alignment: .leading)
                .clipped()

            // Divider only when sidebar visible
            if isSidebarVisible {
                Divider()
            }

            // Detail pane
            DetailView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 600, minHeight: 600)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isSidebarVisible.toggle()
                    }
                } label: {
                    Image(systemName: "sidebar.leading")
                }
                .help("Toggle Sidebar")
            }
        }
    }
}

#Preview {
    MainWindowView()
        .environmentObject(AppState.shared)
}
