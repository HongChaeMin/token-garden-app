import Foundation
import SwiftData

/// In-memory lookup cache for `TokenDataStore.record(_:)` / `recordCodex(_:)`.
///
/// Day-keyed entries (`daily`, `hourly`, `profileTokens`) invalidate on day
/// rollover. Session entries persist — sessionIds are stable across the day.
/// Holds live `@Model` references: we skip the lookup, not the write.
@MainActor
final class RecordCache {
    private(set) var day: Date = .distantPast
    private(set) var daily: DailyUsage?
    private(set) var hourly: [HourlyKey: HourlyUsage] = [:]
    private(set) var profileTokens: [String: ProfileTokenUsage] = [:]
    private(set) var sessions: [String: SessionUsage] = [:]

    struct HourlyKey: Hashable {
        let hour: Int
        let source: String
    }

    /// Clear the day-keyed buckets when a new calendar day is encountered.
    /// Session cache is untouched — sessionIds don't roll over at midnight.
    func invalidateIfDayChanged(to newDay: Date) {
        guard newDay != day else { return }
        day = newDay
        daily = nil
        hourly.removeAll(keepingCapacity: true)
        profileTokens.removeAll(keepingCapacity: true)
    }

    func setDaily(_ daily: DailyUsage) {
        self.daily = daily
    }

    func setHourly(_ usage: HourlyUsage, forHour hour: Int, source: String) {
        hourly[HourlyKey(hour: hour, source: source)] = usage
    }

    func setProfileTokens(_ usage: ProfileTokenUsage, forProfile profileName: String) {
        profileTokens[profileName] = usage
    }

    func setSession(_ session: SessionUsage) {
        sessions[session.sessionId] = session
    }

    /// Reset everything — e.g. after the underlying ModelContainer is replaced.
    func clear() {
        day = .distantPast
        daily = nil
        hourly.removeAll(keepingCapacity: true)
        profileTokens.removeAll(keepingCapacity: true)
        sessions.removeAll(keepingCapacity: true)
    }
}
