import SwiftUI

/// Detail view that shows content based on sidebar selection
public struct DetailView: View {
    @EnvironmentObject private var appState: AppState

    public init() {}

    public var body: some View {
        Group {
            switch appState.selectedSidebarItem {
            case .status:
                StatusPaneView()
            case .general:
                GeneralSettingsView()
            case .models:
                ModelsSettingsView()
            case .devApps:
                DevAppsSettingsView()
            case .corrections:
                CorrectionsSettingsView()
            case .history:
                HistoryView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    DetailView()
        .environmentObject(AppState.shared)
}
