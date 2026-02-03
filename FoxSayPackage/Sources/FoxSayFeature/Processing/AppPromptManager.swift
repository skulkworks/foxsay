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
    public func addApp(bundleId: String, displayName: String, promptId: UUID? = nil) {
        guard !assignments.contains(where: { $0.bundleId == bundleId }) else { return }

        let assignment = AppPromptAssignment(
            bundleId: bundleId,
            displayName: displayName,
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

        addApp(
            bundleId: bundleId,
            displayName: app.localizedName ?? bundleId,
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

    /// Assign a model to an app
    public func assignModel(_ modelRef: ModelReference?, to assignment: AppPromptAssignment) {
        guard let index = assignments.firstIndex(where: { $0.id == assignment.id }) else { return }

        assignments[index].defaultModelRef = modelRef
        saveAssignments()

        let modelName: String
        if let ref = modelRef {
            modelName = ref.displayName
        } else {
            modelName = "default"
        }

        os_log(.info, log: appPromptLog, "Assigned model %{public}@ to app %{public}@",
               modelName, assignment.displayName)
    }

    /// Get the model reference for a bundle ID
    public func getModelReference(forBundleId bundleId: String) -> ModelReference? {
        guard let assignment = assignments.first(where: { $0.bundleId == bundleId }),
              let modelRef = assignment.defaultModelRef else {
            return nil
        }

        // Verify the model is still available
        if modelRef.isAvailable {
            return modelRef
        }

        // Model no longer available, return nil to use default
        os_log(.info, log: appPromptLog, "Assigned model for %{public}@ is no longer available, using default",
               bundleId)
        return nil
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
