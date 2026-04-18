import Foundation

/// A single CLAUDE.md file layer (global / project / .claude/project).
struct ClaudeMdLayer: Sendable, Hashable {
    let path: URL
    /// Raw chars of this file alone (no @-expansion).
    let rawChars: Int
    /// Chars after @-expansion (this file + all included @-references).
    let expandedChars: Int
    /// @-references found in this file (raw strings as written).
    let includes: [String]
}

struct ClaudeMdReport: Sendable {
    let layers: [ClaudeMdLayer]
    /// Concatenated expanded text across all layers — suitable for token
    /// counting as a single payload.
    let totalFlatText: String
    let cyclesDetected: [String]
    let missingReferences: [String]
}

/// Walks the CLAUDE.md hierarchy with `@<path>` reference expansion.
///
/// Locations (in order):
///   1. `~/.claude/CLAUDE.md`          (personal global)
///   2. `<cwd>/CLAUDE.md`              (project root)
///   3. `<cwd>/.claude/CLAUDE.md`      (project override)
///
/// Supports:
///   - `@~/path` (home-relative)
///   - `@/absolute/path`
///   - `@relative/path` (resolved against the including file's directory)
///
/// Not supported:
///   - Conditional includes (CC internal logic)
///   - Dynamic/computed paths
struct ClaudeMdScanner {
    let projectRoot: URL?
    let homeDirectory: URL

    init(projectRoot: URL? = nil, homeDirectory: URL? = nil) {
        self.projectRoot = projectRoot
        self.homeDirectory = homeDirectory ?? FileManager.default.homeDirectoryForCurrentUser
    }

    func scan() -> ClaudeMdReport {
        let cwd = projectRoot ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let candidates: [URL] = [
            homeDirectory.appendingPathComponent(".claude/CLAUDE.md"),
            cwd.appendingPathComponent("CLAUDE.md"),
            cwd.appendingPathComponent(".claude/CLAUDE.md"),
        ]

        var layers: [ClaudeMdLayer] = []
        var cycles: [String] = []
        var missing: [String] = []
        var flatParts: [String] = []

        for candidate in candidates where FileManager.default.fileExists(atPath: candidate.path) {
            guard let raw = try? String(contentsOf: candidate, encoding: .utf8) else { continue }
            let (expanded, includes) = Self.expand(
                path: candidate, visited: [], missing: &missing, cycles: &cycles
            )
            layers.append(ClaudeMdLayer(
                path: candidate,
                rawChars: raw.count,
                expandedChars: expanded.count,
                includes: includes
            ))
            flatParts.append(expanded)
        }

        return ClaudeMdReport(
            layers: layers,
            totalFlatText: flatParts.joined(separator: "\n\n"),
            cyclesDetected: cycles,
            missingReferences: missing
        )
    }

    // MARK: - @-expansion

    /// Expand a single file. `visited` protects against cycles. Line-leading
    /// `@path` references are replaced inline; references mid-line are left
    /// as literal text (matching CC's documented behavior).
    static func expand(
        path: URL,
        visited: Set<URL>,
        missing: inout [String],
        cycles: inout [String]
    ) -> (text: String, includes: [String]) {
        if visited.contains(path) {
            cycles.append(path.path)
            return ("", [])
        }
        guard FileManager.default.fileExists(atPath: path.path) else {
            missing.append(path.path)
            return ("", [])
        }
        guard let text = try? String(contentsOf: path, encoding: .utf8) else {
            missing.append(path.path + " (read error)")
            return ("", [])
        }
        var newVisited = visited
        newVisited.insert(path)

        var out: [String] = []
        var includes: [String] = []
        for line in text.components(separatedBy: "\n") {
            if let ref = Self.matchAtReference(line: line) {
                includes.append(ref)
                let resolved = resolve(ref: ref, base: path)
                let (subText, _) = expand(
                    path: resolved, visited: newVisited, missing: &missing, cycles: &cycles
                )
                out.append(subText)
            } else {
                out.append(line)
            }
        }
        return (out.joined(separator: "\n"), includes)
    }

    /// Match a line that consists of `@<path>` (optional leading whitespace,
    /// optional trailing whitespace) — returns the path or nil.
    static func matchAtReference(line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("@"), trimmed.count > 1 else { return nil }
        let ref = String(trimmed.dropFirst())
        // Rule: must be a single token — no internal whitespace.
        if ref.contains(where: { $0.isWhitespace }) { return nil }
        return ref
    }

    static func resolve(ref: String, base: URL) -> URL {
        if ref.hasPrefix("~") {
            return URL(fileURLWithPath: (ref as NSString).expandingTildeInPath).resolvingSymlinksInPath()
        }
        if ref.hasPrefix("/") {
            return URL(fileURLWithPath: ref).resolvingSymlinksInPath()
        }
        return base.deletingLastPathComponent()
            .appendingPathComponent(ref)
            .resolvingSymlinksInPath()
    }
}
