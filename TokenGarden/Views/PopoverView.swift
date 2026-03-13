import SwiftUI
import SwiftData

struct PopoverView: View {
    @EnvironmentObject var menuBarController: MenuBarController
    @Query(sort: \DailyUsage.date) private var allUsages: [DailyUsage]
    @State private var showSettings = false
    @State private var selectedDate: Date?

    private var todayUsage: DailyUsage? {
        let today = Calendar.current.startOfDay(for: Date())
        return allUsages.first { $0.date == today }
    }

    private var weekTokens: Int {
        let calendar = Calendar.current
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: Date())!
        return allUsages
            .filter { $0.date >= calendar.startOfDay(for: weekAgo) }
            .reduce(0) { $0 + $1.totalTokens }
    }

    private var monthTokens: Int {
        let calendar = Calendar.current
        let monthAgo = calendar.date(byAdding: .month, value: -1, to: Date())!
        return allUsages
            .filter { $0.date >= calendar.startOfDay(for: monthAgo) }
            .reduce(0) { $0 + $1.totalTokens }
    }

    private var heatmapData: [(date: Date, tokens: Int)] {
        allUsages.map { (date: $0.date, tokens: $0.totalTokens) }
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
        let calendar = Calendar.current
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: Date())!
        return projectsForUsages(allUsages.filter { $0.date >= calendar.startOfDay(for: weekAgo) })
    }

    private var monthProjects: [(name: String, tokens: Int)] {
        let calendar = Calendar.current
        let monthAgo = calendar.date(byAdding: .month, value: -1, to: Date())!
        return projectsForUsages(allUsages.filter { $0.date >= calendar.startOfDay(for: monthAgo) })
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
                if showSettings {
                    Button(action: { showSettings = false }) {
                        Image(systemName: "chevron.left")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                Text(showSettings ? "Settings" : "Token Garden")
                    .font(.headline)
                Spacer()
                if !showSettings {
                    Button(action: { showSettings = true }) {
                        Image(systemName: "gearshape")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
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
            } else {
                VStack(spacing: 12) {
                    HeatmapView(dailyUsages: heatmapData, selectedDate: $selectedDate)
                        .padding(.horizontal, 12)
                        .padding(.top, 8)

                    // Show selected day stats or normal stats
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
    }
}
