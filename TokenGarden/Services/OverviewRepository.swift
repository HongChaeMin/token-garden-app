import Foundation
import SwiftData

/// Background SwiftData worker that produces `OverviewSnapshot` value objects.
///
/// Uses the `@ModelActor` macro so every fetch runs on the actor's executor
/// and never touches the main thread. Callers await the result and receive
/// Sendable value types — SwiftData entities never leak into the UI layer.
@ModelActor
actor OverviewRepository {

    /// Fetch everything the Overview tab needs for the default (today-centric)
    /// view. Relationship faulting happens here on the background executor.
    func loadSnapshot(referenceDate: Date = Date()) -> OverviewSnapshot {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: referenceDate)

        var weekCal = calendar
        weekCal.firstWeekday = 2
        let weekStart = weekCal.dateComponents(
            [.calendar, .yearForWeekOfYear, .weekOfYear],
            from: referenceDate
        ).date ?? today

        let monthComps = calendar.dateComponents([.year, .month], from: referenceDate)
        let monthStart = calendar.date(from: monthComps) ?? today

        // 1) Daily usages — drives heatmap, stats, and project breakdowns.
        var dailyDescriptor = FetchDescriptor<DailyUsage>()
        dailyDescriptor.sortBy = [SortDescriptor(\DailyUsage.date)]
        let dailies = (try? modelContext.fetch(dailyDescriptor)) ?? []

        var claudeToday = 0, claudeWeek = 0, claudeMonth = 0
        var codexToday = 0, codexWeek = 0, codexMonth = 0
        var heatmap: [HeatmapDay] = []
        heatmap.reserveCapacity(dailies.count)

        var todayRaw: [String: (claude: Int, codex: Int)] = [:]
        var weekRaw: [String: (claude: Int, codex: Int)] = [:]
        var monthRaw: [String: (claude: Int, codex: Int)] = [:]

        for daily in dailies {
            heatmap.append(HeatmapDay(date: daily.date, claudeTokens: daily.claudeTokens, codexTokens: daily.codexTokens))

            if daily.date == today {
                claudeToday = daily.claudeTokens
                codexToday = daily.codexTokens
            }
            if daily.date >= weekStart {
                claudeWeek += daily.claudeTokens
                codexWeek += daily.codexTokens
            }
            if daily.date >= monthStart {
                claudeMonth += daily.claudeTokens
                codexMonth += daily.codexTokens
            }

            // Relationship faulting happens on the background executor — safe.
            for project in daily.projectBreakdowns {
                let isCodex = (project.profileName ?? "").hasPrefix("Codex/")
                let delta = project.tokens
                let key = project.projectName

                if daily.date == today {
                    var cur = todayRaw[key] ?? (0, 0)
                    if isCodex { cur.codex += delta } else { cur.claude += delta }
                    todayRaw[key] = cur
                }
                if daily.date >= weekStart {
                    var cur = weekRaw[key] ?? (0, 0)
                    if isCodex { cur.codex += delta } else { cur.claude += delta }
                    weekRaw[key] = cur
                }
                if daily.date >= monthStart {
                    var cur = monthRaw[key] ?? (0, 0)
                    if isCodex { cur.codex += delta } else { cur.claude += delta }
                    monthRaw[key] = cur
                }
            }
        }

        // 2) Today's hourly buckets, per source.
        let (claudeHourly, codexHourly) = loadHourlyTokensBySource(for: today)

        // 3) Active sessions, per source.
        var sessionDescriptor = FetchDescriptor<SessionUsage>(
            predicate: #Predicate<SessionUsage> { $0.isActive == true }
        )
        sessionDescriptor.sortBy = [SortDescriptor(\SessionUsage.lastTime, order: .reverse)]
        let sessions = (try? modelContext.fetch(sessionDescriptor)) ?? []

        var claudeSessions: [SessionSummary] = []
        var codexSessions: [SessionSummary] = []
        for s in sessions {
            let summary = SessionSummary(
                sessionId: s.sessionId,
                projectName: s.projectName,
                startTime: s.startTime,
                lastTime: s.lastTime,
                totalTokens: s.totalTokens
            )
            if s.source == "codex" {
                codexSessions.append(summary)
            } else {
                claudeSessions.append(summary)
            }
        }

        return OverviewSnapshot(
            claudeTodayTokens: claudeToday,
            claudeWeekTokens: claudeWeek,
            claudeMonthTokens: claudeMonth,
            codexTodayTokens: codexToday,
            codexWeekTokens: codexWeek,
            codexMonthTokens: codexMonth,
            heatmap: heatmap,
            claudeHourlyToday: claudeHourly,
            codexHourlyToday: codexHourly,
            todayProjects: projectsFromRaw(todayRaw),
            weekProjects: projectsFromRaw(weekRaw),
            monthProjects: projectsFromRaw(monthRaw),
            claudeActiveSessions: claudeSessions,
            codexActiveSessions: codexSessions,
            hasAnyData: !dailies.isEmpty
        )
    }

    /// Hourly tokens for a specific day — used when the user selects a heatmap cell.
    /// Returns `(claudeBuckets, codexBuckets)`, each a 24-slot array.
    func loadHourlyTokensBySource(for date: Date) -> (claude: [Int], codex: [Int]) {
        let day = Calendar.current.startOfDay(for: date)
        let descriptor = FetchDescriptor<HourlyUsage>(
            predicate: #Predicate { $0.date == day }
        )
        let entries = (try? modelContext.fetch(descriptor)) ?? []
        var claude = Array(repeating: 0, count: 24)
        var codex = Array(repeating: 0, count: 24)
        for entry in entries where entry.hour >= 0 && entry.hour < 24 {
            if entry.source == "codex" {
                codex[entry.hour] += entry.tokens
            } else {
                claude[entry.hour] += entry.tokens
            }
        }
        return (claude, codex)
    }

    /// Project breakdown for a specific day.
    func loadProjects(for date: Date) -> [ProjectBreakdown] {
        let day = Calendar.current.startOfDay(for: date)
        let descriptor = FetchDescriptor<DailyUsage>(
            predicate: #Predicate { $0.date == day }
        )
        let dailies = (try? modelContext.fetch(descriptor)) ?? []

        var raw: [String: (claude: Int, codex: Int)] = [:]
        for daily in dailies {
            for project in daily.projectBreakdowns {
                let isCodex = (project.profileName ?? "").hasPrefix("Codex/")
                var cur = raw[project.projectName] ?? (0, 0)
                if isCodex { cur.codex += project.tokens } else { cur.claude += project.tokens }
                raw[project.projectName] = cur
            }
        }
        return projectsFromRaw(raw)
    }

    private func projectsFromRaw(_ raw: [String: (claude: Int, codex: Int)]) -> [ProjectBreakdown] {
        raw.map { ProjectBreakdown(name: $0.key, claudeTokens: $0.value.claude, codexTokens: $0.value.codex) }
            .filter { $0.totalTokens > 0 }
    }
}
