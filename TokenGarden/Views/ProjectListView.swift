import SwiftUI

enum ProjectTimeRange: String, CaseIterable {
    case today = "Today"
    case week = "Week"
    case month = "Month"
}

struct ProjectListView: View {
    let todayProjects: [(name: String, tokens: Int)]
    let weekProjects: [(name: String, tokens: Int)]
    let monthProjects: [(name: String, tokens: Int)]
    var selectedDayProjects: [(name: String, tokens: Int)]?
    var selectedDayLabel: String?
    @State private var selectedRange: ProjectTimeRange = .week
    @State private var isExpanded = false

    private var activeProjects: [(name: String, tokens: Int)] {
        if let selected = selectedDayProjects {
            return selected
        }
        switch selectedRange {
        case .today: return todayProjects
        case .week: return weekProjects
        case .month: return monthProjects
        }
    }

    private var topProjects: [(name: String, tokens: Int)] {
        Array(activeProjects.sorted { $0.tokens > $1.tokens }.prefix(3))
    }

    private var totalTokens: Int {
        activeProjects.reduce(0) { $0 + $1.tokens }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Header
            HStack {
                Label(selectedDayLabel ?? "Projects", systemImage: "folder.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()

                if selectedDayProjects == nil {
                    // Time range picker
                    HStack(spacing: 2) {
                        ForEach(ProjectTimeRange.allCases, id: \.self) { range in
                            Text(range.rawValue)
                                .font(.system(size: 9, weight: selectedRange == range ? .semibold : .regular))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    selectedRange == range
                                        ? Color.accentColor.opacity(0.15)
                                        : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 4)
                                )
                                .foregroundStyle(selectedRange == range ? .primary : .secondary)
                                .onTapGesture {
                                    withAnimation { selectedRange = range }
                                }
                        }
                    }
                }
            }

            if activeProjects.isEmpty {
                Text("No projects")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 4)
            } else {
                let items = isExpanded ? activeProjects.sorted(by: { $0.tokens > $1.tokens }) : topProjects
                ForEach(items, id: \.name) { project in
                    HStack {
                        Text(project.name)
                            .font(.caption)
                            .lineLimit(1)
                        Spacer()
                        Text(TokenFormatter.format(project.tokens))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                        let pct = totalTokens > 0 ? Int(Double(project.tokens) / Double(totalTokens) * 100) : 0
                        Text("\(pct)%")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 30, alignment: .trailing)
                    }
                }

                if !isExpanded && activeProjects.count > 3 {
                    Text("More...")
                        .font(.caption)
                        .foregroundStyle(.blue)
                        .onTapGesture { withAnimation { isExpanded = true } }
                }
            }
        }
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}
