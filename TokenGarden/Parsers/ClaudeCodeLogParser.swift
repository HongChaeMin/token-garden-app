import Foundation

struct ClaudeCodeLogParser: TokenLogParser {
    let name = "claude-code"

    private static nonisolated(unsafe) let dateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    var watchPaths: [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return ["\(home)/.claude"]
    }

    /// Returns sessionId if this line is a session Stop event
    func parseSessionEnd(logLine: String) -> String? {
        guard let data = logLine.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hookEvent = json["hookEvent"] as? String,
              hookEvent == "Stop",
              let sessionId = json["sessionId"] as? String
        else { return nil }
        return sessionId
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
