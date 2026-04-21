import Foundation
import SwiftUI

/// Observable wrapper that reads `~/.claude/projects/<encoded>/*.jsonl`
/// files, runs the Scanners, and publishes a `BreakdownSummary` for
/// the `BreakdownView` to render.
///
/// Kept intentionally simple:
///   - Re-reads JSONL each time a window changes. Not incremental.
///   - Not a SwiftData store — purely derived state.
///   - All work runs on a detached Task so the UI doesn't block on
///     the initial 100–300 ms scan of hundreds of session files.
@MainActor
final class BreakdownLoader: ObservableObject {
    @Published private(set) var summary: BreakdownSummary?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private var currentTask: Task<Void, Never>?

    func load(window: TimeWindow) {
        currentTask?.cancel()
        isLoading = true
        errorMessage = nil
        currentTask = Task.detached(priority: .userInitiated) { [weak self] in
            let result = Self.compute(window: window)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self else { return }
                self.isLoading = false
                switch result {
                case .success(let s): self.summary = s
                case .failure(let e): self.errorMessage = e.localizedDescription
                }
            }
        }
    }

    /// Static compute so we can be called off the main thread without
    /// capturing self. Returns a Result instead of throwing for easier
    /// MainActor bridging.
    nonisolated private static func compute(window: TimeWindow) -> Result<BreakdownSummary, Error> {
        let cutoff = BreakdownAggregator.windowStart(for: window, from: Date())
        let parser = ClaudeCodeLogParser()
        var toolUses: [ToolUseEvent] = []
        var hookBlocks: [HookBlockEvent] = []

        let root = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects", isDirectory: true)
        // Walk each project subdir for *.jsonl files.
        if let projects = try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isDirectoryKey]
        ) {
            for project in projects {
                guard let isDir = (try? project.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory,
                      isDir else { continue }
                guard let files = try? FileManager.default.contentsOfDirectory(
                    at: project, includingPropertiesForKeys: [.contentModificationDateKey]
                ) else { continue }
                for file in files where file.pathExtension == "jsonl" {
                    // Skip files whose mtime is older than the window —
                    // a cheap optimization since most sessions are old.
                    if let mtime = (try? file.resourceValues(
                        forKeys: [.contentModificationDateKey]
                    ))?.contentModificationDate, mtime < cutoff {
                        continue
                    }
                    processFile(file, parser: parser, cutoff: cutoff,
                                toolUses: &toolUses, hookBlocks: &hookBlocks)
                }
            }
        }

        // Static scans
        let skills = SkillScanner().scan().skills
        let claudeMd = ClaudeMdScanner().scan()

        let summary = BreakdownAggregator.aggregate(
            window: window,
            toolUses: toolUses,
            hookBlocks: hookBlocks,
            installedSkills: skills,
            claudeMd: claudeMd
        )
        return .success(summary)
    }

    /// Stream a JSONL file line-by-line and append parsed events.
    /// Uses `String(contentsOf:)` + `components(separatedBy:)` — simple
    /// and adequate for CC session files (a few MB at most).
    nonisolated private static func processFile(
        _ url: URL,
        parser: ClaudeCodeLogParser,
        cutoff: Date,
        toolUses: inout [ToolUseEvent],
        hookBlocks: inout [HookBlockEvent]
    ) {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return }
        for line in content.components(separatedBy: "\n") where !line.isEmpty {
            for event in parser.parseToolUses(logLine: line) where event.timestamp >= cutoff {
                toolUses.append(event)
            }
            for block in parser.parseHookBlocks(logLine: line) where block.timestamp >= cutoff {
                hookBlocks.append(block)
            }
        }
    }
}
