import SwiftUI
import SwiftData

struct SessionListView: View {
    @Query(
        filter: #Predicate<SessionUsage> { _ in true },
        sort: \SessionUsage.lastTime,
        order: .reverse
    ) private var allSessions: [SessionUsage]

    private var todaySessions: [SessionUsage] {
        let today = Calendar.current.startOfDay(for: Date())
        return allSessions.filter { $0.startTime >= today }
    }

    @State private var isExpanded = true

    var body: some View {
        if !todaySessions.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Button(action: { withAnimation { isExpanded.toggle() } }) {
                    HStack {
                        Label("Sessions", systemImage: "clock.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(todaySessions.count)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    }
                }
                .buttonStyle(.plain)

                if isExpanded {
                    VStack(spacing: 4) {
                        ForEach(todaySessions, id: \.sessionId) { session in
                            SessionRow(session: session)
                        }
                    }
                }
            }
            .padding(8)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

private struct SessionRow: View {
    let session: SessionUsage

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "HH:mm"
        return f
    }()

    private var duration: String {
        let interval = session.lastTime.timeIntervalSince(session.startTime)
        let minutes = Int(interval) / 60
        if minutes < 1 { return "<1m" }
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        if remainingMinutes == 0 { return "\(hours)h" }
        return "\(hours)h \(remainingMinutes)m"
    }

    var body: some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text(session.projectName)
                    .font(.caption)
                    .lineLimit(1)
                Text("\(Self.timeFormatter.string(from: session.startTime)) · \(duration)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Text(TokenFormatter.format(session.totalTokens))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
