import SwiftUI

struct StatsView: View {
    let todayTokens: Int
    let weekTokens: Int
    let monthTokens: Int
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Stats", systemImage: "chart.bar.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if !isExpanded {
                    Text(TokenFormatter.format(todayTokens))
                        .font(.caption.monospacedDigit())
                        .fontWeight(.medium)
                }
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 8))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
            .onTapGesture { withAnimation { isExpanded.toggle() } }

            if isExpanded {
                VStack(spacing: 6) {
                    statsRow(label: "Today", value: todayTokens)
                    statsRow(label: "This Week", value: weekTokens)
                    statsRow(label: "This Month", value: monthTokens)
                }
            }
        }
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private func statsRow(label: String, value: Int) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(TokenFormatter.format(value))
                .font(.caption.monospacedDigit())
                .fontWeight(.medium)
        }
    }
}
