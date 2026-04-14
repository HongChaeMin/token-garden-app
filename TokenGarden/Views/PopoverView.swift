import SwiftUI
import SwiftData

struct PopoverView: View {
    @EnvironmentObject var menuBarController: MenuBarController
    @Environment(OverviewViewModel.self) private var vm

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

    // MARK: - Snapshot-derived values (no @Query, no main-thread fetch)

    private var snapshot: OverviewSnapshot { vm.snapshot }

    private var overviewTodayTokens: Int {
        overviewSource == .claude ? snapshot.claudeTodayTokens : snapshot.codexTodayTokens
    }
    private var overviewWeekTokens: Int {
        overviewSource == .claude ? snapshot.claudeWeekTokens : snapshot.codexWeekTokens
    }
    private var overviewMonthTokens: Int {
        overviewSource == .claude ? snapshot.claudeMonthTokens : snapshot.codexMonthTokens
    }

    private var heatmapData: [(date: Date, tokens: Int)] {
        snapshot.heatmap.map { day in
            (date: day.date, tokens: overviewSource == .claude ? day.claudeTokens : day.codexTokens)
        }
    }

    private var activeHourlyTokens: [Int] {
        overviewSource == .claude ? vm.activeClaudeHourlyTokens : vm.activeCodexHourlyTokens
    }

    private var activeSessions: [SessionSummary] {
        overviewSource == .claude ? snapshot.claudeActiveSessions : snapshot.codexActiveSessions
    }

    // MARK: - Source filtering for ProjectListView

    private func filteredProjects(_ raw: [ProjectBreakdown]) -> [ProjectSourceBreakdown] {
        raw.compactMap { row in
            let sourceTokens = overviewSource == .claude ? row.claudeTokens : row.codexTokens
            guard sourceTokens > 0 else { return nil }
            return ProjectSourceBreakdown(
                name: row.name,
                totalTokens: sourceTokens,
                claudeTokens: overviewSource == .claude ? row.claudeTokens : 0,
                codexTokens: overviewSource == .codex ? row.codexTokens : 0
            )
        }
    }

    private var todayProjects: [ProjectSourceBreakdown] { filteredProjects(snapshot.todayProjects) }
    private var weekProjects: [ProjectSourceBreakdown] { filteredProjects(snapshot.weekProjects) }
    private var monthProjects: [ProjectSourceBreakdown] { filteredProjects(snapshot.monthProjects) }

    private var selectedDayProjects: [ProjectSourceBreakdown]? {
        guard vm.selectedDate != nil, let raw = vm.selectedDayProjects else { return nil }
        return filteredProjects(raw)
    }

    private var selectedDayLabel: String? {
        guard let date = vm.selectedDate else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "M/d (E)"
        return formatter.string(from: date)
    }

    private var selectedDayTokens: Int? {
        guard let date = vm.selectedDate else { return nil }
        let day = Calendar.current.startOfDay(for: date)
        guard let row = snapshot.heatmap.first(where: {
            Calendar.current.isDate($0.date, inSameDayAs: day)
        }) else { return nil }
        return overviewSource == .claude ? row.claudeTokens : row.codexTokens
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
        if !snapshot.hasAnyData && overviewSource == .claude {
            return .noData
        }
        return nil
    }

    // MARK: - Body

    var body: some View {
        @Bindable var vm = vm
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

            if vm.isInitialLoading && activeTab == .overview && !showSettings && !showProfiles && !showCodexProfiles {
                OverviewSkeleton()
            } else if let reason = emptyStateReason {
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

                    HeatmapView(dailyUsages: heatmapData, selectedDate: $vm.selectedDate)
                        .padding(.horizontal, 12)

                    if let tokens = selectedDayTokens {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(selectedDayLabel ?? "")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(TokenFormatter.format(tokens))
                                    .font(.caption.monospacedDigit())
                                    .fontWeight(.medium)
                            }
                            HStack(spacing: 8) {
                                sourceSummaryLabel(
                                    title: overviewSource.rawValue,
                                    color: overviewSource == .claude ? .purple : .green,
                                    tokens: tokens
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
                        isToday: vm.selectedDate == nil || Calendar.current.isDateInToday(vm.selectedDate!)
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

                    SessionListView(
                        source: overviewSource == .claude ? .claude : .codex,
                        sessions: activeSessions
                    )
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
}
