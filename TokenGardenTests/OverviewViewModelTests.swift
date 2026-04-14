import Testing
import SwiftData
import Foundation
@testable import TokenGarden

/// Exercises OverviewViewModel — verifies it is isolated to the main actor,
/// loads in the background via OverviewRepository, and fans out selectedDate
/// changes correctly.
@MainActor
struct OverviewViewModelTests {
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

    @Test func initialStateIsLoadingEmpty() throws {
        let container = try makeContainer()
        let vm = OverviewViewModel(modelContainer: container)

        #expect(vm.isInitialLoading == true)
        #expect(vm.snapshot == .empty)
        #expect(vm.selectedDate == nil)
        #expect(vm.selectedDayProjects == nil)
    }

    @Test func startFlipsLoadingFalseAfterRepoCompletes() async throws {
        let container = try makeContainer()
        let vm = OverviewViewModel(modelContainer: container)

        vm.start()
        await vm.awaitPendingTasks()

        #expect(vm.isInitialLoading == false)
    }

    @Test func startLoadsSnapshotFromDatabase() async throws {
        let container = try makeContainer()
        let today = Calendar.current.startOfDay(for: Date())
        let daily = DailyUsage(date: today)
        daily.inputTokens = 400
        daily.outputTokens = 100
        daily.codexTokens = 75
        container.mainContext.insert(daily)
        try container.mainContext.save()

        let vm = OverviewViewModel(modelContainer: container)
        vm.start()
        await vm.awaitPendingTasks()

        #expect(vm.snapshot.claudeTodayTokens == 500)
        #expect(vm.snapshot.codexTodayTokens == 75)
        #expect(vm.snapshot.hasAnyData == true)
    }

    @Test func selectedDateTriggersProjectAndHourlyLoad() async throws {
        let container = try makeContainer()
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())

        let daily = DailyUsage(date: today)
        container.mainContext.insert(daily)
        let project = ProjectUsage(projectName: "selected-project", tokens: 123, profileName: "work")
        project.dailyUsage = daily
        daily.projectBreakdowns.append(project)
        container.mainContext.insert(project)
        container.mainContext.insert(HourlyUsage(date: today, hour: 10, tokens: 77, source: "claude"))
        try container.mainContext.save()

        let vm = OverviewViewModel(modelContainer: container)
        vm.start()
        await vm.awaitPendingTasks()

        vm.selectedDate = today
        await vm.awaitPendingTasks()

        #expect(vm.selectedDayProjects?.count == 1)
        #expect(vm.selectedDayProjects?.first?.name == "selected-project")
        #expect(vm.activeClaudeHourlyTokens[10] == 77)
    }

    @Test func selectedDateNilResetsDayView() async throws {
        let container = try makeContainer()
        let today = Calendar.current.startOfDay(for: Date())

        let daily = DailyUsage(date: today)
        daily.inputTokens = 10
        container.mainContext.insert(daily)
        try container.mainContext.save()

        let vm = OverviewViewModel(modelContainer: container)
        vm.start()
        await vm.awaitPendingTasks()

        vm.selectedDate = today
        await vm.awaitPendingTasks()
        #expect(vm.selectedDayProjects != nil)

        vm.selectedDate = nil

        // After clearing, selectedDayProjects is reset synchronously
        // and activeHourlyTokens returns to today's snapshot values.
        #expect(vm.selectedDayProjects == nil)
        #expect(vm.activeClaudeHourlyTokens == vm.snapshot.claudeHourlyToday)
    }
}
