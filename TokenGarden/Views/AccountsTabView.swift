import SwiftUI
import SwiftData

struct AccountsTabView: View {
    @EnvironmentObject var profileManager: ProfileManager
    var onProfilesTap: () -> Void = {}
    var onCodexProfilesTap: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ProfileBannerView(onTap: onProfilesTap, onCodexTap: onCodexProfilesTap)
                .padding(.horizontal, 12)
                .padding(.top, 8)
            ProjectProfileChartView()
                .padding(.horizontal, 12)
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Active Profile Rate Limits

private struct ActiveProfileLimitsView: View {
    let limits: UsageLimits?

    private func resetLabel(for date: Date) -> String {
        let diff = date.timeIntervalSinceNow
        if diff <= 0 { return "Reset" }
        let hours = Int(diff / 3600)
        let minutes = Int((diff.truncatingRemainder(dividingBy: 3600)) / 60)
        if hours > 0 { return "Resets in \(hours)h \(minutes)m" }
        return "Resets in \(minutes)m"
    }

    private func barColor(_ utilization: Double) -> Color {
        if utilization >= 0.9 { return .red }
        if utilization >= 0.7 { return .orange }
        return .blue
    }

    var body: some View {
        if let limits {
            VStack(alignment: .leading, spacing: 8) {
                Text("Rate Limits")
                    .font(.caption)
                    .fontWeight(.medium)

                limitRow(label: "5h session", utilization: limits.fiveHourUtilization, resetAt: limits.fiveHourResetAt)
                limitRow(label: "7d rolling", utilization: limits.sevenDayUtilization, resetAt: limits.sevenDayResetAt)
            }
            .padding(8)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
        }
    }

    private func limitRow(label: String, utilization: Double, resetAt: Date) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(resetLabel(for: resetAt))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text(String(format: "%.0f%%", utilization * 100))
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(utilization >= 0.9 ? Color.red : .primary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.secondary.opacity(0.15))
                        .frame(height: 4)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(barColor(utilization))
                        .frame(width: geo.size.width * min(utilization, 1.0), height: 4)
                }
            }
            .frame(height: 4)
        }
    }
}

// MARK: - Shared Helpers

private func normalizeModel(_ raw: String) -> String? {
    let lower = raw.lowercased()
    if lower.contains("opus") { return "Opus" }
    if lower.contains("sonnet") { return "Sonnet" }
    if lower.contains("haiku") { return "Haiku" }
    if lower.hasPrefix("gpt-") || lower.hasPrefix("o") { return raw }
    return nil
}

private func modelColor(_ model: String) -> Color {
    switch model {
    case "Opus": return .purple
    case "Sonnet": return .orange
    case "Haiku": return .mint
    default:
        let codexColors: [Color] = [.green, .blue, .purple, .orange, .pink, .indigo, .brown]
        let hash = model.unicodeScalars.reduce(0) { $0 &+ Int($1.value) &* 31 }
        return codexColors[abs(hash) % codexColors.count]
    }
}

private func profileColor(for name: String) -> Color {
    if name.hasPrefix("Codex/") {
        let codexColors: [Color] = [.green, .indigo, .brown, .cyan, .pink]
        let hash = name.unicodeScalars.reduce(0) { $0 &+ Int($1.value) &* 31 }
        return codexColors[abs(hash) % codexColors.count]
    }
    let colors = ProfileColor.allCases
    let hash = name.unicodeScalars.reduce(0) { $0 &+ Int($1.value) &* 31 }
    let index = abs(hash) % colors.count
    return colors[index].color
}

private func isCodexProfileName(_ name: String) -> Bool {
    name.hasPrefix("Codex/")
}

private func sourceTokenLabel(title: String, color: Color, tokens: Int) -> some View {
    HStack(spacing: 3) {
        Circle()
            .fill(color)
            .frame(width: 5, height: 5)
        Text("\(title) \(TokenFormatter.format(tokens))")
            .font(.system(size: 9))
            .foregroundStyle(tokens > 0 ? .secondary : .quaternary)
    }
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

    private var claudeTokens: Int {
        allProjectUsages
            .filter { !isCodexProfileName($0.profileName ?? "") }
            .reduce(0) { $0 + $1.tokens }
    }

    private var codexTokens: Int {
        allProjectUsages
            .filter { isCodexProfileName($0.profileName ?? "") }
            .reduce(0) { $0 + $1.tokens }
    }

    var body: some View {
        if !modelTokens.isEmpty && totalTokens > 0 {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Model Usage")
                        .font(.caption)
                        .fontWeight(.medium)
                    Spacer()
                    Text("All \(TokenFormatter.format(totalTokens))")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

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

                HStack(spacing: 8) {
                    sourceTokenLabel(title: "Claude", color: .purple, tokens: claudeTokens)
                    sourceTokenLabel(title: "Codex", color: .green, tokens: codexTokens)
                    Spacer()
                }

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
    @Query private var codexProfiles: [CodexProfile]
    @State private var hoveredClaudeProject: String?
    @State private var hoveredCodexProject: String?
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

    private struct SourceProjectData {
        let project: String
        let profiles: [(name: String, tokens: Int)]
        let total: Int
    }

    private var claudeProjectData: [SourceProjectData] {
        projectData(forCodex: false)
    }

    private var codexProjectData: [SourceProjectData] {
        projectData(forCodex: true)
    }

    private func projectData(forCodex: Bool) -> [SourceProjectData] {
        var byProject: [String: [String: Int]] = [:]
        for usage in filteredUsages {
            let profile = usage.profileName ?? "Unknown"
            guard isCodexProfileName(profile) == forCodex else { continue }
            byProject[usage.projectName, default: [:]][profile, default: 0] += usage.tokens
        }
        return byProject.map { project, profiles in
            let sorted = profiles.map { (name: $0.key, tokens: $0.value) }
                .sorted { $0.tokens > $1.tokens }
            return SourceProjectData(
                project: project,
                profiles: sorted,
                total: sorted.reduce(0) { $0 + $1.tokens }
            )
        }
        .filter { $0.total > 0 }
        .sorted { $0.total > $1.total }
    }

    private var allProfileNames: [String] {
        var names = Set<String>()
        for item in claudeProjectData + codexProjectData {
            for p in item.profiles { names.insert(p.name) }
        }
        return names.sorted()
    }

    private var claudeProfileNames: [String] {
        allProfileNames.filter { !isCodexProfileName($0) }
    }

    private var codexProfileNames: [String] {
        allProfileNames.filter { isCodexProfileName($0) }
    }

    private func displayName(for profileName: String) -> String {
        if profileName.hasPrefix("Codex/") {
            let email = String(profileName.dropFirst("Codex/".count))
            if let saved = codexProfiles.first(where: { $0.email == email }) {
                return saved.name
            }
            return email.components(separatedBy: "@").first ?? email
        }
        return profileName
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

            if claudeProjectData.isEmpty && codexProjectData.isEmpty {
                Text("No data")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 10) {
                    sourceSection(
                        title: "Claude Accounts",
                        color: .purple,
                        projectData: claudeProjectData,
                        profileNames: claudeProfileNames,
                        hoveredProject: $hoveredClaudeProject
                    )
                    if !claudeProjectData.isEmpty && !codexProjectData.isEmpty {
                        Divider()
                            .padding(.vertical, 2)
                    }
                    sourceSection(
                        title: "Codex Accounts",
                        color: .green,
                        projectData: codexProjectData,
                        profileNames: codexProfileNames,
                        hoveredProject: $hoveredCodexProject
                    )
                }
            }
        }
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func sourceSection(
        title: String,
        color: Color,
        projectData: [SourceProjectData],
        profileNames: [String],
        hoveredProject: Binding<String?>
    ) -> some View {
        let total = projectData.reduce(0) { $0 + $1.total }
        if !projectData.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(title)
                        .font(.caption2)
                        .fontWeight(.medium)
                    Spacer()
                    sourceTokenLabel(
                        title: title.replacingOccurrences(of: " Accounts", with: ""),
                        color: color,
                        tokens: total
                    )
                }

                if !profileNames.isEmpty {
                    profileLegendRow(names: profileNames)
                }

                VStack(spacing: 4) {
                    ForEach(projectData.prefix(10), id: \.project) { item in
                        projectBar(
                            item,
                            maxTotal: projectData.map(\.total).max() ?? 1,
                            hoveredProject: hoveredProject
                        )
                    }
                }
            }
            .padding(8)
            .background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func projectBar(
        _ item: SourceProjectData,
        maxTotal: Int,
        hoveredProject: Binding<String?>
    ) -> some View {
        let isHovered = hoveredProject.wrappedValue == item.project
        return VStack(alignment: .leading, spacing: 3) {
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
                        Text("\(displayName(for: profile.name)) \(TokenFormatter.format(profile.tokens)) \(String(format: "%.0f", pct))%")
                            .font(.system(size: 8))
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                }
            }
        }
        .onHover { isHovered in
            hoveredProject.wrappedValue = isHovered ? item.project : nil
        }
    }

    private func profileLegendRow(names: [String]) -> some View {
        HStack(spacing: 8) {
            ForEach(names, id: \.self) { name in
                HStack(spacing: 3) {
                    Circle()
                        .fill(profileColor(for: name))
                        .frame(width: 5, height: 5)
                    Text(displayName(for: name))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
        }
    }
}
