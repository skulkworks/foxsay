import SwiftUI

/// Individual system status card
struct SystemStatusCard: View {
    let icon: String
    let label: String
    let value: String
    let statusColor: Color
    let isLoading: Bool
    let action: (() -> Void)?

    @State private var pulseAnimation = false

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
            HStack(spacing: 12) {
                // Icon with colored background
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(statusColor.opacity(0.15))
                        .frame(width: 40, height: 40)

                    if isLoading {
                        SpinningStatusIcon(icon: icon, color: statusColor)
                    } else {
                        Image(systemName: icon)
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(statusColor)
                    }
                }

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

                Spacer()

                // Status indicator dot
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                    .overlay {
                        if isLoading {
                            Circle()
                                .stroke(statusColor.opacity(0.5), lineWidth: 2)
                                .scaleEffect(pulseAnimation ? 2.0 : 1.0)
                                .opacity(pulseAnimation ? 0 : 0.8)
                        }
                    }
                    .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: pulseAnimation)
                    .onAppear {
                        if isLoading {
                            pulseAnimation = true
                        }
                    }
                    .onChange(of: isLoading) { _, newValue in
                        pulseAnimation = newValue
                    }
            }
            .padding(12)
            .background(Color(.textBackgroundColor).opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

/// Spinning icon for loading states
private struct SpinningStatusIcon: View {
    let icon: String
    let color: Color

    var body: some View {
        TimelineView(.animation) { timeline in
            let rotation = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.0) * 360

            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(color)
                .rotationEffect(.degrees(rotation))
        }
    }
}

#Preview {
    VStack(spacing: 12) {
        HStack(spacing: 12) {
            SystemStatusCard(
                icon: "mic.fill",
                label: "Microphone",
                value: "MacBook Pro Microphone",
                statusColor: .dashboardGreen
            )

            SystemStatusCard(
                icon: "hand.raised.fill",
                label: "Accessibility",
                value: "Enabled",
                statusColor: .dashboardGreen
            )
        }

        HStack(spacing: 12) {
            SystemStatusCard(
                icon: "waveform",
                label: "Speech Model",
                value: "Parakeet v2",
                statusColor: .dashboardBlue,
                isLoading: true
            )

            SystemStatusCard(
                icon: "brain",
                label: "AI Model",
                value: "Llama 3.2 3B",
                statusColor: .dashboardPurple
            )
        }
    }
    .padding()
    .frame(width: 500)
}
