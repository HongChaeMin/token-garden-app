import Testing
import SwiftData
import Foundation
@testable import TokenGarden

@Test @MainActor func recordTokenEvent() async throws {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(
        for: DailyUsage.self,
        ProjectUsage.self,
        SessionUsage.self,
        HourlyUsage.self,
        ProfileTokenUsage.self,
        configurations: config
    )
    let store = TokenDataStore(modelContainer: container)

    let event = TokenEvent(
        timestamp: Date(),
        inputTokens: 100,
        outputTokens: 50,
        cacheCreationTokens: 200,
        cacheReadTokens: 30,
        model: "claude-opus-4-6",
        projectName: "my-project",
        sessionId: "session-1",
        source: "claude-code"
    )

    store.record(event)
    store.flush()

    let context = ModelContext(container)
    let descriptor = FetchDescriptor<DailyUsage>()
    let results = try context.fetch(descriptor)
    #expect(results.count == 1)
    #expect(results[0].inputTokens == 100)
    #expect(results[0].outputTokens == 50)
    #expect(results[0].cacheCreationTokens == 200)
    #expect(results[0].projectBreakdowns.count == 1)
    #expect(results[0].projectBreakdowns[0].projectName == "my-project")
}

@Test @MainActor func recordMultipleEventsAccumulate() async throws {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(
        for: DailyUsage.self,
        ProjectUsage.self,
        SessionUsage.self,
        HourlyUsage.self,
        ProfileTokenUsage.self,
        configurations: config
    )
    let store = TokenDataStore(modelContainer: container)

    let event1 = TokenEvent(
        timestamp: Date(), inputTokens: 100, outputTokens: 50,
        cacheCreationTokens: 0, cacheReadTokens: 0,
        model: "claude-opus-4-6", projectName: "project-a", sessionId: "session-1", source: "claude-code"
    )
    let event2 = TokenEvent(
        timestamp: Date(), inputTokens: 200, outputTokens: 100,
        cacheCreationTokens: 0, cacheReadTokens: 0,
        model: "claude-opus-4-6", projectName: "project-a", sessionId: "session-1", source: "claude-code"
    )

    store.record(event1)
    store.record(event2)
    store.flush()

    let context = ModelContext(container)
    let descriptor = FetchDescriptor<DailyUsage>()
    let results = try context.fetch(descriptor)
    #expect(results.count == 1)
    #expect(results[0].inputTokens == 300)
    #expect(results[0].outputTokens == 150)
    #expect(results[0].projectBreakdowns.count == 1)
    #expect(results[0].projectBreakdowns[0].tokens == 450)
}

@Test @MainActor func fetchDailyUsagesForRange() async throws {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(
        for: DailyUsage.self,
        ProjectUsage.self,
        SessionUsage.self,
        HourlyUsage.self,
        ProfileTokenUsage.self,
        configurations: config
    )
    let store = TokenDataStore(modelContainer: container)

    let calendar = Calendar.current
    let today = calendar.startOfDay(for: Date())
    let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!

    let event1 = TokenEvent(
        timestamp: today, inputTokens: 100, outputTokens: 50,
        cacheCreationTokens: 0, cacheReadTokens: 0,
        model: nil, projectName: nil, sessionId: nil, source: "claude-code"
    )
    let event2 = TokenEvent(
        timestamp: yesterday, inputTokens: 200, outputTokens: 100,
        cacheCreationTokens: 0, cacheReadTokens: 0,
        model: nil, projectName: nil, sessionId: nil, source: "claude-code"
    )

    store.record(event1)
    store.record(event2)
    store.flush()

    let results = store.fetchDailyUsages(from: yesterday, to: today)
    #expect(results.count == 2)
}

@Test @MainActor func recordSessionUsage() async throws {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(
        for: DailyUsage.self,
        ProjectUsage.self,
        SessionUsage.self,
        HourlyUsage.self,
        ProfileTokenUsage.self,
        configurations: config
    )
    let store = TokenDataStore(modelContainer: container)

    let event1 = TokenEvent(
        timestamp: Date(), inputTokens: 100, outputTokens: 50,
        cacheCreationTokens: 0, cacheReadTokens: 0,
        model: "claude-opus-4-6", projectName: "my-project", sessionId: "session-abc", source: "claude-code"
    )
    let event2 = TokenEvent(
        timestamp: Date(), inputTokens: 200, outputTokens: 100,
        cacheCreationTokens: 0, cacheReadTokens: 0,
        model: "claude-opus-4-6", projectName: "my-project", sessionId: "session-abc", source: "claude-code"
    )

    store.record(event1)
    store.record(event2)
    store.flush()

    let context = ModelContext(container)
    let descriptor = FetchDescriptor<SessionUsage>()
    let sessions = try context.fetch(descriptor)
    #expect(sessions.count == 1)
    #expect(sessions[0].sessionId == "session-abc")
    #expect(sessions[0].totalTokens == 450)
    #expect(sessions[0].projectName == "my-project")
}

@Test @MainActor func recordCodexEventUsesUpdatedAtForDailyAndHourlyUsage() async throws {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(
        for: DailyUsage.self,
        ProjectUsage.self,
        SessionUsage.self,
        HourlyUsage.self,
        ProfileTokenUsage.self,
        configurations: config
    )
    let store = TokenDataStore(modelContainer: container)

    let timestamp = Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 7, hour: 15, minute: 30))!
    let event = CodexThreadEvent(
        threadId: "thread-1",
        updatedAt: timestamp,
        tokensUsed: 120,
        projectName: "token-garden-app",
        model: "gpt-5.4",
        accountEmail: "dev@example.com"
    )

    store.recordCodex(event)
    store.flush()

    let context = ModelContext(container)
    let dailyResults = try context.fetch(FetchDescriptor<DailyUsage>())
    #expect(dailyResults.count == 1)
    #expect(dailyResults[0].codexTokens == 120)
    #expect(dailyResults[0].totalTokens == 120)
    #expect(dailyResults[0].projectBreakdowns.count == 1)
    #expect(dailyResults[0].projectBreakdowns[0].profileName == "Codex/dev@example.com")

    let hourlyBuckets = store.fetchHourlyTokens(for: timestamp)
    #expect(hourlyBuckets[15] == 120)
    #expect(store.fetchHourlyTokens(for: timestamp, source: "codex")[15] == 120)
    #expect(store.fetchHourlyTokens(for: timestamp, source: "claude")[15] == 0)

    let sessions = try context.fetch(FetchDescriptor<SessionUsage>())
    #expect(sessions.count == 1)
    #expect(sessions[0].source == "codex")
    #expect(sessions[0].isActive == true)
}
