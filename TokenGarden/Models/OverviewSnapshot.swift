import Foundation

/// Sendable value-type snapshot of everything the Overview tab renders.
///
/// Contains data for BOTH sources (Claude + Codex) so switching the source
/// toggle never triggers a refetch. The view layer only reads these values —
/// SwiftData entities never leak into the UI layer, which means relationship
/// faulting is confined to the repository actor.
struct OverviewSnapshot: Sendable, Equatable {
    // Per-source token totals for stats tiles
    var claudeTodayTokens: Int
    var claudeWeekTokens: Int
    var claudeMonthTokens: Int
    var codexTodayTokens: Int
    var codexWeekTokens: Int
    var codexMonthTokens: Int

    // Heatmap rows carry both sources so the view picks whichever the user toggled.
    var heatmap: [HeatmapDay]

    // Today's hourly tokens by source (24 slots, indexed by hour of day).
    var claudeHourlyToday: [Int]
    var codexHourlyToday: [Int]

    // Project breakdowns by time range, with both source token counts on each row.
    var todayProjects: [ProjectBreakdown]
    var weekProjects: [ProjectBreakdown]
    var monthProjects: [ProjectBreakdown]

    // Active sessions by source.
    var claudeActiveSessions: [SessionSummary]
    var codexActiveSessions: [SessionSummary]

    var hasAnyData: Bool

    static let empty = OverviewSnapshot(
        claudeTodayTokens: 0, claudeWeekTokens: 0, claudeMonthTokens: 0,
        codexTodayTokens: 0, codexWeekTokens: 0, codexMonthTokens: 0,
        heatmap: [],
        claudeHourlyToday: Array(repeating: 0, count: 24),
        codexHourlyToday: Array(repeating: 0, count: 24),
        todayProjects: [], weekProjects: [], monthProjects: [],
        claudeActiveSessions: [], codexActiveSessions: [],
        hasAnyData: false
    )
}

/// Single heatmap day — carries both source totals so the view can pick.
struct HeatmapDay: Sendable, Equatable, Hashable {
    let date: Date
    let claudeTokens: Int
    let codexTokens: Int
}

/// Project aggregate for a time range, with both source tokens.
struct ProjectBreakdown: Sendable, Equatable, Hashable, Identifiable {
    let name: String
    let claudeTokens: Int
    let codexTokens: Int

    var id: String { name }
    var totalTokens: Int { claudeTokens + codexTokens }
}

/// Active session summary — detached from SwiftData's `SessionUsage`.
struct SessionSummary: Sendable, Equatable, Hashable, Identifiable {
    let sessionId: String
    let projectName: String
    let startTime: Date
    let lastTime: Date
    let totalTokens: Int

    var id: String { sessionId }
}
