import Foundation

struct ClaudeCodeLogParser: TokenLogParser {
    let name = "claude-code"

    private static nonisolated(unsafe) let dateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static nonisolated(unsafe) let systemReminderRegex: NSRegularExpression = {
        // Matches <system-reminder>...</system-reminder>, DOTALL
        return try! NSRegularExpression(
            pattern: "<system-reminder>([\\s\\S]*?)</system-reminder>",
            options: []
        )
    }()

    var watchPaths: [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return ["\(home)/.claude"]
    }

    /// Returns sessionId if this line is a session Stop event
    func parseSessionEnd(logLine: String) -> String? {
        guard let data = logLine.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sessionId = json["sessionId"] as? String,
              let dataObj = json["data"] as? [String: Any],
              let hookEvent = dataObj["hookEvent"] as? String,
              hookEvent == "Stop"
        else { return nil }
        return sessionId
    }

    // MARK: - Structural parsing (tool_use + system-reminder)

    /// Parse tool_use blocks from an assistant message. Returns zero or
    /// more events — one per tool_use block. Non-assistant lines and lines
    /// without tool_use content return an empty array.
    func parseToolUses(logLine: String) -> [ToolUseEvent] {
        guard let data = logLine.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (json["type"] as? String) == "assistant",
              let message = json["message"] as? [String: Any],
              let content = message["content"] as? [[String: Any]] else {
            return []
        }

        let timestamp = (json["timestamp"] as? String)
            .flatMap { Self.dateFormatter.date(from: $0) } ?? Date()
        let sessionId = json["sessionId"] as? String
        let cwd = json["cwd"] as? String
        let projectName = cwd.flatMap { URL(fileURLWithPath: $0).lastPathComponent }

        var events: [ToolUseEvent] = []
        for block in content {
            guard (block["type"] as? String) == "tool_use",
                  let toolName = block["name"] as? String else {
                continue
            }
            let inputChars = Self.inputChars(for: block["input"])
            let (category, mcpServer, skillName) = Self.classify(toolName: toolName, input: block["input"])
            events.append(ToolUseEvent(
                timestamp: timestamp,
                sessionId: sessionId,
                projectName: projectName,
                toolName: toolName,
                inputChars: inputChars,
                category: category,
                mcpServer: mcpServer,
                skillName: skillName
            ))
        }
        return events
    }

    /// Parse `<system-reminder>` blocks from a user message. Returns zero
    /// or more events — these are hook-injected content that was persisted
    /// to JSONL (a **lower bound** on total hook-injected tokens; runtime
    /// ephemeral injections aren't captured here).
    func parseHookBlocks(logLine: String) -> [HookBlockEvent] {
        guard let data = logLine.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (json["type"] as? String) == "user",
              let message = json["message"] as? [String: Any] else {
            return []
        }

        let timestamp = (json["timestamp"] as? String)
            .flatMap { Self.dateFormatter.date(from: $0) } ?? Date()
        let sessionId = json["sessionId"] as? String
        let cwd = json["cwd"] as? String
        let projectName = cwd.flatMap { URL(fileURLWithPath: $0).lastPathComponent }

        // Collect text content (string or array of text blocks)
        var text = ""
        if let str = message["content"] as? String {
            text = str
        } else if let blocks = message["content"] as? [[String: Any]] {
            for blk in blocks {
                if let t = blk["text"] as? String { text += t }
            }
        }
        guard !text.isEmpty else { return [] }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = Self.systemReminderRegex.matches(in: text, range: range)
        return matches.compactMap { m in
            guard m.numberOfRanges >= 2,
                  let bodyRange = Range(m.range(at: 1), in: text) else { return nil }
            let body = String(text[bodyRange])
            return HookBlockEvent(
                timestamp: timestamp,
                sessionId: sessionId,
                projectName: projectName,
                body: body,
                category: Self.categorizeHook(body: body)
            )
        }
    }

    // MARK: - Classification helpers

    private static func inputChars(for input: Any?) -> Int {
        guard let input else { return 0 }
        if let data = try? JSONSerialization.data(
            withJSONObject: input,
            options: []
        ), let s = String(data: data, encoding: .utf8) {
            return s.count
        }
        return 0
    }

    /// Map a tool_use `name` + `input` to (category, mcpServer, skillName).
    /// - MCP tools: `mcp__<server>__<tool>` — server is the 2nd segment.
    /// - Skill tool: name == "Skill", skillName from input["skill"].
    /// - Otherwise: .native.
    static func classify(toolName: String, input: Any?) -> (ToolCategory, String?, String?) {
        if toolName.hasPrefix("mcp__") {
            let parts = toolName.split(separator: "_").filter { !$0.isEmpty }
            // "mcp__plugin_rtb_rtb-db__query_db" → parts after collapsing
            // doubled underscores. Simpler: split on "__" literally.
            let literal = toolName.components(separatedBy: "__")
            let server = literal.count > 1 ? literal[1] : toolName
            return (.mcp, server, nil)
            _ = parts  // keep the linter happy about the unused variable
        }
        if toolName == "Skill" {
            let skill = (input as? [String: Any])?["skill"] as? String
            return (.skill, nil, skill)
        }
        return (.native, nil, nil)
    }

    /// Classify a hook block body by looking for marker strings. Best-effort
    /// heuristic — categories are only for UI grouping.
    static func categorizeHook(body: String) -> HookCategory {
        if body.contains("SessionStart hook") || body.contains("RTB 개발 프로토콜") {
            return .sessionStart
        }
        if body.contains("UserPromptSubmit hook") {
            return .userPromptSubmit
        }
        if body.contains("PreToolUse") {
            return .preToolUse
        }
        if body.contains("PostToolUse") {
            return .postToolUse
        }
        if body.contains("The following skills are available") {
            return .skillsListing
        }
        return .other
    }

    func parse(logLine: String) -> TokenEvent? {
        guard let data = logLine.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String,
              type == "assistant",
              let message = json["message"] as? [String: Any],
              let usage = message["usage"] as? [String: Any],
              let inputTokens = usage["input_tokens"] as? Int,
              let outputTokens = usage["output_tokens"] as? Int,
              let timestampStr = json["timestamp"] as? String
        else {
            return nil
        }

        let cacheCreation = usage["cache_creation_input_tokens"] as? Int ?? 0
        let cacheRead = usage["cache_read_input_tokens"] as? Int ?? 0
        let model = message["model"] as? String
        let cwd = json["cwd"] as? String
        let projectName = cwd.flatMap { URL(fileURLWithPath: $0).lastPathComponent }
        let sessionId = json["sessionId"] as? String
        let timestamp = Self.dateFormatter.date(from: timestampStr) ?? Date()

        return TokenEvent(
            timestamp: timestamp,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cacheCreationTokens: cacheCreation,
            cacheReadTokens: cacheRead,
            model: model,
            projectName: projectName,
            sessionId: sessionId,
            source: name
        )
    }
}
