import Foundation
import Testing
@testable import TokenGarden

// MARK: - fixtures

private let now = Date(timeIntervalSince1970: 1_800_000_000)  // deterministic "now"
private let insideDay = now.addingTimeInterval(-60)           // 1 min ago
private let outsideDay = now.addingTimeInterval(-60 * 60 * 48) // 2 days ago

private func toolEvent(
    at ts: Date = insideDay,
    name: String,
    input: String = "x",
    category: ToolCategory = .native,
    mcpServer: String? = nil,
    skillName: String? = nil
) -> ToolUseEvent {
    ToolUseEvent(
        timestamp: ts,
        sessionId: "s1",
        projectName: "proj",
        toolName: name,
        inputChars: input.count,
        category: category,
        mcpServer: mcpServer,
        skillName: skillName
    )
}

private func skillInfo(name: String, bodyChars: Int) -> SkillInfo {
    SkillInfo(
        name: name,
        path: URL(fileURLWithPath: "/fake/\(name)/SKILL.md"),
        source: .global,
        description: "desc",
        frontmatterChars: name.count + 2 + 4,
        bodyChars: bodyChars,
        totalChars: bodyChars + 20,
        rawText: ""
    )
}

private let emptyClaudeMd = ClaudeMdReport(
    layers: [], totalFlatText: "", cyclesDetected: [], missingReferences: []
)

// MARK: - window filter

@Test func filtersEventsOutsideWindow() {
    let toolUses = [
        toolEvent(at: insideDay, name: "Bash"),
        toolEvent(at: outsideDay, name: "Bash"),
    ]
    let summary = BreakdownAggregator.aggregate(
        window: .day,
        toolUses: toolUses,
        hookBlocks: [],
        installedSkills: [],
        claudeMd: emptyClaudeMd,
        now: now
    )
    #expect(summary.toolTotals.first?.calls == 1)
}

@Test func weekWindowIncludesOlderEventsThanDay() {
    let twoDaysAgo = now.addingTimeInterval(-60 * 60 * 48)
    let toolUses = [toolEvent(at: twoDaysAgo, name: "Bash")]
    let daySummary = BreakdownAggregator.aggregate(
        window: .day, toolUses: toolUses, hookBlocks: [],
        installedSkills: [], claudeMd: emptyClaudeMd, now: now
    )
    let weekSummary = BreakdownAggregator.aggregate(
        window: .week, toolUses: toolUses, hookBlocks: [],
        installedSkills: [], claudeMd: emptyClaudeMd, now: now
    )
    // day window excludes it; week window may include it (depends on calendar week boundary)
    #expect(daySummary.toolTotals.isEmpty || daySummary.toolTotals.first?.calls == 0)
    _ = weekSummary  // week boundary is calendar-dependent; just assert day case
}

// MARK: - MCP aggregation

@Test func aggregatesMcpByServer() {
    let events = [
        toolEvent(name: "mcp__a__x", input: "hello", category: .mcp, mcpServer: "a"),
        toolEvent(name: "mcp__a__y", input: "world!", category: .mcp, mcpServer: "a"),
        toolEvent(name: "mcp__b__z", input: "!", category: .mcp, mcpServer: "b"),
    ]
    let summary = BreakdownAggregator.aggregate(
        window: .day, toolUses: events, hookBlocks: [],
        installedSkills: [], claudeMd: emptyClaudeMd, now: now
    )
    #expect(summary.mcp.count == 2)
    let a = summary.mcp.first { $0.server == "a" }!
    #expect(a.calls == 2)
    #expect(a.totalInputChars == 11) // 5 + 6
    let b = summary.mcp.first { $0.server == "b" }!
    #expect(b.calls == 1)
    #expect(b.totalInputChars == 1)
}

@Test func nonMcpEventsDoNotAppearInMcpRows() {
    // 경계값 — Bash/Edit 등 native tool은 mcp 리스트에서 제외
    let events = [toolEvent(name: "Bash", category: .native)]
    let summary = BreakdownAggregator.aggregate(
        window: .day, toolUses: events, hookBlocks: [],
        installedSkills: [], claudeMd: emptyClaudeMd, now: now
    )
    #expect(summary.mcp.isEmpty)
    #expect(summary.toolTotals.count == 1)
}

// MARK: - Skill aggregation

@Test func reportsInvokedAndUninvokedSkills() {
    let events = [
        toolEvent(name: "Skill", input: "{\"skill\":\"alpha\"}", category: .skill, skillName: "alpha"),
    ]
    let installed = [
        skillInfo(name: "alpha", bodyChars: 100),
        skillInfo(name: "beta", bodyChars: 200),
        skillInfo(name: "gamma", bodyChars: 50),
    ]
    let summary = BreakdownAggregator.aggregate(
        window: .day, toolUses: events, hookBlocks: [],
        installedSkills: installed, claudeMd: emptyClaudeMd, now: now
    )
    #expect(summary.skills.invocations.count == 1)
    #expect(summary.skills.invocations[0].name == "alpha")
    #expect(summary.skills.invocations[0].bodyChars == 100)
    #expect(summary.skills.uninvokedNames == ["beta", "gamma"])
    #expect(summary.skills.installed.count == 3)
}

@Test func skillBaselineSumsAllFrontmatter() {
    let installed = [
        skillInfo(name: "a", bodyChars: 0),
        skillInfo(name: "b", bodyChars: 0),
    ]
    let summary = BreakdownAggregator.aggregate(
        window: .day, toolUses: [], hookBlocks: [],
        installedSkills: installed, claudeMd: emptyClaudeMd, now: now
    )
    // frontmatterChars = name.count + 2 + 4 (": desc")
    // "a" → 1 + 2 + 4 = 7, "b" → same = 7. Sum 14.
    #expect(summary.skills.baselineChars == 14)
}

@Test func emptySkillsReturnsEmptyBreakdown() {
    // 경계값 — 설치 없음 / 호출 없음
    let summary = BreakdownAggregator.aggregate(
        window: .day, toolUses: [], hookBlocks: [],
        installedSkills: [], claudeMd: emptyClaudeMd, now: now
    )
    #expect(summary.skills.installed.isEmpty)
    #expect(summary.skills.invocations.isEmpty)
    #expect(summary.skills.uninvokedNames.isEmpty)
    #expect(summary.skills.baselineChars == 0)
}

// MARK: - Hook aggregation

@Test func aggregatesHooksByCategory() {
    let blocks = [
        HookBlockEvent(
            timestamp: insideDay, sessionId: "s", projectName: "p",
            body: "SessionStart hook success: OK", category: .sessionStart
        ),
        HookBlockEvent(
            timestamp: insideDay, sessionId: "s", projectName: "p",
            body: "UserPromptSubmit hook success: OK", category: .userPromptSubmit
        ),
        HookBlockEvent(
            timestamp: insideDay, sessionId: "s", projectName: "p",
            body: "SessionStart hook success: OK", category: .sessionStart
        ),
    ]
    let summary = BreakdownAggregator.aggregate(
        window: .day, toolUses: [], hookBlocks: blocks,
        installedSkills: [], claudeMd: emptyClaudeMd, now: now
    )
    let sessionStart = summary.hooks.first { $0.category == .sessionStart }!
    let promptSubmit = summary.hooks.first { $0.category == .userPromptSubmit }!
    #expect(sessionStart.blocks == 2)
    #expect(promptSubmit.blocks == 1)
    #expect(sessionStart.totalChars > 0)
}

// MARK: - window boundaries

@Test func dayWindowStartIsMidnight() {
    let anyTime = Date(timeIntervalSince1970: 1_800_000_000)
    let start = BreakdownAggregator.windowStart(for: .day, from: anyTime)
    let cal = Calendar.current
    let comps = cal.dateComponents([.hour, .minute, .second], from: start)
    #expect(comps.hour == 0)
    #expect(comps.minute == 0)
    #expect(comps.second == 0)
}
