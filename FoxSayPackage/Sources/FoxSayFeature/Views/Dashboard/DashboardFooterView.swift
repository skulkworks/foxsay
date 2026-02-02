import SwiftUI

/// Footer component showing last session info and hotkey reminder
struct DashboardFooterView: View {
    @ObservedObject private var historyManager = HistoryManager.shared
    @ObservedObject private var hotkeyManager = HotkeyManager.shared

    /// Whether auto-paste is enabled (reads from UserDefaults)
    private var autoPasteEnabled: Bool {
        UserDefaults.standard.object(forKey: "pasteToActiveApp") as? Bool ?? true
    }

    var body: some View {
        HStack {
            // Left side: Last session info and auto-paste status
            VStack(alignment: .leading, spacing: 4) {
                if let lastSession = historyManager.items.first {
                    Text("Last session: \(lastSession.formattedTimestamp)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 4) {
                    Circle()
                        .fill(autoPasteEnabled ? Color.dashboardGreen : Color.secondary.opacity(0.5))
                        .frame(width: 6, height: 6)

                    Text(autoPasteEnabled ? "Auto-paste enabled" : "Auto-paste disabled")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Right side: Keyboard hint
            hotkeyHint
        }
    }

    // MARK: - Hotkey Hint

    private var hotkeyHint: some View {
        HStack(spacing: 4) {
            Text("Hold")
                .font(.caption)
                .foregroundStyle(.secondary)

            // Styled key cap
            Text(hotkeyManager.selectedModifier.symbol)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.primary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color(.textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.primary.opacity(0.15), lineWidth: 0.5)
                )

            if !hotkeyManager.selectedModifier.side.isEmpty {
                Text(hotkeyManager.selectedModifier.side)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("to record")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    DashboardFooterView()
        .padding()
        .frame(width: 500)
}
