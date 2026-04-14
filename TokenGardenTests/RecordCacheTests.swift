import Testing
import SwiftData
import Foundation
@testable import TokenGarden

/// Exercises RecordCache's day-keyed invalidation + session persistence.
@MainActor
struct RecordCacheTests {
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

    @Test func invalidateIfDayChangedClearsDayKeyedEntries() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let today = Calendar.current.startOfDay(for: Date())
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!

        let cache = RecordCache()
        cache.invalidateIfDayChanged(to: today)

        let daily = DailyUsage(date: today)
        ctx.insert(daily)
        cache.setDaily(daily)

        let hourly = HourlyUsage(date: today, hour: 10, tokens: 5, source: "claude")
        ctx.insert(hourly)
        cache.setHourly(hourly, forHour: 10, source: "claude")

        let profile = ProfileTokenUsage(profileName: "work", date: today, tokens: 5)
        ctx.insert(profile)
        cache.setProfileTokens(profile, forProfile: "work")

        let session = SessionUsage(sessionId: "s-1", projectName: "p", startTime: Date(), source: "claude")
        ctx.insert(session)
        cache.setSession(session)

        // Day rollover → day-keyed slots clear, sessions survive.
        cache.invalidateIfDayChanged(to: tomorrow)

        #expect(cache.daily == nil)
        #expect(cache.hourly.isEmpty)
        #expect(cache.profileTokens.isEmpty)
        #expect(cache.sessions.count == 1)
    }

    @Test func invalidateIsNoOpWhenSameDay() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let today = Calendar.current.startOfDay(for: Date())

        let cache = RecordCache()
        cache.invalidateIfDayChanged(to: today)

        let daily = DailyUsage(date: today)
        ctx.insert(daily)
        cache.setDaily(daily)

        cache.invalidateIfDayChanged(to: today)

        #expect(cache.daily === daily)
    }

    @Test func clearWipesEverything() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let session = SessionUsage(sessionId: "s-1", projectName: "p", startTime: Date(), source: "claude")
        ctx.insert(session)

        let cache = RecordCache()
        cache.setSession(session)
        cache.clear()

        #expect(cache.sessions.isEmpty)
    }
}
