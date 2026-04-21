import Foundation
import Testing
@testable import TokenGarden

// MARK: - helpers

private func makeTempDir() -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("tg-scanner-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func write(_ content: String, to url: URL) {
    try? FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try? content.write(to: url, atomically: true, encoding: .utf8)
}

// MARK: - SkillScanner.parseFrontmatter

@Test func parsesStandardFrontmatter() {
    let text = """
    ---
    name: my-skill
    description: Does a thing
    ---
    Body here
    """
    let (meta, body) = SkillScanner.parseFrontmatter(text)
    #expect(meta["name"] == "my-skill")
    #expect(meta["description"] == "Does a thing")
    #expect(body == "Body here")
}

@Test func stripsOuterQuotes() {
    let text = """
    ---
    name: "quoted-name"
    description: 'single-quoted'
    ---
    body
    """
    let (meta, _) = SkillScanner.parseFrontmatter(text)
    #expect(meta["name"] == "quoted-name")
    #expect(meta["description"] == "single-quoted")
}

@Test func noFrontmatterReturnsEmptyMeta() {
    // 경계값 — frontmatter 없음
    let text = "just body text"
    let (meta, body) = SkillScanner.parseFrontmatter(text)
    #expect(meta.isEmpty)
    #expect(body == text)
}

@Test func unclosedFrontmatterIsTreatedAsNoFrontmatter() {
    // 에러 케이스 — 닫는 --- 없음
    let text = "---\nname: foo\nbody with no closing"
    let (meta, _) = SkillScanner.parseFrontmatter(text)
    #expect(meta.isEmpty)
}

@Test func colonInValuePreserved() {
    let text = """
    ---
    name: foo
    description: See https://example.com/path for docs
    ---
    """
    let (meta, _) = SkillScanner.parseFrontmatter(text)
    #expect(meta["description"] == "See https://example.com/path for docs")
}

// MARK: - SkillScanner.scan

@Test func scannerFindsSkillsInGlobalAndProjectLocations() {
    let tempHome = makeTempDir()
    let tempProject = makeTempDir()
    defer {
        try? FileManager.default.removeItem(at: tempHome)
        try? FileManager.default.removeItem(at: tempProject)
    }
    write(
        "---\nname: global-skill\ndescription: g\n---\nbody A",
        to: tempHome.appendingPathComponent(".claude/skills/g1/SKILL.md")
    )
    write(
        "---\nname: project-skill\ndescription: p\n---\nbody B",
        to: tempProject.appendingPathComponent(".claude/skills/p1/SKILL.md")
    )

    let scanner = SkillScanner(projectRoot: tempProject, homeDirectory: tempHome)
    let report = scanner.scan()
    #expect(report.skills.count == 2)
    let names = Set(report.skills.map(\.name))
    #expect(names.contains("global-skill"))
    #expect(names.contains("project-skill"))
    #expect(report.bySource[.global] == 1)
    #expect(report.bySource[.project] == 1)
}

@Test func scannerReportsTotalBaselineAndBody() {
    let tempHome = makeTempDir()
    defer { try? FileManager.default.removeItem(at: tempHome) }
    write(
        "---\nname: a\ndescription: desc-a\n---\n" + String(repeating: "x", count: 100),
        to: tempHome.appendingPathComponent(".claude/skills/a/SKILL.md")
    )
    write(
        "---\nname: b\ndescription: desc-b\n---\n" + String(repeating: "y", count: 200),
        to: tempHome.appendingPathComponent(".claude/skills/b/SKILL.md")
    )
    let scanner = SkillScanner(projectRoot: tempHome, homeDirectory: tempHome)
    let report = scanner.scan()
    #expect(report.skills.count == 2)
    #expect(report.totalBodyChars >= 300)
    // baseline = "a: desc-a" + "b: desc-b" = 9 + 9 = 18
    #expect(report.totalFrontmatterChars == 18)
    // Sorted by body size desc
    #expect(report.skills[0].name == "b")
}

@Test func scannerHandlesMissingDirectoryGracefully() {
    // 경계값 — 빈 홈 디렉토리
    let empty = makeTempDir()
    defer { try? FileManager.default.removeItem(at: empty) }
    let scanner = SkillScanner(projectRoot: empty, homeDirectory: empty)
    let report = scanner.scan()
    #expect(report.skills.isEmpty)
}

// MARK: - ClaudeMdScanner.matchAtReference

@Test func detectsAtReferenceOnOwnLine() {
    #expect(ClaudeMdScanner.matchAtReference(line: "@instructions.md") == "instructions.md")
    #expect(ClaudeMdScanner.matchAtReference(line: "  @~/config.md  ") == "~/config.md")
}

@Test func ignoresInlineAt() {
    // 경계값 — 줄 중간 @ 는 무시
    #expect(ClaudeMdScanner.matchAtReference(line: "See @foo for details") == nil)
    #expect(ClaudeMdScanner.matchAtReference(line: "") == nil)
    #expect(ClaudeMdScanner.matchAtReference(line: "@") == nil)
}

// MARK: - ClaudeMdScanner.scan + expand

@Test func expandsAtReferencesRecursively() {
    let dir = makeTempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let child = dir.appendingPathComponent("child.md")
    try? "CHILD".write(to: child, atomically: true, encoding: .utf8)
    let parent = dir.appendingPathComponent(".claude/CLAUDE.md")
    write("PARENT\n@../child.md\nAFTER", to: parent)

    let scanner = ClaudeMdScanner(projectRoot: dir, homeDirectory: dir)
    let report = scanner.scan()
    // Note: expanded can be smaller than raw if "@path" is longer than the
    // referenced file's content. Validate inclusion instead.
    #expect(report.totalFlatText.contains("PARENT"))
    #expect(report.totalFlatText.contains("CHILD"))
    #expect(report.totalFlatText.contains("AFTER"))
    // layer.includes should record the ref
    #expect(report.layers.contains { $0.includes.contains("../child.md") })
}

@Test func detectsCycles() {
    let dir = makeTempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    write("A\n@b.md", to: dir.appendingPathComponent(".claude/CLAUDE.md"))
    write("B\n@CLAUDE.md", to: dir.appendingPathComponent(".claude/b.md"))
    // Actually — need cycle → need b to @ back to the parent. Let me make a simpler cycle test.

    let dir2 = makeTempDir()
    defer { try? FileManager.default.removeItem(at: dir2) }
    let a = dir2.appendingPathComponent("a.md")
    let b = dir2.appendingPathComponent("b.md")
    write("@b.md", to: a)
    write("@a.md", to: b)
    var missing: [String] = []
    var cycles: [String] = []
    _ = ClaudeMdScanner.expand(path: a, visited: [], missing: &missing, cycles: &cycles)
    #expect(cycles.count == 1)
}

@Test func recordsMissingReferences() {
    // 에러 케이스 — 존재하지 않는 파일 참조
    let dir = makeTempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let parent = dir.appendingPathComponent("parent.md")
    write("@nonexistent.md", to: parent)
    var missing: [String] = []
    var cycles: [String] = []
    let (text, _) = ClaudeMdScanner.expand(
        path: parent, visited: [], missing: &missing, cycles: &cycles
    )
    #expect(text == "")
    #expect(missing.count == 1)
    #expect(missing[0].contains("nonexistent.md"))
}

@Test func resolveHandlesHomeAbsoluteAndRelative() {
    let home = ClaudeMdScanner.resolve(ref: "~/test.md", base: URL(fileURLWithPath: "/any"))
    #expect(home.path.contains(NSHomeDirectory().replacingOccurrences(of: "/System/Volumes/Data", with: "")) ||
           home.path.hasPrefix(NSHomeDirectory()))

    let abs = ClaudeMdScanner.resolve(ref: "/etc/hosts", base: URL(fileURLWithPath: "/any"))
    #expect(abs.path.hasSuffix("/etc/hosts"))

    let rel = ClaudeMdScanner.resolve(
        ref: "docs/note.md",
        base: URL(fileURLWithPath: "/tmp/project/CLAUDE.md")
    )
    #expect(rel.path.hasSuffix("/project/docs/note.md"))
}
