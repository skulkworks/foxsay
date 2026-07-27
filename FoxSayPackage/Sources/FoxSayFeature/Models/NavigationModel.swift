import Foundation

/// Sidebar navigation items
public enum SidebarItem: String, CaseIterable, Identifiable {
    case status = "Dashboard"
    case general = "General"
    case models = "Speech Models"
    case aiModels = "AI Models"
    case prompts = "Prompts"
    case applications = "Applications"
    case dictionary = "Dictionary"
    case history = "History"
    case experimental = "Text Transforms"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .status: return "square.grid.2x2"
        case .general: return "gear"
        case .models: return "cpu"
        case .aiModels: return "brain"
        case .prompts: return "text.bubble"
        case .applications: return "app.badge"
        case .dictionary: return "character.book.closed"
        case .history: return "clock"
        case .experimental: return "flask"
        }
    }

    public var title: String {
        rawValue
    }
}
