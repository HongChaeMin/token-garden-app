import SwiftUI
import SwiftData

struct SessionListView: View {
    @Query(
        filter: #Predicate<SessionUsage> { _ in true },
        sort: \SessionUsage.lastTime,
        order: .reverse
    ) private var allSessions: [SessionUsage]

    private var activeSessions: [SessionUsage] {
        allSessions.filter { $0.isActive }
    }

    private var recentSessions: [SessionUsage] {
        let inactive = allSessions.filter { !$0.isActive }
        return Array(inactive.prefix(5))
    }

    private var displaySessions: [SessionUsage] {
        let active = activeSessions
        if !active.isEmpty { return active }
        return recentSessions
    }

    private var sectionTitle: String {
        activeSessions.isEmpty ? "Recent Sessions" : "Active Sessions"
    }

    @State private var isExpanded = true

    var body: some View {
        if !displaySessions.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Button(action: { withAnimation(.easeOut(duration: 0.15)) { isExpanded.toggle() } }) {
                    HStack {
                        Label(sectionTitle, systemImage: activeSessions.isEmpty ? "clock.fill" : "bolt.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(displaySessions.count)")
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
                    ScrollView {
                        VStack(spacing: 4) {
                            ForEach(displaySessions, id: \.sessionId) { session in
                                SessionRow(session: session)
                            }
                        }
                    }
                    .frame(maxHeight: 500)
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
            if session.isActive {
                Circle()
                    .fill(.green)
                    .frame(width: 6, height: 6)
            }
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
