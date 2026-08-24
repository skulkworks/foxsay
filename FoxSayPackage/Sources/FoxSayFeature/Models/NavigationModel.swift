import Foundation

/// A dashboard section that can be jumped to from elsewhere in the app.
///
/// The sidebar's status footer reports permission and model problems, but the
/// controls for fixing them live in the dashboard's System Status card, so the
/// footer needs a way to say "show me that" rather than only "open Dashboard".
public enum DashboardSection: String, Identifiable, Hashable {
    case systemStatus

    public var id: String { rawValue }
}

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
    case ourApps = "Our Apps"
    case about = "About"

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
        // Dashboard already owns the 2x2 grid, so the app list takes the 3x3.
        case .ourApps: return "square.grid.3x3"
        case .about: return "info.circle"
        }
    }

    public var title: String {
        rawValue
    }
}
