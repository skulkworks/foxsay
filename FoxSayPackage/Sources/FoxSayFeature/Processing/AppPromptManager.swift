import Foundation
import AppKit
import os.log

private let appPromptLog = OSLog(subsystem: "com.foxsay", category: "APP-PROMPT")

/// Manages default prompt assignments for applications
@MainActor
public class AppPromptManager: ObservableObject {
    public static let shared = AppPromptManager()

    // MARK: - UserDefaults Keys

    private static let assignmentsKey = "appPromptAssignments"

    // MARK: - Published Properties

    /// App-to-prompt assignments
    @Published public private(set) var assignments: [AppPromptAssignment] = []

    // MARK: - Initialization

    private init() {
        loadAssignments()
    }

    // MARK: - Assignment Management

    /// Add an app with optional default prompt
    public func addApp(bundleId: String, displayName: String, iconData: Data? = nil, promptId: UUID? = nil) {
        guard !assignments.contains(where: { $0.bundleId == bundleId }) else { return }

        let assignment = AppPromptAssignment(
            bundleId: bundleId,
            displayName: displayName,
            iconData: iconData,
            defaultPromptId: promptId
        )

        assignments.append(assignment)
        saveAssignments()

        os_log(.info, log: appPromptLog, "Added app: %{public}@", displayName)
    }

    /// Add an app from a running application
    public func addApp(from app: NSRunningApplication, promptId: UUID? = nil) {
        guard let bundleId = app.bundleIdentifier else { return }
        guard !assignments.contains(where: { $0.bundleId == bundleId }) else { return }

        var iconData: Data?
        if let icon = app.icon {
            iconData = icon.tiffRepresentation
        }

        addApp(
            bundleId: bundleId,
            displayName: app.localizedName ?? bundleId,
            iconData: iconData,
            promptId: promptId
        )
    }

    /// Remove an app assignment
    public func removeApp(_ assignment: AppPromptAssignment) {
        assignments.removeAll { $0.id == assignment.id }
        saveAssignments()

        os_log(.info, log: appPromptLog, "Removed app: %{public}@", assignment.displayName)
    }

    /// Assign a prompt to an app
    public func assignPrompt(_ promptId: UUID?, to assignment: AppPromptAssignment) {
        guard let index = assignments.firstIndex(where: { $0.id == assignment.id }) else { return }

        assignments[index].defaultPromptId = promptId
        saveAssignments()

        os_log(.info, log: appPromptLog, "Assigned prompt %{public}@ to app %{public}@",
               promptId?.uuidString ?? "none", assignment.displayName)
    }

    /// Get the default prompt for a bundle ID
    public func getDefaultPrompt(forBundleId bundleId: String) -> Prompt? {
        guard let assignment = assignments.first(where: { $0.bundleId == bundleId }),
              let promptId = assignment.defaultPromptId else {
            return nil
        }

        return PromptManager.shared.prompts.first { $0.id == promptId }
    }

    /// Get the assignment for a bundle ID
    public func getAssignment(forBundleId bundleId: String) -> AppPromptAssignment? {
        assignments.first { $0.bundleId == bundleId }
    }

    /// Check if an app has a prompt assigned
    public func hasPromptAssigned(bundleId: String) -> Bool {
        guard let assignment = assignments.first(where: { $0.bundleId == bundleId }) else {
            return false
        }
        return assignment.defaultPromptId != nil
    }

    /// Update app icon data (e.g., when app is running)
    public func updateIconData(for bundleId: String, iconData: Data?) {
        guard let index = assignments.firstIndex(where: { $0.bundleId == bundleId }) else { return }

        // Only update if we don't have icon data yet
        if assignments[index].iconData == nil && iconData != nil {
            assignments[index].iconData = iconData
            saveAssignments()
        }
    }

    // MARK: - Persistence

    private func loadAssignments() {
        if let data = UserDefaults.standard.data(forKey: Self.assignmentsKey),
           let loaded = try? JSONDecoder().decode([AppPromptAssignment].self, from: data) {
            assignments = loaded
        }
    }

    private func saveAssignments() {
        if let data = try? JSONEncoder().encode(assignments) {
            UserDefaults.standard.set(data, forKey: Self.assignmentsKey)
        }
    }
}
