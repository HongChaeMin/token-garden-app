import SwiftUI
import SwiftData

enum SessionSource {
    case claude
    case codex
}

struct SessionListView: View {
    let source: SessionSource
    @Query(sort: \SessionUsage.lastTime, order: .reverse) private var allSessions: [SessionUsage]

    @State private var isExpanded = false

    private var activeSessions: [SessionUsage] {
        switch source {
        case .claude:
            return allSessions.filter { $0.source == "claude" && $0.isActive }
        case .codex:
            return allSessions.filter { $0.source == "codex" && $0.isActive }
        }
    }

    private var title: String {
        switch source {
        case .claude: return "Active Sessions"
        case .codex: return "Active Threads"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: { isExpanded.toggle() }) {
                HStack {
                    Label(title, systemImage: "bolt.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(activeSessions.count)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                if activeSessions.isEmpty {
                    Text(source == .claude ? "No active sessions" : "No active threads")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.vertical, 4)
                } else {
                    let content = VStack(spacing: 4) {
                        ForEach(activeSessions, id: \.sessionId) { session in
                            SessionRow(session: session)
                        }
                    }
                    if activeSessions.count > 10 {
                        ScrollView { content }
                            .scrollIndicators(.never)
                            .frame(maxHeight: 250)
                    } else {
                        content
                    }
                }
            }
        }
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
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
        let interval = Date().timeIntervalSince(session.startTime)
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
            Circle()
                .fill(.green)
                .frame(width: 6, height: 6)
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
