import SwiftUI

/// A keyboard key drawn as a quiet keycap chip. Neutral by default; the tinted
/// variant is only used for hover feedback on clickable hotkey rows.
struct KeycapLabel: View {
    let text: String
    var tinted = false

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(tinted ? Color.accentColor : Color.primary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(tinted ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(
                        tinted ? Color.accentColor.opacity(0.25) : Color.primary.opacity(0.10),
                        lineWidth: 1
                    )
            )
    }
}

#Preview {
    HStack(spacing: 8) {
        KeycapLabel(text: "⌘")
        KeycapLabel(text: "Right ⌥")
        KeycapLabel(text: "Fn", tinted: true)
    }
    .padding()
}
