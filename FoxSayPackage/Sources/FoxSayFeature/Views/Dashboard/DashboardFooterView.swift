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
        HStack(alignment: .center) {
            // Left side: Last session info and auto-paste status
            VStack(alignment: .leading, spacing: 4) {
                if let lastSession = historyManager.items.first {
                    Text("Last session: \(lastSession.formattedTimestamp)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                HStack(spacing: 5) {
                    StatusDot(color: autoPasteEnabled ? .statusOK : Color.primary.opacity(0.2))

                    Text(autoPasteEnabled ? "Auto-paste enabled" : "Auto-paste disabled")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            // Right side: Keyboard hint
            hotkeyHint
        }
    }

    // MARK: - Hotkey Hint

    private var hotkeyHint: some View {
        HStack(spacing: 5) {
            Text("Hold")
                .font(.caption)
                .foregroundStyle(.tertiary)

            if !hotkeyManager.selectedModifier.side.isEmpty {
                Text(hotkeyManager.selectedModifier.side)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            KeycapLabel(text: hotkeyManager.selectedModifier.symbol)

            Text("to record")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }
}

#Preview {
    DashboardFooterView()
        .padding()
        .frame(width: 500)
}
