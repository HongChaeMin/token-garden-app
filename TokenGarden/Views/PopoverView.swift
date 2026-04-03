import SwiftUI
import SwiftData

struct PopoverView: View {
    @EnvironmentObject var menuBarController: MenuBarController
    @Query(sort: \DailyUsage.date) private var allUsages: [DailyUsage]
    enum Tab { case overview, accounts }
    @State private var activeTab: Tab = .overview
    @State private var showSettings = false
    @State private var showProfiles = false
    @State private var selectedDate: Date?

    private var todayUsage: DailyUsage? {
        let today = Calendar.current.startOfDay(for: Date())
        return allUsages.first { $0.date == today }
    }

    private var weekTokens: Int {
        var calendar = Calendar.current
        calendar.firstWeekday = 2 // Monday
        let weekStart = calendar.dateComponents([.calendar, .yearForWeekOfYear, .weekOfYear], from: Date()).date!
        return allUsages
            .filter { $0.date >= weekStart }
            .reduce(0) { $0 + $1.totalTokens }
    }

    private var monthTokens: Int {
        let calendar = Calendar.current
        let comps = calendar.dateComponents([.year, .month], from: Date())
        let monthStart = calendar.date(from: comps)!
        return allUsages
            .filter { $0.date >= monthStart }
            .reduce(0) { $0 + $1.totalTokens }
    }

    private var heatmapData: [(date: Date, tokens: Int)] {
        allUsages.map { (date: $0.date, tokens: $0.totalTokens) }
    }

    @Query private var allHourlyUsages: [HourlyUsage]

    private var activeHourlyTokens: [Int] {
        let cal = Calendar.current
        let targetDay = cal.startOfDay(for: selectedDate ?? Date())

        let dayEntries = allHourlyUsages.filter { $0.date == targetDay }

        var buckets = Array(repeating: 0, count: 24)
        for entry in dayEntries {
            guard entry.hour >= 0 && entry.hour < 24 else { continue }
            buckets[entry.hour] += entry.tokens
        }
        return buckets
    }

    // MARK: - Project data by time range

    private func projectsForUsages(_ usages: [DailyUsage]) -> [(name: String, tokens: Int)] {
        var totals: [String: Int] = [:]
        for usage in usages {
            for project in usage.projectBreakdowns {
                totals[project.projectName, default: 0] += project.tokens
            }
        }
        return totals.map { (name: $0.key, tokens: $0.value) }
    }

    private var todayProjects: [(name: String, tokens: Int)] {
        let today = Calendar.current.startOfDay(for: Date())
        return projectsForUsages(allUsages.filter { $0.date == today })
    }

    private var weekProjects: [(name: String, tokens: Int)] {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        let weekStart = calendar.dateComponents([.calendar, .yearForWeekOfYear, .weekOfYear], from: Date()).date!
        return projectsForUsages(allUsages.filter { $0.date >= weekStart })
    }

    private var monthProjects: [(name: String, tokens: Int)] {
        let calendar = Calendar.current
        let comps = calendar.dateComponents([.year, .month], from: Date())
        let monthStart = calendar.date(from: comps)!
        return projectsForUsages(allUsages.filter { $0.date >= monthStart })
    }

    private var selectedDayProjects: [(name: String, tokens: Int)]? {
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
        let logPath = UserDefaults.standard.string(forKey: "logPath") ?? "~/.claude/"
        let expandedPath = NSString(string: logPath).expandingTildeInPath

        if !FileManager.default.fileExists(atPath: expandedPath) {
            return .noClaudeCode
        }
        if !FileManager.default.isReadableFile(atPath: expandedPath) {
            return .noPermission
        }
        if allUsages.isEmpty {
            return .noData
        }
        return nil
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if showSettings || showProfiles {
                    Button(action: {
                        showSettings = false
                        showProfiles = false
                    }) {
                        Image(systemName: "chevron.left")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    Text(showProfiles ? "Profiles" : "Settings")
                        .font(.headline)
                } else {
                    Text("Token Garden")
                        .font(.headline)
                }
                Spacer()
                if !showSettings && !showProfiles {
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

            if !showSettings && !showProfiles && activeTab == .accounts {
                ProfileBannerView(onTap: { showProfiles = true })
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
            }

            if let reason = emptyStateReason {
                EmptyStateView(reason: reason)
                    .frame(minHeight: 200)
            } else if showSettings {
                SettingsView()
                    .transition(.identity)
            } else if showProfiles {
                ProfileListView()
            } else if activeTab == .accounts {
                AccountsTabView()
                    .transition(.identity)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    HeatmapView(dailyUsages: heatmapData, selectedDate: $selectedDate)
                        .padding(.horizontal, 12)
                        .padding(.top, 8)

                    if let date = selectedDate,
                       let usage = allUsages.first(where: {
                           Calendar.current.isDate($0.date, inSameDayAs: date)
                       }) {
                        HStack {
                            Text(selectedDayLabel ?? "")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(TokenFormatter.format(usage.totalTokens))
                                .font(.caption.monospacedDigit())
                                .fontWeight(.medium)
                        }
                        .padding(8)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                        .padding(.horizontal, 12)
                    } else {
                        StatsView(
                            todayTokens: todayUsage?.totalTokens ?? 0,
                            weekTokens: weekTokens,
                            monthTokens: monthTokens
                        )
                        .padding(.horizontal, 12)
                    }

                    HourlyChartView(
                        hourlyTokens: activeHourlyTokens,
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

                    SessionListView()
                        .padding(.horizontal, 12)
                }
                .padding(.bottom, 12)
            }
        }
        .frame(width: 320)
        .animation(nil, value: showSettings)
        .animation(nil, value: showProfiles)
        .animation(nil, value: activeTab)
    }
}
