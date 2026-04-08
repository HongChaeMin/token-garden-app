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
                Image(systemName: "chevron.right")
                    .font(.system(size: 8))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
            }
            .contentShape(Rectangle())
            .onTapGesture { isExpanded.toggle() }

            if isExpanded {
                VStack(spacing: 6) {
                    statsRow(label: "Today", tokens: todayTokens)
                    statsRow(label: "This Week", tokens: weekTokens)
                    statsRow(label: "This Month", tokens: monthTokens)
                }
            }
        }
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private func statsRow(label: String, tokens: Int) -> some View {
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(TokenFormatter.format(tokens))
                    .font(.caption.monospacedDigit())
                    .fontWeight(.medium)
            }
        }
    }
}
