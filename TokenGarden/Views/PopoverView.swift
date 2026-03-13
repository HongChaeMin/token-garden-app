import SwiftUI
import SwiftData

struct PopoverView: View {
    @EnvironmentObject var menuBarController: MenuBarController
    @Query(sort: \DailyUsage.date) private var allUsages: [DailyUsage]
    @State private var showSettings = false

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
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let start = calendar.date(byAdding: .day, value: -83, to: today)!
        return allUsages
            .filter { $0.date >= start }
            .map { (date: $0.date, tokens: $0.totalTokens) }
    }

    private var projectData: [(name: String, tokens: Int)] {
        var totals: [String: Int] = [:]
        for usage in allUsages {
            for project in usage.projectBreakdowns {
                totals[project.projectName, default: 0] += project.tokens
            }
        }
        return totals.map { (name: $0.key, tokens: $0.value) }
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
                Text("Token Garden")
                    .font(.headline)
                Spacer()
                Button(action: { showSettings.toggle() }) {
                    Image(systemName: "gearshape")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider()

            if let reason = emptyStateReason {
                EmptyStateView(reason: reason)
            } else if showSettings {
                SettingsView()
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        HeatmapView(dailyUsages: heatmapData)
                            .padding(.horizontal, 12)
                            .padding(.top, 8)

                        StatsView(
                            todayTokens: todayUsage?.totalTokens ?? 0,
                            weekTokens: weekTokens,
                            monthTokens: monthTokens
                        )
                        .padding(.horizontal, 12)

                        if !projectData.isEmpty {
                            ProjectListView(projects: projectData)
                                .padding(.horizontal, 12)
                        }
                    }
                    .padding(.bottom, 12)
                }
            }
        }
        .frame(width: 320, height: 400)
    }
}
