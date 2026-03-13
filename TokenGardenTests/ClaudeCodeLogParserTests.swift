import Testing
import Foundation
@testable import TokenGarden

@Test func parseAssistantLine() {
    let parser = ClaudeCodeLogParser()
    let line = """
    {"type":"assistant","message":{"model":"claude-opus-4-6","id":"msg_1","type":"message","role":"assistant","content":[],"stop_reason":"end_turn","stop_sequence":null,"usage":{"input_tokens":100,"output_tokens":50,"cache_creation_input_tokens":200,"cache_read_input_tokens":30}},"timestamp":"2026-03-13T05:23:31.807Z","cwd":"/Users/test/projects/my-app","sessionId":"abc-123","uuid":"uuid-1"}
    """
    let event = parser.parse(logLine: line)
    #expect(event != nil)
    #expect(event!.inputTokens == 100)
    #expect(event!.outputTokens == 50)
    #expect(event!.cacheCreationTokens == 200)
    #expect(event!.cacheReadTokens == 30)
    #expect(event!.model == "claude-opus-4-6")
    #expect(event!.projectName == "my-app")
    #expect(event!.source == "claude-code")
    #expect(event!.totalTokens == 150)
}

@Test func skipNonAssistantLine() {
    let parser = ClaudeCodeLogParser()
    let line = """
    {"type":"user","message":{"role":"user","content":[{"type":"text","text":"hello"}]},"timestamp":"2026-03-13T05:00:00.000Z","cwd":"/Users/test/projects/my-app"}
    """
    let event = parser.parse(logLine: line)
    #expect(event == nil)
}

@Test func skipProgressLine() {
    let parser = ClaudeCodeLogParser()
    let line = """
    {"type":"progress","data":{"type":"hook_progress"},"timestamp":"2026-03-13T05:00:00.000Z","cwd":"/Users/test/projects/my-app"}
    """
    let event = parser.parse(logLine: line)
    #expect(event == nil)
}

@Test func projectNameFromCwd() {
    let parser = ClaudeCodeLogParser()
    let line = """
    {"type":"assistant","message":{"model":"claude-sonnet-4-20250514","id":"msg_1","type":"message","role":"assistant","content":[],"stop_reason":"end_turn","stop_sequence":null,"usage":{"input_tokens":10,"output_tokens":5,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}},"timestamp":"2026-03-13T05:00:00.000Z","cwd":"/Users/someone/Company/private/projects/deep/nested/project-name","sessionId":"s1","uuid":"u1"}
    """
    let event = parser.parse(logLine: line)
    #expect(event?.projectName == "project-name")
}

@Test func watchPathsIncludeClaudeProjects() {
    let parser = ClaudeCodeLogParser()
    #expect(parser.watchPaths.first!.hasSuffix(".claude/projects"))
}
