import Foundation
import Testing
@testable import TokenGarden

// MARK: - tool_use parsing

@Test func parsesMcpToolUseWithServerName() {
    let parser = ClaudeCodeLogParser()
    let line = """
    {"type":"assistant","timestamp":"2026-04-18T10:00:00.000Z","sessionId":"abc",\
    "cwd":"/Users/x/proj","message":{"model":"claude-opus-4-7","content":[\
    {"type":"tool_use","name":"mcp__plugin_rtb_rtb-db__query_db","input":{"sql":"SELECT 1"}}\
    ]}}
    """
    let events = parser.parseToolUses(logLine: line)
    #expect(events.count == 1)
    #expect(events[0].toolName == "mcp__plugin_rtb_rtb-db__query_db")
    #expect(events[0].category == .mcp)
    #expect(events[0].mcpServer == "plugin_rtb_rtb-db")
    #expect(events[0].skillName == nil)
    #expect(events[0].inputChars > 0)
    #expect(events[0].sessionId == "abc")
    #expect(events[0].projectName == "proj")
}

@Test func parsesSkillToolUseWithSkillName() {
    let parser = ClaudeCodeLogParser()
    let line = """
    {"type":"assistant","timestamp":"2026-04-18T10:00:00.000Z","message":{\
    "content":[{"type":"tool_use","name":"Skill","input":{"skill":"cc-usage-analyze","args":"test"}}]\
    }}
    """
    let events = parser.parseToolUses(logLine: line)
    #expect(events.count == 1)
    #expect(events[0].category == .skill)
    #expect(events[0].skillName == "cc-usage-analyze")
    #expect(events[0].mcpServer == nil)
}

@Test func parsesNativeToolUse() {
    let parser = ClaudeCodeLogParser()
    let line = """
    {"type":"assistant","timestamp":"2026-04-18T10:00:00.000Z","message":{\
    "content":[{"type":"tool_use","name":"Bash","input":{"command":"ls"}}]}}
    """
    let events = parser.parseToolUses(logLine: line)
    #expect(events.count == 1)
    #expect(events[0].category == .native)
    #expect(events[0].mcpServer == nil)
    #expect(events[0].skillName == nil)
}

@Test func parsesMultipleToolUsesFromSingleMessage() {
    let parser = ClaudeCodeLogParser()
    let line = """
    {"type":"assistant","timestamp":"2026-04-18T10:00:00.000Z","message":{\
    "content":[\
    {"type":"text","text":"thinking..."},\
    {"type":"tool_use","name":"Read","input":{"path":"a.txt"}},\
    {"type":"tool_use","name":"Edit","input":{"path":"a.txt","old":"x","new":"y"}}\
    ]}}
    """
    let events = parser.parseToolUses(logLine: line)
    #expect(events.count == 2)
    #expect(events[0].toolName == "Read")
    #expect(events[1].toolName == "Edit")
}

@Test func ignoresNonAssistantLines() {
    // 경계값 — user/system 라인은 무시
    let parser = ClaudeCodeLogParser()
    let userLine = """
    {"type":"user","message":{"content":[{"type":"tool_use","name":"Bash"}]}}
    """
    #expect(parser.parseToolUses(logLine: userLine).isEmpty)
}

@Test func handlesMalformedJsonGracefully() {
    // 에러 케이스 — crash 안 함
    let parser = ClaudeCodeLogParser()
    #expect(parser.parseToolUses(logLine: "not json").isEmpty)
    #expect(parser.parseToolUses(logLine: "").isEmpty)
}

// MARK: - system-reminder parsing

@Test func parsesSystemReminderBlocks() {
    let parser = ClaudeCodeLogParser()
    let line = """
    {"type":"user","timestamp":"2026-04-18T10:00:00.000Z","message":{\
    "content":"intro <system-reminder>hook-body-1</system-reminder> mid <system-reminder>hook-body-2</system-reminder> end"\
    }}
    """
    let events = parser.parseHookBlocks(logLine: line)
    #expect(events.count == 2)
    #expect(events[0].body == "hook-body-1")
    #expect(events[1].body == "hook-body-2")
}

@Test func handlesMultilineSystemReminder() {
    let parser = ClaudeCodeLogParser()
    let line = #"{"type":"user","message":{"content":"<system-reminder>line1\nline2\nline3</system-reminder>"}}"#
    let events = parser.parseHookBlocks(logLine: line)
    #expect(events.count == 1)
    #expect(events[0].body.contains("line1"))
    #expect(events[0].body.contains("line3"))
}

@Test func emptyMessageReturnsNoHookBlocks() {
    // 경계값 — 빈 content
    let parser = ClaudeCodeLogParser()
    let line = #"{"type":"user","message":{"content":""}}"#
    #expect(parser.parseHookBlocks(logLine: line).isEmpty)
}

@Test func hookCategorizationDetectsSessionStart() {
    #expect(ClaudeCodeLogParser.categorizeHook(body: "SessionStart hook success: ABC") == .sessionStart)
    #expect(ClaudeCodeLogParser.categorizeHook(body: "UserPromptSubmit hook success: OK") == .userPromptSubmit)
    #expect(ClaudeCodeLogParser.categorizeHook(body: "The following skills are available") == .skillsListing)
    #expect(ClaudeCodeLogParser.categorizeHook(body: "random hook output") == .other)
}

// MARK: - classify helper

@Test func classifyMcpParsesServerName() {
    let (cat, server, skill) = ClaudeCodeLogParser.classify(
        toolName: "mcp__plugin_rtb_rtb-db__query_db", input: nil
    )
    #expect(cat == .mcp)
    #expect(server == "plugin_rtb_rtb-db")
    #expect(skill == nil)
}

@Test func classifySkillExtractsSkillNameFromInput() {
    let (cat, server, skill) = ClaudeCodeLogParser.classify(
        toolName: "Skill", input: ["skill": "my-skill"] as [String: Any]
    )
    #expect(cat == .skill)
    #expect(server == nil)
    #expect(skill == "my-skill")
}

@Test func classifyNativeToolReturnsNative() {
    let (cat, _, _) = ClaudeCodeLogParser.classify(toolName: "Bash", input: nil)
    #expect(cat == .native)
}
