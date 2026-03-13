import Testing
import SwiftData
import Foundation
@testable import TokenGarden

@Test @MainActor func recordTokenEvent() async throws {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: DailyUsage.self, ProjectUsage.self, configurations: config)
    let store = TokenDataStore(modelContainer: container)

    let event = TokenEvent(
        timestamp: Date(),
        inputTokens: 100,
        outputTokens: 50,
        cacheCreationTokens: 200,
        cacheReadTokens: 30,
        model: "claude-opus-4-6",
        projectName: "my-project",
        source: "claude-code"
    )

    store.record(event)

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
    let container = try ModelContainer(for: DailyUsage.self, ProjectUsage.self, configurations: config)
    let store = TokenDataStore(modelContainer: container)

    let event1 = TokenEvent(
        timestamp: Date(), inputTokens: 100, outputTokens: 50,
        cacheCreationTokens: 0, cacheReadTokens: 0,
        model: "claude-opus-4-6", projectName: "project-a", source: "claude-code"
    )
    let event2 = TokenEvent(
        timestamp: Date(), inputTokens: 200, outputTokens: 100,
        cacheCreationTokens: 0, cacheReadTokens: 0,
        model: "claude-opus-4-6", projectName: "project-a", source: "claude-code"
    )

    store.record(event1)
    store.record(event2)

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
    let container = try ModelContainer(for: DailyUsage.self, ProjectUsage.self, configurations: config)
    let store = TokenDataStore(modelContainer: container)

    let calendar = Calendar.current
    let today = calendar.startOfDay(for: Date())
    let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!

    let event1 = TokenEvent(
        timestamp: today, inputTokens: 100, outputTokens: 50,
        cacheCreationTokens: 0, cacheReadTokens: 0,
        model: nil, projectName: nil, source: "claude-code"
    )
    let event2 = TokenEvent(
        timestamp: yesterday, inputTokens: 200, outputTokens: 100,
        cacheCreationTokens: 0, cacheReadTokens: 0,
        model: nil, projectName: nil, source: "claude-code"
    )

    store.record(event1)
    store.record(event2)

    let results = store.fetchDailyUsages(from: yesterday, to: today)
    #expect(results.count == 2)
}
