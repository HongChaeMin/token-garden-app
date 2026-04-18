import SwiftUI

/// Top-level container for the 4 structural breakdown sub-tabs
/// (MCP / Skill / Hook / CLAUDE.md). Shows a time-window picker at the
/// top and swaps the body based on the selected dimension.
///
/// Data is loaded on-demand via `BreakdownLoader` — a lightweight
/// observable object that runs the Scanners + parses JSONL files and
/// caches the resulting `BreakdownSummary`.
struct BreakdownView: View {
    @StateObject private var loader = BreakdownLoader()
    @State private var window: TimeWindow = .day
    @State private var dimension: Dimension = .mcp

    enum Dimension: String, CaseIterable, Identifiable {
        case mcp = "MCP"
        case skill = "Skill"
        case hook = "Hook"
        case claudeMd = "CLAUDE.md"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Window + dimension pickers
            HStack {
                Picker("Window", selection: $window) {
                    ForEach(TimeWindow.allCases) { w in
                        Text(w.label).tag(w)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 260)

                Spacer()

                if loader.isLoading {
                    ProgressView().controlSize(.small)
                }
                if let err = loader.errorMessage {
                    Text(err)
                        .foregroundStyle(.red)
                        .font(.caption)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal)

            Picker("Dimension", selection: $dimension) {
                ForEach(Dimension.allCases) { d in Text(d.rawValue).tag(d) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            Divider()

            // Body
            ScrollView {
                Group {
                    if let summary = loader.summary {
                        switch dimension {
                        case .mcp: MCPBreakdownView(rows: summary.mcp)
                        case .skill: SkillBreakdownView(skills: summary.skills)
                        case .hook: HookBreakdownView(rows: summary.hooks)
                        case .claudeMd: ClaudeMdBreakdownView(breakdown: summary.claudeMd)
                        }
                    } else if !loader.isLoading {
                        Text("Loading breakdown…")
                            .foregroundStyle(.secondary)
                            .padding()
                    }
                }
                .padding(.horizontal)
            }
        }
        .padding(.vertical, 8)
        .onAppear { loader.load(window: window) }
        .onChange(of: window) { _, newValue in loader.load(window: newValue) }
    }
}

// MARK: - MCP

struct MCPBreakdownView: View {
    let rows: [MCPServerRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header("MCP 서버별 호출 + 입력 토큰 추정", accuracy: "📊 input chars 기반")
            if rows.isEmpty {
                Text("선택한 기간에 MCP 호출 없음").foregroundStyle(.secondary)
            } else {
                tableHeader(["Server", "Calls", "~ tokens", "avg/call"])
                ForEach(rows) { row in
                    HStack {
                        Text(row.server).frame(maxWidth: .infinity, alignment: .leading)
                        Text("\(row.calls)").frame(width: 80, alignment: .trailing)
                        Text("\(row.approxTokens)").frame(width: 90, alignment: .trailing)
                        Text("\(row.averageInputChars)").frame(width: 80, alignment: .trailing)
                    }
                    .font(.system(.body, design: .monospaced))
                }
            }
        }
    }
}

// MARK: - Skill

struct SkillBreakdownView: View {
    let skills: SkillsBreakdown

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header("Skill 구조 breakdown", accuracy: "📊 파일/호출 기반 (시스템 프롬프트 주입 정책 추정)")

            VStack(alignment: .leading, spacing: 4) {
                Text("설치 baseline")
                    .font(.headline)
                Text("모든 세션의 시스템 프롬프트에 포함되는 (name + description) 합:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(skills.baselineChars) chars ≈ \(Int(Double(skills.baselineChars) / 3.5)) tokens  ·  설치 수 \(skills.installed.count)")
                    .font(.system(.body, design: .monospaced))
                    .padding(.vertical, 2)
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("호출 기록 (창 내)").font(.headline)
                if skills.invocations.isEmpty {
                    Text("호출 없음").foregroundStyle(.secondary)
                } else {
                    tableHeader(["Skill", "Calls", "body chars"])
                    ForEach(skills.invocations) { row in
                        HStack {
                            Text(row.name).frame(maxWidth: .infinity, alignment: .leading)
                            Text("\(row.calls)").frame(width: 80, alignment: .trailing)
                            Text("\(row.bodyChars)").frame(width: 100, alignment: .trailing)
                        }
                        .font(.system(.body, design: .monospaced))
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("미호출 Skill (창 내)").font(.headline)
                Text("이 창에서 한 번도 호출되지 않음 — 제거/비활성 후보")
                    .font(.caption).foregroundStyle(.secondary)
                if skills.uninvokedNames.isEmpty {
                    Text("모두 호출됨").foregroundStyle(.secondary)
                } else {
                    Text("\(skills.uninvokedNames.count)개:")
                        .font(.system(.body, design: .monospaced))
                    Text(skills.uninvokedNames.joined(separator: ", "))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Hook

struct HookBreakdownView: View {
    let rows: [HookRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header("Hook 주입 — JSONL 저장 블록", accuracy: "⚠️ 하한선 (런타임 휘발 주입 미포함)")
            Text("실제 hook 주입은 대부분 API 전송 시점에 휘발되어 저장되지 않음. 아래 수치는 <system-reminder> 태그로 persist된 것만 집계.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if rows.isEmpty {
                Text("선택한 기간에 저장된 hook 블록 없음").foregroundStyle(.secondary)
            } else {
                tableHeader(["Category", "Blocks", "chars", "~ tokens"])
                ForEach(rows) { row in
                    HStack {
                        Text(row.category.rawValue).frame(maxWidth: .infinity, alignment: .leading)
                        Text("\(row.blocks)").frame(width: 70, alignment: .trailing)
                        Text("\(row.totalChars)").frame(width: 90, alignment: .trailing)
                        Text("\(row.approxTokens)").frame(width: 90, alignment: .trailing)
                    }
                    .font(.system(.body, design: .monospaced))
                }
            }
        }
    }
}

// MARK: - CLAUDE.md

struct ClaudeMdBreakdownView: View {
    let breakdown: ClaudeMdBreakdown

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header("CLAUDE.md 계층 + @-확장", accuracy: "📊 정적 파일 크기 기반 (세션당 1회 cache_create)")
            Text("총 확장 크기: \(breakdown.totalExpandedChars) chars ≈ \(breakdown.approxTokens) tokens")
                .font(.system(.body, design: .monospaced))
            if breakdown.layers.isEmpty {
                Text("CLAUDE.md 파일을 찾지 못함").foregroundStyle(.secondary)
            } else {
                ForEach(Array(breakdown.layers.enumerated()), id: \.offset) { _, layer in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(layer.path.path)
                            .font(.system(.body, design: .monospaced))
                            .lineLimit(1).truncationMode(.middle)
                        HStack {
                            Text("raw \(layer.rawChars)")
                            Text("expanded \(layer.expandedChars)")
                            if !layer.includes.isEmpty {
                                Text("+\(layer.includes.count) includes")
                            }
                        }
                        .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
            if !breakdown.cyclesDetected.isEmpty {
                Text("⚠️ cycles: \(breakdown.cyclesDetected.joined(separator: ", "))")
                    .font(.caption).foregroundStyle(.orange)
            }
            if !breakdown.missingReferences.isEmpty {
                Text("missing: \(breakdown.missingReferences.prefix(3).joined(separator: ", "))…")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
    }
}

// MARK: - shared bits

@ViewBuilder
private func header(_ title: String, accuracy: String) -> some View {
    HStack {
        Text(title).font(.headline)
        Spacer()
        Text(accuracy).font(.caption).foregroundStyle(.secondary)
    }
}

@ViewBuilder
private func tableHeader(_ titles: [String]) -> some View {
    HStack {
        ForEach(Array(titles.enumerated()), id: \.offset) { i, title in
            if i == 0 {
                Text(title).frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(title).frame(width: 90, alignment: .trailing)
            }
        }
    }
    .font(.caption)
    .foregroundStyle(.secondary)
    Divider().padding(.vertical, 2)
}
