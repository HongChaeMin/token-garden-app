import SwiftUI
import SwiftData

struct AccountsTabView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ModelBreakdownView()
                .padding(.horizontal, 12)
            ProjectProfileChartView()
                .padding(.horizontal, 12)
        }
        .padding(.vertical, 12)
    }
}

// MARK: - Shared Helpers

private func normalizeModel(_ raw: String) -> String? {
    let lower = raw.lowercased()
    if lower.contains("opus") { return "Opus" }
    if lower.contains("sonnet") { return "Sonnet" }
    if lower.contains("haiku") { return "Haiku" }
    return nil
}

private func modelColor(_ model: String) -> Color {
    switch model {
    case "Opus": return .purple
    case "Sonnet": return .orange
    case "Haiku": return .mint
    default: return .gray
    }
}

private func profileColor(for name: String) -> Color {
    let colors = ProfileColor.allCases
    let hash = name.unicodeScalars.reduce(0) { $0 &+ Int($1.value) &* 31 }
    let index = abs(hash) % colors.count
    return colors[index].color
}

// MARK: - Model Breakdown (overall)

private struct ModelBreakdownView: View {
    @Query private var allProjectUsages: [ProjectUsage]

    private var modelTokens: [(model: String, tokens: Int)] {
        var totals: [String: Int] = [:]
        for usage in allProjectUsages {
            guard let model = normalizeModel(usage.model ?? "") else { continue }
            totals[model, default: 0] += usage.tokens
        }
        return totals.map { (model: $0.key, tokens: $0.value) }
            .filter { $0.tokens > 0 }
            .sorted { $0.tokens > $1.tokens }
    }

    private var totalTokens: Int {
        modelTokens.reduce(0) { $0 + $1.tokens }
    }

    var body: some View {
        if !modelTokens.isEmpty && totalTokens > 0 {
            VStack(alignment: .leading, spacing: 6) {
                Text("Model Usage")
                    .font(.caption)
                    .fontWeight(.medium)

                GeometryReader { geo in
                    HStack(spacing: 1) {
                        ForEach(modelTokens, id: \.model) { item in
                            let ratio = Double(item.tokens) / Double(totalTokens)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(modelColor(item.model))
                                .frame(width: max(geo.size.width * ratio - 1, 2))
                        }
                    }
                }
                .frame(height: 6)
                .clipShape(RoundedRectangle(cornerRadius: 3))

                HStack(spacing: 10) {
                    ForEach(modelTokens, id: \.model) { item in
                        let pct = Double(item.tokens) / Double(totalTokens) * 100
                        HStack(spacing: 3) {
                            Circle()
                                .fill(modelColor(item.model))
                                .frame(width: 5, height: 5)
                            Text("\(item.model) \(String(format: "%.0f", pct))%")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }
            }
            .padding(8)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
        }
    }
}

// MARK: - Project × Profile Bar Chart

private struct ProjectProfileChartView: View {
    @Query private var allProjectUsages: [ProjectUsage]
    @State private var hoveredProject: String?
    @State private var selectedRange: TimeRange = .today

    enum TimeRange: String, CaseIterable {
        case today = "Today"
        case week = "Week"
        case month = "Month"
    }

    private var calendar: Calendar { Calendar.current }

    private var rangeStart: Date {
        switch selectedRange {
        case .today:
            return calendar.startOfDay(for: Date())
        case .week:
            var cal = calendar
            cal.firstWeekday = 2
            return cal.dateComponents([.calendar, .yearForWeekOfYear, .weekOfYear], from: Date()).date!
        case .month:
            let comps = calendar.dateComponents([.year, .month], from: Date())
            return calendar.date(from: comps)!
        }
    }

    private var filteredUsages: [ProjectUsage] {
        let start = rangeStart
        return allProjectUsages.filter { usage in
            guard let daily = usage.dailyUsage else { return false }
            return daily.date >= start
        }
    }

    private var projectData: [(project: String, profiles: [(name: String, tokens: Int)], total: Int)] {
        var byProject: [String: [String: Int]] = [:]
        for usage in filteredUsages {
            let project = usage.projectName
            let profile = usage.profileName ?? "Unknown"
            byProject[project, default: [:]][profile, default: 0] += usage.tokens
        }
        return byProject.map { project, profiles in
            let sorted = profiles.map { (name: $0.key, tokens: $0.value) }
                .sorted { $0.tokens > $1.tokens }
            let total = sorted.reduce(0) { $0 + $1.tokens }
            return (project: project, profiles: sorted, total: total)
        }
        .filter { $0.total > 0 }
        .sorted { $0.total > $1.total }
    }

    private var allProfileNames: [String] {
        var names = Set<String>()
        for item in projectData {
            for p in item.profiles { names.insert(p.name) }
        }
        return names.sorted()
    }

    private var maxTotal: Int {
        projectData.map(\.total).max() ?? 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Project × Account")
                    .font(.caption)
                    .fontWeight(.medium)
                Spacer()
                HStack(spacing: 2) {
                    ForEach(TimeRange.allCases, id: \.self) { range in
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
                            .onTapGesture { selectedRange = range }
                    }
                }
            }

            if projectData.isEmpty {
                Text("No data")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
                // Legend
                HStack(spacing: 8) {
                    ForEach(allProfileNames, id: \.self) { name in
                        HStack(spacing: 3) {
                            Circle()
                                .fill(profileColor(for: name))
                                .frame(width: 5, height: 5)
                            Text(name)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }

                // Bars
                VStack(spacing: 4) {
                    ForEach(projectData.prefix(10), id: \.project) { item in
                        projectBar(item)
                    }
                }
            }
        }
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private func projectBar(_ item: (project: String, profiles: [(name: String, tokens: Int)], total: Int)) -> some View {
        let isHovered = hoveredProject == item.project
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(item.project)
                    .font(.caption2)
                    .lineLimit(1)
                Spacer()
                Text(TokenFormatter.format(item.total))
                    .font(.system(size: 9).monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            GeometryReader { geo in
                let barWidth = geo.size.width * CGFloat(item.total) / CGFloat(maxTotal)
                HStack(spacing: 0) {
                    ForEach(item.profiles, id: \.name) { profile in
                        let ratio = CGFloat(profile.tokens) / CGFloat(item.total)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(profileColor(for: profile.name))
                            .frame(width: max(barWidth * ratio, 2))
                    }
                }
                .frame(height: 8)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .frame(height: 8)

            if isHovered {
                HStack(spacing: 6) {
                    ForEach(item.profiles, id: \.name) { profile in
                        let pct = Double(profile.tokens) / Double(item.total) * 100
                        Text("\(profile.name) \(String(format: "%.0f", pct))%")
                            .font(.system(size: 8))
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                }
            }
        }
        .onHover { isHovered in
            hoveredProject = isHovered ? item.project : nil
        }
    }
}
