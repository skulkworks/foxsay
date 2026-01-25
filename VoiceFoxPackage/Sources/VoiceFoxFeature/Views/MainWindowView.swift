import SwiftUI

/// Main window view with sidebar navigation
public struct MainWindowView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var modelManager = ModelManager.shared

    public init() {}

    public var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 220)
        } detail: {
            DetailView()
        }
        .frame(minWidth: 600, minHeight: 450)
    }
}

#Preview {
    MainWindowView()
        .environmentObject(AppState.shared)
}
