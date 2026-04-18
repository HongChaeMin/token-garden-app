import SwiftUI

/// Top-level container for the 4 structural breakdown sub-tabs
/// (MCP / Skill / Hook / CLAUDE.md). Typography mirrors the rest of the
/// app — `.caption` / `.caption2` / `.system(size:)` with monospacedDigit
/// for numeric columns — so the Breakdown tab feels native to the popover.
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
        VStack(alignment: .leading, spacing: 6) {
            Picker("", selection: $window) {
                ForEach(TimeWindow.allCases) { w in
                    Text(shortLabel(w)).tag(w)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .padding(.horizontal, 12)

            Picker("", selection: $dimension) {
                ForEach(Dimension.allCases) { d in
                    Text(d.rawValue).tag(d)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .padding(.horizontal, 12)

            if loader.isLoading {
                HStack(spacing: 4) {
                    ProgressView().controlSize(.small)
                    Text("Loading…").font(.caption2).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
            }
            if let err = loader.errorMessage {
                Text(err)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .padding(.horizontal, 12)
            }

            Divider()

            // Each sub-view manages its own scrolling so the overall popover
            // height stays bounded. Skill especially needs this because
            // uninvoked skill lists can be hundreds of items long.
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
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                }
            }
        }
        .padding(.vertical, 8)
        .frame(height: 480)
        .onAppear { loader.load(window: window) }
        .onChange(of: window) { _, newValue in loader.load(window: newValue) }
    }

    private func shortLabel(_ w: TimeWindow) -> String {
        switch w {
        case .day:   return "Today"
        case .week:  return "Week"
        case .month: return "Month"
        }
    }
}

// MARK: - shared components

private struct SectionHeader: View {
    let title: String
    let badge: String
    var body: some View {
        HStack {
            Text(title).font(.caption).fontWeight(.semibold)
            Spacer()
            Text(badge).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

private struct TableHeader: View {
    let titles: [(String, CGFloat?)]  // nil width = flex
    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(titles.enumerated()), id: \.offset) { _, pair in
                if let w = pair.1 {
                    Text(pair.0)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .frame(width: w, alignment: .trailing)
                } else {
                    Text(pair.0)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

// MARK: - MCP

struct MCPBreakdownView: View {
    let rows: [MCPServerRow]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                SectionHeader(title: "MCP 호출", badge: "📊 input chars")
                if rows.isEmpty {
                    Text("선택한 기간에 MCP 호출 없음")
                        .font(.caption2).foregroundStyle(.secondary)
                } else {
                    TableHeader(titles: [
                        ("Server", nil), ("Calls", 44), ("~tok", 52), ("avg", 44),
                    ])
                    ForEach(rows) { row in
                        HStack(spacing: 4) {
                            Text(displayName(row.server))
                                .font(.caption2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Text("\(row.calls)")
                                .font(.system(size: 10).monospacedDigit())
                                .frame(width: 44, alignment: .trailing)
                            Text("\(row.approxTokens)")
                                .font(.system(size: 10).monospacedDigit())
                                .frame(width: 52, alignment: .trailing)
                            Text("\(row.averageInputChars)")
                                .font(.system(size: 10).monospacedDigit())
                                .frame(width: 44, alignment: .trailing)
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
        }
    }

    /// Strip the `plugin_` prefix for display — 75% of servers share it.
    private func displayName(_ raw: String) -> String {
        raw.hasPrefix("plugin_") ? String(raw.dropFirst("plugin_".count)) : raw
    }
}

// MARK: - Skill

struct SkillBreakdownView: View {
    let skills: SkillsBreakdown

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Fixed header — always visible
            VStack(alignment: .leading, spacing: 2) {
                SectionHeader(title: "Skill breakdown", badge: "📊 파일 기반")
                Text("설치 baseline").font(.caption).fontWeight(.semibold)
                Text("매 세션 system prompt에 포함되는 name+description 합")
                    .font(.caption2).foregroundStyle(.secondary)
                let tokens = BakedCalibration.estimate(skills.baselineChars, as: .skillMarkdown)
                Text("≈ \(tokens) tok · \(skills.baselineChars) chars · \(skills.installed.count)개")
                    .font(.system(size: 10).monospacedDigit())
            }
            .padding(.horizontal, 12)

            Divider()

            // Invocations — fixed height scroll window
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("호출 기록").font(.caption).fontWeight(.semibold)
                    Spacer()
                    Text("\(skills.invocations.count)개")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)

                if skills.invocations.isEmpty {
                    Text("호출 없음")
                        .font(.caption2).foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                } else {
                    TableHeader(titles: [("Skill", nil), ("Calls", 44), ("body", 60)])
                        .padding(.horizontal, 12)
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(skills.invocations) { row in
                                HStack(spacing: 4) {
                                    Text(row.name)
                                        .font(.caption2)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    Text("\(row.calls)")
                                        .font(.system(size: 10).monospacedDigit())
                                        .frame(width: 44, alignment: .trailing)
                                    Text("\(row.bodyChars)")
                                        .font(.system(size: 10).monospacedDigit())
                                        .frame(width: 60, alignment: .trailing)
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                    }
                    .frame(height: 160)
                }
            }

            Divider()

            // Uninvoked — fixed height scroll window
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("미호출 Skill").font(.caption).fontWeight(.semibold)
                    Spacer()
                    Text("\(skills.uninvokedNames.count)개")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                Text("창 내 호출 없음 — 제거 후보")
                    .font(.caption2).foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                if skills.uninvokedNames.isEmpty {
                    Text("모두 호출됨")
                        .font(.caption2).foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(skills.uninvokedNames, id: \.self) { name in
                                Text(name)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                        .padding(.horizontal, 12)
                    }
                    .frame(maxHeight: .infinity)
                }
            }
        }
    }
}

// MARK: - Hook

struct HookBreakdownView: View {
    let rows: [HookRow]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                SectionHeader(title: "Hook 주입", badge: "⚠️ 하한선")
                Text("runtime 휘발 주입 제외. JSONL 저장분만.")
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if rows.isEmpty {
                    Text("저장된 hook 블록 없음")
                        .font(.caption2).foregroundStyle(.secondary)
                } else {
                    TableHeader(titles: [
                        ("Category", nil), ("Blk", 36), ("chars", 56), ("~tok", 52),
                    ])
                    ForEach(rows) { row in
                        HStack(spacing: 4) {
                            Text(row.category.rawValue)
                                .font(.caption2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Text("\(row.blocks)")
                                .font(.system(size: 10).monospacedDigit())
                                .frame(width: 36, alignment: .trailing)
                            Text("\(row.totalChars)")
                                .font(.system(size: 10).monospacedDigit())
                                .frame(width: 56, alignment: .trailing)
                            Text("\(row.approxTokens)")
                                .font(.system(size: 10).monospacedDigit())
                                .frame(width: 52, alignment: .trailing)
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
        }
    }
}

// MARK: - CLAUDE.md

struct ClaudeMdBreakdownView: View {
    let breakdown: ClaudeMdBreakdown

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                SectionHeader(title: "CLAUDE.md 계층", badge: "📊 파일 크기")
            Text("≈ \(breakdown.approxTokens) tok · \(breakdown.totalExpandedChars) chars")
                .font(.system(size: 10).monospacedDigit())
            if breakdown.layers.isEmpty {
                Text("CLAUDE.md 파일을 찾지 못함")
                    .font(.caption2).foregroundStyle(.secondary)
            } else {
                ForEach(Array(breakdown.layers.enumerated()), id: \.offset) { _, layer in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(layer.path.path)
                            .font(.system(size: 9))
                            .lineLimit(1).truncationMode(.middle)
                        HStack(spacing: 8) {
                            Text("raw \(layer.rawChars)")
                            Text("exp \(layer.expandedChars)")
                            if !layer.includes.isEmpty {
                                Text("+\(layer.includes.count) inc")
                            }
                        }
                        .font(.system(size: 9).monospacedDigit())
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
            if !breakdown.cyclesDetected.isEmpty {
                Text("⚠️ cycles: \(breakdown.cyclesDetected.joined(separator: ", "))")
                    .font(.caption2).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !breakdown.missingReferences.isEmpty {
                Text("missing: \(breakdown.missingReferences.prefix(3).joined(separator: ", "))…")
                    .font(.caption2).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            }
            .padding(.horizontal, 12)
        }
    }
}
