import SwiftUI
import SwiftData

struct PopoverView: View {
    @EnvironmentObject var menuBarController: MenuBarController
    @Query(sort: \DailyUsage.date) private var allUsages: [DailyUsage]
    enum Tab { case overview, accounts }
    enum OverviewSource: String, CaseIterable {
        case claude = "Claude"
        case codex = "Codex"
    }
    @State private var activeTab: Tab = .overview
    @State private var overviewSource: OverviewSource = .claude
    @State private var showSettings = false
    @State private var showProfiles = false
    @State private var showCodexProfiles = false
    @State private var selectedDate: Date?

    private var todayUsage: DailyUsage? {
        let today = Calendar.current.startOfDay(for: Date())
        return allUsages.first { $0.date == today }
    }

    private var weekUsages: [DailyUsage] {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        let weekStart = calendar.dateComponents([.calendar, .yearForWeekOfYear, .weekOfYear], from: Date()).date!
        return allUsages.filter { $0.date >= weekStart }
    }

    private var monthUsages: [DailyUsage] {
        let calendar = Calendar.current
        let comps = calendar.dateComponents([.year, .month], from: Date())
        let monthStart = calendar.date(from: comps)!
        return allUsages.filter { $0.date >= monthStart }
    }

    private var weekTokens: Int { weekUsages.reduce(0) { $0 + $1.totalTokens } }
    private var monthTokens: Int { monthUsages.reduce(0) { $0 + $1.totalTokens } }

    private var todayCodexTokens: Int { todayUsage?.codexTokens ?? 0 }
    private var weekCodexTokens: Int { weekUsages.reduce(0) { $0 + $1.codexTokens } }
    private var monthCodexTokens: Int { monthUsages.reduce(0) { $0 + $1.codexTokens } }

    private var todayClaudeTokens: Int { todayUsage?.claudeTokens ?? 0 }
    private var weekClaudeTokens: Int { weekUsages.reduce(0) { $0 + $1.claudeTokens } }
    private var monthClaudeTokens: Int { monthUsages.reduce(0) { $0 + $1.claudeTokens } }

    private var heatmapData: [(date: Date, tokens: Int)] {
        allUsages.map { usage in
            (date: usage.date, tokens: sourceTokens(for: usage))
        }
    }

    @Query private var allHourlyUsages: [HourlyUsage]

    private var activeHourlyTokens: [Int] {
        let cal = Calendar.current
        let targetDay = cal.startOfDay(for: selectedDate ?? Date())

        let source = overviewSource == .claude ? "claude" : "codex"
        let dayEntries = allHourlyUsages.filter { $0.date == targetDay && $0.source == source }

        var buckets = Array(repeating: 0, count: 24)
        for entry in dayEntries {
            guard entry.hour >= 0 && entry.hour < 24 else { continue }
            buckets[entry.hour] += entry.tokens
        }
        return buckets
    }

    private var overviewTodayTokens: Int {
        overviewSource == .claude ? todayClaudeTokens : todayCodexTokens
    }

    private var overviewWeekTokens: Int {
        overviewSource == .claude ? weekClaudeTokens : weekCodexTokens
    }

    private var overviewMonthTokens: Int {
        overviewSource == .claude ? monthClaudeTokens : monthCodexTokens
    }

    // MARK: - Project data by time range

    private func projectsForUsages(_ usages: [DailyUsage]) -> [ProjectSourceBreakdown] {
        var totals: [String: (claude: Int, codex: Int)] = [:]
        for usage in usages {
            for project in usage.projectBreakdowns {
                let isCodex = (project.profileName ?? "").hasPrefix("Codex/")
                if isCodex {
                    totals[project.projectName, default: (0, 0)].codex += project.tokens
                } else {
                    totals[project.projectName, default: (0, 0)].claude += project.tokens
                }
            }
        }
        return totals.map { item in
            let total = overviewSource == .claude ? item.value.claude : item.value.codex
            return ProjectSourceBreakdown(
                name: item.key,
                totalTokens: total,
                claudeTokens: overviewSource == .claude ? item.value.claude : 0,
                codexTokens: overviewSource == .codex ? item.value.codex : 0
            )
        }
        .filter { $0.totalTokens > 0 }
    }

    private var todayProjects: [ProjectSourceBreakdown] {
        let today = Calendar.current.startOfDay(for: Date())
        return projectsForUsages(allUsages.filter { $0.date == today })
    }

    private var weekProjects: [ProjectSourceBreakdown] {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        let weekStart = calendar.dateComponents([.calendar, .yearForWeekOfYear, .weekOfYear], from: Date()).date!
        return projectsForUsages(allUsages.filter { $0.date >= weekStart })
    }

    private var monthProjects: [ProjectSourceBreakdown] {
        let calendar = Calendar.current
        let comps = calendar.dateComponents([.year, .month], from: Date())
        let monthStart = calendar.date(from: comps)!
        return projectsForUsages(allUsages.filter { $0.date >= monthStart })
    }

    private var selectedDayProjects: [ProjectSourceBreakdown]? {
        guard let date = selectedDate else { return nil }
        let day = Calendar.current.startOfDay(for: date)
        let usages = allUsages.filter { $0.date == day }
        guard !usages.isEmpty else { return [] }
        return projectsForUsages(usages)
    }

    private var selectedDayLabel: String? {
        guard let date = selectedDate else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "M/d (E)"
        return formatter.string(from: date)
    }

    private var emptyStateReason: EmptyStateReason? {
        if activeTab == .overview && overviewSource == .codex {
            return nil
        }

        let logPath = UserDefaults.standard.string(forKey: "logPath") ?? "~/.claude/"
        let expandedPath = NSString(string: logPath).expandingTildeInPath

        if !FileManager.default.fileExists(atPath: expandedPath) {
            return .noClaudeCode
        }
        if !FileManager.default.isReadableFile(atPath: expandedPath) {
            return .noPermission
        }
        if allUsages.isEmpty && overviewSource == .claude {
            return .noData
        }
        return nil
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if showSettings || showProfiles || showCodexProfiles {
                    Button(action: {
                        showSettings = false
                        showProfiles = false
                        showCodexProfiles = false
                    }) {
                        Image(systemName: "chevron.left")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    Text(showCodexProfiles ? "Codex Profiles" : showProfiles ? "Profiles" : "Settings")
                        .font(.headline)
                } else {
                    Text("Token Garden")
                        .font(.headline)
                }
                Spacer()
                if !showSettings && !showProfiles && !showCodexProfiles {
                    HStack(spacing: 12) {
                        Button(action: { activeTab = .overview }) {
                            Image(systemName: "chart.bar")
                                .foregroundStyle(activeTab == .overview ? .primary : .tertiary)
                        }
                        .buttonStyle(.plain)
                        Button(action: { activeTab = .accounts }) {
                            Image(systemName: "person.2")
                                .foregroundStyle(activeTab == .accounts ? .primary : .tertiary)
                        }
                        .buttonStyle(.plain)
                        Button(action: { showSettings = true }) {
                            Image(systemName: "gearshape")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider()


            if let reason = emptyStateReason {
                EmptyStateView(reason: reason)
                    .frame(minHeight: 200)
            } else if showSettings {
                SettingsView()
                    .transition(.identity)
            } else if showProfiles {
                ProfileListView()
            } else if showCodexProfiles {
                CodexProfileListView()
            } else if activeTab == .accounts {
                AccountsTabView(
                    onProfilesTap: { showProfiles = true },
                    onCodexProfilesTap: { showCodexProfiles = true }
                )
                    .transition(.identity)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 6) {
                        ForEach(OverviewSource.allCases, id: \.self) { source in
                            Text(source.rawValue)
                                .font(.system(size: 11, weight: overviewSource == source ? .semibold : .regular))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(
                                    overviewSource == source ? Color.accentColor.opacity(0.15) : Color.clear,
                                    in: Capsule()
                                )
                                .foregroundStyle(overviewSource == source ? .primary : .secondary)
                                .onTapGesture {
                                    overviewSource = source
                                }
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 8)

                    HeatmapView(dailyUsages: heatmapData, selectedDate: $selectedDate)
                        .padding(.horizontal, 12)

                    if let date = selectedDate,
                       let usage = allUsages.first(where: {
                           Calendar.current.isDate($0.date, inSameDayAs: date)
                       }) {
                        let selectedTokens = sourceTokens(for: usage)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(selectedDayLabel ?? "")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(TokenFormatter.format(selectedTokens))
                                    .font(.caption.monospacedDigit())
                                    .fontWeight(.medium)
                            }
                            HStack(spacing: 8) {
                                sourceSummaryLabel(
                                    title: overviewSource.rawValue,
                                    color: overviewSource == .claude ? .purple : .green,
                                    tokens: selectedTokens
                                )
                                Spacer()
                            }
                        }
                        .padding(8)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                        .padding(.horizontal, 12)
                    } else {
                        StatsView(
                            todayTokens: overviewTodayTokens,
                            weekTokens: overviewWeekTokens,
                            monthTokens: overviewMonthTokens
                        )
                        .padding(.horizontal, 12)
                    }

                    HourlyChartView(
                        hourlyTokens: activeHourlyTokens,
                        title: "\(overviewSource.rawValue) Hourly",
                        isToday: selectedDate == nil || Calendar.current.isDateInToday(selectedDate!)
                    )
                        .padding(.horizontal, 12)

                    ProjectListView(
                        todayProjects: todayProjects,
                        weekProjects: weekProjects,
                        monthProjects: monthProjects,
                        selectedDayProjects: selectedDayProjects,
                        selectedDayLabel: selectedDayLabel
                    )
                    .padding(.horizontal, 12)

                    SessionListView(source: overviewSource == .claude ? .claude : .codex)
                        .padding(.horizontal, 12)
                }
                .padding(.bottom, 12)
            }
        }
        .frame(width: 340)
        .animation(nil, value: showSettings)
        .animation(nil, value: showProfiles)
        .animation(nil, value: showCodexProfiles)
        .animation(nil, value: activeTab)
        .animation(nil, value: overviewSource)
    }

    private func sourceSummaryLabel(title: String, color: Color, tokens: Int) -> some View {
        HStack(spacing: 3) {
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
            Text("\(title) \(TokenFormatter.format(tokens))")
                .font(.system(size: 9))
                .foregroundStyle(tokens > 0 ? .tertiary : .quaternary)
        }
    }

    private func sourceTokens(for usage: DailyUsage) -> Int {
        overviewSource == .claude ? usage.claudeTokens : usage.codexTokens
    }

}
