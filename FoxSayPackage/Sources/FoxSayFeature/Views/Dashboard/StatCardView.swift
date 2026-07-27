import SwiftUI

/// Individual statistic card for the dashboard
struct StatCardView: View {
    let icon: String
    let value: String
    let label: String
    let trend: String?

    init(
        icon: String,
        value: String,
        label: String,
        trend: String? = nil
    ) {
        self.icon = icon
        self.value = value
        self.label = label
        self.trend = trend
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if let trend {
                trendLabel(trend)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(padding: 14)
    }

    /// Only the direction arrow carries color; the wording stays neutral.
    @ViewBuilder
    private func trendLabel(_ trend: String) -> some View {
        let arrow = trend.prefix(1)

        if arrow == "↑" || arrow == "↓" {
            HStack(spacing: 3) {
                Text(arrow)
                    .foregroundStyle(arrow == "↑" ? Color.statusOK : Color.secondary)

                Text(trend.dropFirst().trimmingCharacters(in: .whitespaces))
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 10))
            .lineLimit(1)
        } else {
            Text(trend)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

#Preview {
    HStack(spacing: 12) {
        StatCardView(
            icon: "mic.fill",
            value: "2,847",
            label: "Sessions",
            trend: "↑ 12% this month"
        )

        StatCardView(
            icon: "text.bubble.fill",
            value: "847K",
            label: "Words",
            trend: "↓ 4% this month"
        )

        StatCardView(
            icon: "clock.fill",
            value: "353h",
            label: "Time Saved"
        )

        StatCardView(
            icon: "checkmark.seal.fill",
            value: "96.4%",
            label: "Accuracy"
        )
    }
    .padding()
    .frame(width: 500)
}
