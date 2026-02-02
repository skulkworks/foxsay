import SwiftUI

/// Segmented period selector for dashboard (30d | 6mo | 1y)
struct PeriodSelectorView: View {
    @Binding var selectedPeriod: DashboardPeriod

    var body: some View {
        HStack(spacing: 4) {
            ForEach(DashboardPeriod.allCases) { period in
                periodButton(period)
            }
        }
        .padding(3)
        .background(Color(.textBackgroundColor).opacity(0.5))
        .clipShape(Capsule())
    }

    private func periodButton(_ period: DashboardPeriod) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedPeriod = period
            }
        } label: {
            Text(period.rawValue)
                .font(.caption)
                .fontWeight(selectedPeriod == period ? .semibold : .regular)
                .foregroundStyle(selectedPeriod == period ? .primary : .secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    selectedPeriod == period
                        ? Color(.textBackgroundColor)
                        : Color.clear
                )
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State var period: DashboardPeriod = .thirtyDays

        var body: some View {
            VStack(spacing: 20) {
                PeriodSelectorView(selectedPeriod: $period)

                Text("Selected: \(period.displayName)")
                    .font(.caption)
            }
            .padding()
        }
    }

    return PreviewWrapper()
}
