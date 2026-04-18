import Foundation

// MARK: - View-model types

struct BreakdownSummary: Sendable {
    let window: TimeWindow
    let mcp: [MCPServerRow]
    let toolTotals: [ToolRow]
    let skills: SkillsBreakdown
    let hooks: [HookRow]
    let claudeMd: ClaudeMdBreakdown
    let generatedAt: Date
}

enum TimeWindow: String, Sendable, CaseIterable, Identifiable {
    case day, week, month
    var id: String { rawValue }
    var label: String {
        switch self {
        case .day: return "Today"
        case .week: return "This week"
        case .month: return "This month"
        }
    }
}

struct MCPServerRow: Sendable, Identifiable {
    var id: String { server }
    let server: String
    let calls: Int
    let totalInputChars: Int
    /// Per-call average char footprint — useful for spotting unusually
    /// chatty tools that are worth prompt-shrinking.
    var averageInputChars: Int { calls > 0 ? totalInputChars / calls : 0 }
    /// Estimated tokens (fallback = chars / 3.5). UI may replace with
    /// exact count from TokenCounter.
    var approxTokens: Int { max(0, Int(Double(totalInputChars) / 3.5)) }
}

struct ToolRow: Sendable, Identifiable {
    var id: String { name }
    let name: String
    let calls: Int
    let totalInputChars: Int
}

struct SkillsBreakdown: Sendable {
    /// All installed skills, regardless of invocation. Ordered by body size
    /// descending — heaviest first.
    let installed: [SkillInfo]
    /// Skills invoked via the Skill tool in the window. Keyed by skill name.
    let invocations: [SkillInvocationRow]
    /// Names present in `installed` but never seen in `invocations` —
    /// candidates for removal.
    let uninvokedNames: [String]
    /// Sum of `"<name>: <description>"` chars across all installed skills.
    /// This is the **baseline cost** — what every session pays just by
    /// having these skills discoverable.
    var baselineChars: Int { installed.reduce(0) { $0 + $1.frontmatterChars } }
    /// Sum of all invoked skill body chars in the window (actual load).
    var invokedBodyChars: Int { invocations.reduce(0) { $0 + $1.bodyChars } }
}

struct SkillInvocationRow: Sendable, Identifiable {
    var id: String { name }
    let name: String
    let calls: Int
    /// Chars of arguments passed to the Skill tool (small).
    let argChars: Int
    /// Chars of the skill's SKILL.md body (what CC loads into context
    /// on each invocation). 0 if we couldn't find a matching SkillInfo.
    let bodyChars: Int
}

struct HookRow: Sendable, Identifiable {
    var id: String { category.rawValue }
    let category: HookCategory
    let blocks: Int
    let totalChars: Int
    var approxTokens: Int { max(0, Int(Double(totalChars) / 3.5)) }
}

struct ClaudeMdBreakdown: Sendable {
    let layers: [ClaudeMdLayer]
    let totalExpandedChars: Int
    let cyclesDetected: [String]
    let missingReferences: [String]
    var approxTokens: Int { max(0, Int(Double(totalExpandedChars) / 3.5)) }
}

// MARK: - Aggregator

/// Pure aggregation — takes raw events + static scan data and produces
/// a single `BreakdownSummary` view model. No I/O, no mutation, no deps
/// on SwiftData. Safe to call repeatedly; expected cost is O(events).
struct BreakdownAggregator {
    /// Aggregate events into a summary filtered to `window`.
    /// `now` is injected for deterministic testing.
    static func aggregate(
        window: TimeWindow,
        toolUses: [ToolUseEvent],
        hookBlocks: [HookBlockEvent],
        installedSkills: [SkillInfo],
        claudeMd: ClaudeMdReport,
        now: Date = Date()
    ) -> BreakdownSummary {
        let cutoff = windowStart(for: window, from: now)
        let filteredTools = toolUses.filter { $0.timestamp >= cutoff }
        let filteredHooks = hookBlocks.filter { $0.timestamp >= cutoff }

        let mcp = aggregateMCP(events: filteredTools)
        let toolTotals = aggregateTools(events: filteredTools)
        let skillsBreak = aggregateSkills(
            events: filteredTools,
            installed: installedSkills
        )
        let hooks = aggregateHooks(events: filteredHooks)
        let cm = ClaudeMdBreakdown(
            layers: claudeMd.layers,
            totalExpandedChars: claudeMd.totalFlatText.count,
            cyclesDetected: claudeMd.cyclesDetected,
            missingReferences: claudeMd.missingReferences
        )
        return BreakdownSummary(
            window: window,
            mcp: mcp,
            toolTotals: toolTotals,
            skills: skillsBreak,
            hooks: hooks,
            claudeMd: cm,
            generatedAt: now
        )
    }

    static func windowStart(for window: TimeWindow, from now: Date) -> Date {
        var calendar = Calendar.current
        calendar.firstWeekday = 2  // Monday (matches existing PopoverView)
        switch window {
        case .day:
            return calendar.startOfDay(for: now)
        case .week:
            return calendar
                .dateComponents([.calendar, .yearForWeekOfYear, .weekOfYear], from: now)
                .date ?? calendar.startOfDay(for: now)
        case .month:
            let comps = calendar.dateComponents([.year, .month], from: now)
            return calendar.date(from: comps) ?? calendar.startOfDay(for: now)
        }
    }

    // MARK: - Per-dimension aggregation

    static func aggregateMCP(events: [ToolUseEvent]) -> [MCPServerRow] {
        var callsByServer: [String: Int] = [:]
        var charsByServer: [String: Int] = [:]
        for e in events where e.category == .mcp {
            guard let server = e.mcpServer else { continue }
            callsByServer[server, default: 0] += 1
            charsByServer[server, default: 0] += e.inputChars
        }
        return callsByServer.keys.sorted().map { key in
            MCPServerRow(
                server: key,
                calls: callsByServer[key] ?? 0,
                totalInputChars: charsByServer[key] ?? 0
            )
        }.sorted { $0.calls > $1.calls }
    }

    static func aggregateTools(events: [ToolUseEvent]) -> [ToolRow] {
        var callsByName: [String: Int] = [:]
        var charsByName: [String: Int] = [:]
        for e in events {
            callsByName[e.toolName, default: 0] += 1
            charsByName[e.toolName, default: 0] += e.inputChars
        }
        return callsByName.keys.map { key in
            ToolRow(
                name: key,
                calls: callsByName[key] ?? 0,
                totalInputChars: charsByName[key] ?? 0
            )
        }.sorted { $0.calls > $1.calls }
    }

    static func aggregateSkills(
        events: [ToolUseEvent],
        installed: [SkillInfo]
    ) -> SkillsBreakdown {
        var calls: [String: Int] = [:]
        var chars: [String: Int] = [:]
        for e in events where e.category == .skill {
            guard let name = e.skillName else { continue }
            calls[name, default: 0] += 1
            chars[name, default: 0] += e.inputChars
        }
        let installedByName = Dictionary(uniqueKeysWithValues: installed.map { ($0.name, $0) })
        let invocations = calls.keys.map { name in
            SkillInvocationRow(
                name: name,
                calls: calls[name] ?? 0,
                argChars: chars[name] ?? 0,
                bodyChars: installedByName[name]?.bodyChars ?? 0
            )
        }.sorted { $0.calls > $1.calls }

        let invokedNames = Set(calls.keys)
        let uninvoked = installed
            .map(\.name)
            .filter { !invokedNames.contains($0) }
            .sorted()

        return SkillsBreakdown(
            installed: installed,
            invocations: invocations,
            uninvokedNames: uninvoked
        )
    }

    static func aggregateHooks(events: [HookBlockEvent]) -> [HookRow] {
        var blocks: [HookCategory: Int] = [:]
        var chars: [HookCategory: Int] = [:]
        for e in events {
            blocks[e.category, default: 0] += 1
            chars[e.category, default: 0] += e.body.count
        }
        return blocks.keys.map { cat in
            HookRow(
                category: cat,
                blocks: blocks[cat] ?? 0,
                totalChars: chars[cat] ?? 0
            )
        }.sorted { $0.blocks > $1.blocks }
    }
}
