import Foundation

/// A single `tool_use` block observed in an assistant message. Used to
/// attribute token pressure to MCP servers, Skill invocations, and native
/// tool calls.
///
/// The `inputChars` field is the length of the JSON-serialized `input`
/// payload sent to the tool — it's the only portion of tool use that
/// Anthropic's message-level `usage` field doesn't roll up separately.
/// Combined with TokenCounter (count_tokens API) the UI can convert chars
/// to exact tokens on demand.
struct ToolUseEvent: Sendable, Hashable {
    let timestamp: Date
    let sessionId: String?
    let projectName: String?
    /// Full tool name as it appears in the log — e.g. `Bash`, `Edit`,
    /// `mcp__plugin_rtb_rtb-db__query_db`, `Skill`.
    let toolName: String
    /// JSON-serialized chars of the `input` payload; 0 if input was empty.
    let inputChars: Int
    /// Category for grouping views. Derived from `toolName`.
    let category: ToolCategory
    /// MCP server name (e.g. `plugin_rtb_rtb-db`) when `category == .mcp`.
    let mcpServer: String?
    /// Skill name when `category == .skill` and the invocation named one.
    let skillName: String?
}

enum ToolCategory: String, Sendable, Hashable {
    case mcp
    case skill
    case native
}

/// A `<system-reminder>` block found in a user message — the JSONL-visible
/// portion of hook-injected context. Runtime-only hook injections don't
/// persist here, so counts derived from these events are a **lower bound**.
struct HookBlockEvent: Sendable, Hashable {
    let timestamp: Date
    let sessionId: String?
    let projectName: String?
    /// Full text of the block body (between the opening and closing tags).
    let body: String
    /// Heuristic categorization based on keywords inside the body.
    let category: HookCategory
}

enum HookCategory: String, Sendable, Hashable {
    case sessionStart        // "SessionStart hook" marker
    case userPromptSubmit    // "UserPromptSubmit hook" marker
    case preToolUse          // PreToolUse markers
    case postToolUse         // PostToolUse markers
    case skillsListing       // Long listings of "The following skills are available"
    case other
}
