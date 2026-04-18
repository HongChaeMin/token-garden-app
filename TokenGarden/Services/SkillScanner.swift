import Foundation

/// Metadata extracted from a single installed SKILL.md.
/// Mirrors the Python prototype in rtb-ai-usage/scripts/scan_skills.py so
/// the two codebases produce comparable numbers.
struct SkillInfo: Sendable, Hashable {
    let name: String
    let path: URL
    let source: SkillSource
    let description: String
    /// `"<name>: <description>"` — what CC advertises to the model in the
    /// system prompt (the baseline cost of simply having the skill installed).
    let frontmatterChars: Int
    /// The SKILL.md body (what gets loaded when the skill is actually invoked).
    let bodyChars: Int
    let totalChars: Int
    /// Full file contents — optional (callers may not need this for token
    /// counting if they only care about chars).
    let rawText: String
}

enum SkillSource: String, Sendable, Hashable {
    case global         // ~/.claude/skills/
    case marketplace    // ~/.claude/plugins/marketplaces/*/skills/*/
    case project        // <cwd>/.claude/skills/
}

struct SkillsReport: Sendable {
    let skills: [SkillInfo]
    let bySource: [SkillSource: Int]
    let duplicateNames: [String]

    var totalFrontmatterChars: Int {
        skills.reduce(0) { $0 + $1.frontmatterChars }
    }
    var totalBodyChars: Int {
        skills.reduce(0) { $0 + $1.bodyChars }
    }
}

/// Walks known skill locations, parses SKILL.md frontmatter (name +
/// description), and separates body from frontmatter.
///
/// Scope:
///   - `~/.claude/skills/*/SKILL.md`                                    (global)
///   - `~/.claude/plugins/marketplaces/*/skills/*/SKILL.md`            (marketplace)
///   - `~/.claude/plugins/marketplaces/*/plugins/*/skills/*/SKILL.md`  (nested marketplace)
///   - `<cwd>/.claude/skills/*/SKILL.md`                                (project local)
///
/// Later scans win on duplicate skill names (the user's project layer
/// overrides personal-global which overrides marketplace).
struct SkillScanner {
    /// Optional project root for project-local skills. Defaults to CWD.
    let projectRoot: URL?
    /// Optional home directory override for tests.
    let homeDirectory: URL

    init(projectRoot: URL? = nil, homeDirectory: URL? = nil) {
        self.projectRoot = projectRoot
        self.homeDirectory = homeDirectory ?? FileManager.default.homeDirectoryForCurrentUser
    }

    func scan() -> SkillsReport {
        var seen: [String: SkillInfo] = [:]
        var duplicates: [String] = []

        for (root, source) in searchRoots() {
            for skillMD in skillMDFiles(in: root) {
                guard let info = load(path: skillMD, source: source) else { continue }
                if seen[info.name] != nil {
                    duplicates.append(info.name)
                }
                seen[info.name] = info
            }
        }

        var bySource: [SkillSource: Int] = [:]
        for info in seen.values {
            bySource[info.source, default: 0] += 1
        }
        let skills = seen.values.sorted { $0.bodyChars > $1.bodyChars }
        return SkillsReport(
            skills: Array(skills),
            bySource: bySource,
            duplicateNames: Array(Set(duplicates)).sorted()
        )
    }

    // MARK: - Layout

    private func searchRoots() -> [(URL, SkillSource)] {
        var roots: [(URL, SkillSource)] = []
        roots.append((homeDirectory.appendingPathComponent(".claude/skills"), .global))

        let mpRoot = homeDirectory.appendingPathComponent(".claude/plugins/marketplaces")
        if let mpChildren = try? FileManager.default.contentsOfDirectory(
            at: mpRoot, includingPropertiesForKeys: [.isDirectoryKey]
        ) {
            for mp in mpChildren where (try? mp.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                roots.append((mp.appendingPathComponent("skills"), .marketplace))
                let plugins = mp.appendingPathComponent("plugins")
                if let pluginChildren = try? FileManager.default.contentsOfDirectory(
                    at: plugins, includingPropertiesForKeys: [.isDirectoryKey]
                ) {
                    for pl in pluginChildren where (try? pl.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                        roots.append((pl.appendingPathComponent("skills"), .marketplace))
                    }
                }
            }
        }

        let cwd = projectRoot ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        roots.append((cwd.appendingPathComponent(".claude/skills"), .project))
        return roots
    }

    private func skillMDFiles(in root: URL) -> [URL] {
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isDirectoryKey]
        ) else { return [] }
        return children.compactMap { dir in
            let skill = dir.appendingPathComponent("SKILL.md")
            return FileManager.default.fileExists(atPath: skill.path) ? skill : nil
        }
    }

    // MARK: - Parsing

    private func load(path: URL, source: SkillSource) -> SkillInfo? {
        guard let text = try? String(contentsOf: path, encoding: .utf8) else { return nil }
        let (meta, body) = Self.parseFrontmatter(text)
        let name = meta["name"] ?? path.deletingLastPathComponent().lastPathComponent
        guard !name.isEmpty else { return nil }
        let description = meta["description"] ?? ""
        let baseline = "\(name): \(description)"
        return SkillInfo(
            name: name,
            path: path,
            source: source,
            description: description,
            frontmatterChars: baseline.count,
            bodyChars: body.count,
            totalChars: text.count,
            rawText: text
        )
    }

    /// Tiny YAML-ish parser — supports `key: value` on single lines only.
    /// Quoted values have outer quotes stripped.
    static func parseFrontmatter(_ text: String) -> (meta: [String: String], body: String) {
        guard text.hasPrefix("---") else { return ([:], text) }
        // Find the second `---` marker on its own line.
        let lines = text.components(separatedBy: "\n")
        guard lines.count > 1 else { return ([:], text) }
        var endIndex: Int? = nil
        for i in 1..<lines.count where lines[i].trimmingCharacters(in: .whitespaces) == "---" {
            endIndex = i
            break
        }
        guard let end = endIndex else { return ([:], text) }

        var meta: [String: String] = [:]
        var currentKey: String? = nil
        for line in lines[1..<end] {
            if let colonRange = line.range(of: ":"),
               let firstChar = line.first, firstChar.isLetter || firstChar == "_" {
                let key = line[line.startIndex..<colonRange.lowerBound]
                    .trimmingCharacters(in: .whitespaces)
                var value = line[colonRange.upperBound..<line.endIndex]
                    .trimmingCharacters(in: .whitespaces)
                // Strip one layer of outer quotes
                if value.hasPrefix("\"") && value.hasSuffix("\"") && value.count >= 2 {
                    value = String(value.dropFirst().dropLast())
                } else if value.hasPrefix("'") && value.hasSuffix("'") && value.count >= 2 {
                    value = String(value.dropFirst().dropLast())
                }
                meta[key] = value
                currentKey = key
            } else if let key = currentKey,
                      let firstChar = line.first, firstChar.isWhitespace {
                meta[key] = ((meta[key] ?? "") + " " + line.trimmingCharacters(in: .whitespaces)).trimmingCharacters(in: .whitespaces)
            }
        }

        let bodyLines = Array(lines[(end + 1)...])
        let body = bodyLines.joined(separator: "\n")
        return (meta, body)
    }
}
