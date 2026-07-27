import SwiftUI

/// Segmented period selector for dashboard (6mo | 1y)
struct PeriodSelectorView: View {
    @Binding var selectedPeriod: DashboardPeriod

    var body: some View {
        HStack(spacing: 2) {
            ForEach(DashboardPeriod.allCases) { period in
                periodButton(period)
            }
        }
        .padding(2)
        .background(Capsule().fill(Color.primary.opacity(0.05)))
    }

    private func periodButton(_ period: DashboardPeriod) -> some View {
        let isSelected = selectedPeriod == period

        return Button {
            withAnimation(.easeOut(duration: 0.18)) {
                selectedPeriod = period
            }
        } label: {
            Text(period.rawValue)
                .font(.caption)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    Capsule().fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(period.displayName)
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State var period: DashboardPeriod = .sixMonths

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
