import Foundation
import SwiftData

/// In-memory cache of the SwiftData entities touched by `TokenDataStore.record(_:)`
/// and `recordCodex(_:)`. Each incoming event used to run 3–4 `fetch` calls just
/// to locate "the DailyUsage for today / the ProfileTokenUsage for this profile /
/// the SessionUsage for this sessionId". During log backfill that ran hundreds
/// of times in a tight loop and was the biggest cause of main-thread hangs.
///
/// The cache keeps live `@Model` references so mutations still flow back to the
/// ModelContext — we're skipping the lookup, not the write.
///
/// Day-keyed entries (`daily`, `hourly`, `profileTokens`) invalidate on day
/// rollover. Session entries live as long as the app process because sessionIds
/// are stable.
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
