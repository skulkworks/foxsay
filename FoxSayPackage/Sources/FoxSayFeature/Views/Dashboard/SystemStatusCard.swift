import SwiftUI

/// Individual system status card
struct SystemStatusCard: View {
    let icon: String
    let label: String
    let value: String
    let statusColor: Color
    let isLoading: Bool
    let action: (() -> Void)?

    init(
        icon: String,
        label: String,
        value: String,
        statusColor: Color,
        isLoading: Bool = false,
        action: (() -> Void)? = nil
    ) {
        self.icon = icon
        self.label = label
        self.value = value
        self.statusColor = statusColor
        self.isLoading = isLoading
        self.action = action
    }

    var body: some View {
        Button {
            action?()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.primary.opacity(0.06))
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(value)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.65)
                        .frame(width: 12, height: 12)
                } else {
                    StatusDot(color: statusColor)
                }
            }
            .cardSurface(padding: 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    VStack(spacing: 10) {
        HStack(spacing: 10) {
            SystemStatusCard(
                icon: "mic.fill",
                label: "Microphone",
                value: "MacBook Pro Microphone",
                statusColor: .statusOK
            )

            SystemStatusCard(
                icon: "hand.raised",
                label: "Accessibility",
                value: "Permission Required",
                statusColor: .statusWarning
            )
        }

        HStack(spacing: 10) {
            SystemStatusCard(
                icon: "waveform",
                label: "Speech Model",
                value: "Parakeet v2",
                statusColor: .statusOK,
                isLoading: true
            )

            SystemStatusCard(
                icon: "brain",
                label: "AI Model",
                value: "Llama 3.2 3B",
                statusColor: .statusOK
            )
        }
    }
    .padding()
    .frame(width: 500)
}
