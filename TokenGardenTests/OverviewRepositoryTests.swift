import Testing
import SwiftData
import Foundation
@testable import TokenGarden

/// Exercises OverviewRepository against an in-memory SwiftData container.
///
/// The Repository runs on a background ModelActor — tests invoke it from the
/// MainActor and verify the returned Sendable OverviewSnapshot values.
@MainActor
struct OverviewRepositoryTests {
    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: DailyUsage.self,
            ProjectUsage.self,
            SessionUsage.self,
            HourlyUsage.self,
            ProfileTokenUsage.self,
            configurations: config
        )
    }

    @Test func loadSnapshotOnEmptyStoreReturnsEmpty() async throws {
        let container = try makeContainer()
        let repo = OverviewRepository(modelContainer: container)

        let snapshot = await repo.loadSnapshot()

        #expect(snapshot.hasAnyData == false)
        #expect(snapshot.heatmap.isEmpty)
        #expect(snapshot.claudeTodayTokens == 0)
        #expect(snapshot.codexTodayTokens == 0)
        #expect(snapshot.claudeActiveSessions.isEmpty)
        #expect(snapshot.codexActiveSessions.isEmpty)
        #expect(snapshot.claudeHourlyToday.count == 24)
        #expect(snapshot.codexHourlyToday.count == 24)
    }

    @Test func loadSnapshotAggregatesTodayByBothSources() async throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let today = Calendar.current.startOfDay(for: Date())

        let daily = DailyUsage(date: today)
        daily.inputTokens = 300
        daily.outputTokens = 200 // claudeTokens = 500
        daily.codexTokens = 150
        ctx.insert(daily)
        try ctx.save()

        let repo = OverviewRepository(modelContainer: container)
        let snapshot = await repo.loadSnapshot()

        #expect(snapshot.hasAnyData == true)
        #expect(snapshot.claudeTodayTokens == 500)
        #expect(snapshot.codexTodayTokens == 150)
        #expect(snapshot.heatmap.count == 1)
        #expect(snapshot.heatmap.first?.claudeTokens == 500)
        #expect(snapshot.heatmap.first?.codexTokens == 150)
    }

    @Test func loadSnapshotSplitsProjectsByCodexPrefix() async throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let today = Calendar.current.startOfDay(for: Date())

        let daily = DailyUsage(date: today)
        ctx.insert(daily)

        // Claude project (no Codex/ prefix)
        let claudeProject = ProjectUsage(projectName: "repo-A", tokens: 400, profileName: "work")
        claudeProject.dailyUsage = daily
        daily.projectBreakdowns.append(claudeProject)
        ctx.insert(claudeProject)

        // Codex project — prefixed profileName
        let codexProject = ProjectUsage(projectName: "repo-B", tokens: 250, profileName: "Codex/user@example.com")
        codexProject.dailyUsage = daily
        daily.projectBreakdowns.append(codexProject)
        ctx.insert(codexProject)

        try ctx.save()

        let repo = OverviewRepository(modelContainer: container)
        let snapshot = await repo.loadSnapshot()

        #expect(snapshot.todayProjects.count == 2)
        let repoA = snapshot.todayProjects.first { $0.name == "repo-A" }
        let repoB = snapshot.todayProjects.first { $0.name == "repo-B" }
        #expect(repoA?.claudeTokens == 400)
        #expect(repoA?.codexTokens == 0)
        #expect(repoB?.claudeTokens == 0)
        #expect(repoB?.codexTokens == 250)
    }

    @Test func loadSnapshotGroupsActiveSessionsBySource() async throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let s1 = SessionUsage(sessionId: "s-claude", projectName: "a", startTime: Date(), source: "claude")
        let s2 = SessionUsage(sessionId: "s-codex", projectName: "b", startTime: Date(), source: "codex")
        let s3 = SessionUsage(sessionId: "s-dead", projectName: "c", startTime: Date(), source: "claude")
        s3.isActive = false
        ctx.insert(s1)
        ctx.insert(s2)
        ctx.insert(s3)
        try ctx.save()

        let repo = OverviewRepository(modelContainer: container)
        let snapshot = await repo.loadSnapshot()

        #expect(snapshot.claudeActiveSessions.map(\.sessionId) == ["s-claude"])
        #expect(snapshot.codexActiveSessions.map(\.sessionId) == ["s-codex"])
    }

    @Test func loadHourlyTokensBySourceBucketsByHourAndSource() async throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let today = Calendar.current.startOfDay(for: Date())

        ctx.insert(HourlyUsage(date: today, hour: 9, tokens: 100, source: "claude"))
        ctx.insert(HourlyUsage(date: today, hour: 9, tokens: 50, source: "codex"))
        ctx.insert(HourlyUsage(date: today, hour: 14, tokens: 200, source: "claude"))
        // Other-day entry — must be ignored by the per-day predicate.
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!
        ctx.insert(HourlyUsage(date: yesterday, hour: 9, tokens: 999, source: "claude"))
        try ctx.save()

        let repo = OverviewRepository(modelContainer: container)
        let (claude, codex) = await repo.loadHourlyTokensBySource(for: today)

        #expect(claude.count == 24)
        #expect(claude[9] == 100)
        #expect(claude[14] == 200)
        #expect(codex[9] == 50)
        #expect(claude.reduce(0, +) == 300) // yesterday's 999 excluded
    }

    @Test func loadProjectsForSelectedDateIgnoresOtherDates() async throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let yesterday = cal.date(byAdding: .day, value: -1, to: today)!

        let todayDaily = DailyUsage(date: today)
        ctx.insert(todayDaily)
        let todayProject = ProjectUsage(projectName: "today-project", tokens: 100, profileName: "work")
        todayProject.dailyUsage = todayDaily
        todayDaily.projectBreakdowns.append(todayProject)
        ctx.insert(todayProject)

        let yesterdayDaily = DailyUsage(date: yesterday)
        ctx.insert(yesterdayDaily)
        let yesterdayProject = ProjectUsage(projectName: "yesterday-project", tokens: 999, profileName: "work")
        yesterdayProject.dailyUsage = yesterdayDaily
        yesterdayDaily.projectBreakdowns.append(yesterdayProject)
        ctx.insert(yesterdayProject)

        try ctx.save()

        let repo = OverviewRepository(modelContainer: container)
        let projects = await repo.loadProjects(for: today)

        #expect(projects.count == 1)
        #expect(projects.first?.name == "today-project")
        #expect(projects.first?.claudeTokens == 100)
    }
}
