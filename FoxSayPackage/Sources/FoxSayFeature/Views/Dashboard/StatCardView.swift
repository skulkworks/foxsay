import SwiftUI

/// Individual statistic card for the dashboard
struct StatCardView: View {
    let icon: String
    let value: String
    let label: String
    let color: Color
    let trend: String?

    init(
        icon: String,
        value: String,
        label: String,
        color: Color,
        trend: String? = nil
    ) {
        self.icon = icon
        self.value = value
        self.label = label
        self.color = color
        self.trend = trend
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Icon badge with dark grey background
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 28, height: 28)
                .background(Color.primary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                // Value
                Text(value)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                // Label
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            // Trend (optional)
            if let trend = trend {
                Text(trend)
                    .font(.system(size: 10))
                    .foregroundStyle(trend.hasPrefix("↑") ? Color.dashboardGreen : .secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.textBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    HStack(spacing: 12) {
        StatCardView(
            icon: "mic.fill",
            value: "2,847",
            label: "Sessions",
            color: .dashboardOrange,
            trend: "↑ 12% this month"
        )

        StatCardView(
            icon: "text.bubble.fill",
            value: "847K",
            label: "Words",
            color: .dashboardBlue,
            trend: nil
        )

        StatCardView(
            icon: "clock.fill",
            value: "353h",
            label: "Time Saved",
            color: .dashboardOrange
        )

        StatCardView(
            icon: "checkmark.seal.fill",
            value: "96.4%",
            label: "Accuracy",
            color: .dashboardBlue
        )
    }
    .padding()
    .frame(width: 500)
}
