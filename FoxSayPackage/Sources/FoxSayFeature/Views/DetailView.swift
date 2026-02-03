import SwiftUI

/// Detail view that shows content based on sidebar selection
public struct DetailView: View {
    @EnvironmentObject private var appState: AppState

    public init() {}

    public var body: some View {
        contentView
            .id(appState.selectedSidebarItem)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var contentView: some View {
        switch appState.selectedSidebarItem {
        case .status:
            DashboardView()
        case .general:
            GeneralSettingsView()
        case .models:
            ModelsSettingsView()
        case .aiModels:
            AIModelsSettingsView()
        case .prompts:
            PromptsSettingsView()
        case .applications:
            AppPromptsSettingsView()
        case .dictionary:
            DictionarySettingsView()
        case .history:
            HistoryView()
        case .experimental:
            ExperimentalSettingsView()
        }
    }
}

#Preview {
    DetailView()
        .environmentObject(AppState.shared)
}
