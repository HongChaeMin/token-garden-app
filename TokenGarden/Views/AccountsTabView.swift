import SwiftUI
import SwiftData

struct AccountsTabView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ModelBreakdownView()
                .padding(.horizontal, 12)
            AccountStatsView()
                .padding(.horizontal, 12)
            AccountDailyChartView()
                .padding(.horizontal, 12)
        }
        .padding(.vertical, 12)
    }
}

// MARK: - Shared Helpers

private func normalizeModel(_ raw: String) -> String? {
    let lower = raw.lowercased()
    if lower.contains("opus") { return "Opus" }
    if lower.contains("sonnet") { return "Sonnet" }
    if lower.contains("haiku") { return "Haiku" }
    return nil
}

private func modelColor(_ model: String) -> Color {
    switch model {
    case "Opus": return .purple
    case "Sonnet": return .orange
    case "Haiku": return .mint
    default: return .gray
    }
}

// MARK: - Model Breakdown (overall)

private struct ModelBreakdownView: View {
    @Query private var allProjectUsages: [ProjectUsage]

    private var modelTokens: [(model: String, tokens: Int)] {
        var totals: [String: Int] = [:]
        for usage in allProjectUsages {
            guard let model = normalizeModel(usage.model ?? "") else { continue }
            totals[model, default: 0] += usage.tokens
        }
        return totals.map { (model: $0.key, tokens: $0.value) }
            .filter { $0.tokens > 0 }
            .sorted { $0.tokens > $1.tokens }
    }

    private var totalTokens: Int {
        modelTokens.reduce(0) { $0 + $1.tokens }
    }

    var body: some View {
        if !modelTokens.isEmpty && totalTokens > 0 {
            VStack(alignment: .leading, spacing: 6) {
                Text("Model Usage")
                    .font(.caption)
                    .fontWeight(.medium)

                GeometryReader { geo in
                    HStack(spacing: 1) {
                        ForEach(modelTokens, id: \.model) { item in
                            let ratio = Double(item.tokens) / Double(totalTokens)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(modelColor(item.model))
                                .frame(width: max(geo.size.width * ratio - 1, 2))
                        }
                    }
                }
                .frame(height: 6)
                .clipShape(RoundedRectangle(cornerRadius: 3))

                HStack(spacing: 10) {
                    ForEach(modelTokens, id: \.model) { item in
                        let pct = Double(item.tokens) / Double(totalTokens) * 100
                        HStack(spacing: 3) {
                            Circle()
                                .fill(modelColor(item.model))
                                .frame(width: 5, height: 5)
                            Text("\(item.model) \(String(format: "%.0f", pct))%")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }
            }
            .padding(8)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
        }
    }
}

// MARK: - Account Stats (Today / Week / Month per account)

private struct AccountStatsView: View {
    @Query private var allProfileUsages: [ProfileTokenUsage]
    @Query private var allProjectUsages: [ProjectUsage]
    @State private var isExpanded = false

    private var calendar: Calendar { Calendar.current }

    private var today: Date { calendar.startOfDay(for: Date()) }

    private var weekStart: Date {
        var cal = calendar
        cal.firstWeekday = 2
        return cal.dateComponents([.calendar, .yearForWeekOfYear, .weekOfYear], from: Date()).date!
    }

    private var monthStart: Date {
        let comps = calendar.dateComponents([.year, .month], from: Date())
        return calendar.date(from: comps)!
    }

    private var profileNames: [String] {
        Array(Set(allProfileUsages.map(\.profileName))).sorted()
    }

    private func tokens(for profile: String, from start: Date) -> Int {
        allProfileUsages
            .filter { $0.profileName == profile && $0.date >= start }
            .reduce(0) { $0 + $1.tokens }
    }

    private func modelBreakdown(for profile: String) -> [(model: String, tokens: Int)] {
        var totals: [String: Int] = [:]
        for usage in allProjectUsages {
            guard usage.profileName == profile,
                  let model = normalizeModel(usage.model ?? "") else { continue }
            totals[model, default: 0] += usage.tokens
        }
        return totals.map { (model: $0.key, tokens: $0.value) }
            .filter { $0.tokens > 0 }
            .sorted { $0.tokens > $1.tokens }
    }

    var body: some View {
        if !profileNames.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label("Account Stats", systemImage: "chart.bar.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if !isExpanded {
                        Text("\(profileNames.count) accounts")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .contentShape(Rectangle())
                .onTapGesture { isExpanded.toggle() }

                if isExpanded {
                    ForEach(profileNames, id: \.self) { profile in
                        accountCard(profile)
                    }
                }
            }
            .padding(8)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func accountCard(_ profile: String) -> some View {
        let todayT = tokens(for: profile, from: today)
        let weekT = tokens(for: profile, from: weekStart)
        let monthT = tokens(for: profile, from: monthStart)
        let models = modelBreakdown(for: profile)
        let total = models.reduce(0) { $0 + $1.tokens }

        return VStack(alignment: .leading, spacing: 4) {
            Text(profile)
                .font(.caption)
                .fontWeight(.medium)

            // Model bar
            if !models.isEmpty && total > 0 {
                GeometryReader { geo in
                    HStack(spacing: 1) {
                        ForEach(models, id: \.model) { item in
                            let ratio = Double(item.tokens) / Double(total)
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(modelColor(item.model))
                                .frame(width: max(geo.size.width * ratio - 1, 2))
                        }
                    }
                }
                .frame(height: 4)
                .clipShape(RoundedRectangle(cornerRadius: 2))

                HStack(spacing: 6) {
                    ForEach(models, id: \.model) { item in
                        HStack(spacing: 2) {
                            Circle().fill(modelColor(item.model)).frame(width: 4, height: 4)
                            Text("\(String(format: "%.0f", Double(item.tokens) / Double(total) * 100))%")
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    Spacer()
                }
            }

            // Day / Week / Month
            HStack(spacing: 0) {
                statCell(label: "Today", value: todayT)
                statCell(label: "Week", value: weekT)
                statCell(label: "Month", value: monthT)
            }
        }
        .padding(6)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 4))
    }

    private func statCell(label: String, value: Int) -> some View {
        VStack(spacing: 1) {
            Text(TokenFormatter.format(value))
                .font(.system(size: 10).monospacedDigit())
                .fontWeight(.medium)
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Account Daily Chart (bar chart per account, last 28 days)

private struct AccountDailyChartView: View {
    @Query private var allProfileUsages: [ProfileTokenUsage]
    @Query private var allProfiles: [Profile]
    @State private var isExpanded = false
    @State private var hoveredDay: Int?

    private let dayCount = 28

    private var profileNames: [String] {
        Array(Set(allProfileUsages.map(\.profileName))).sorted()
    }

    private func colorForProfile(_ name: String) -> Color {
        allProfiles.first(where: { $0.name == name })?.profileColor ?? .blue
    }


    private func dailyTokens(for profile: String) -> [Int] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        var usageByDate: [Date: Int] = [:]
        for usage in allProfileUsages where usage.profileName == profile {
            let day = calendar.startOfDay(for: usage.date)
            usageByDate[day, default: 0] += usage.tokens
        }

        var result: [Int] = []
        for i in (0..<dayCount).reversed() {
            let date = calendar.date(byAdding: .day, value: -i, to: today)!
            result.append(usageByDate[date] ?? 0)
        }
        return result
    }

    private var dayLabels: [String] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let fmt = DateFormatter()
        fmt.dateFormat = "M/d"
        return (0..<dayCount).reversed().map { i in
            let date = calendar.date(byAdding: .day, value: -i, to: today)!
            return fmt.string(from: date)
        }
    }

    var body: some View {
        if !profileNames.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label("Daily Trend", systemImage: "chart.bar.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if !isExpanded {
                        Text("28 days")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .contentShape(Rectangle())
                .onTapGesture { isExpanded.toggle() }

                if isExpanded {
                    ForEach(profileNames, id: \.self) { profile in
                        profileChart(profile, color: colorForProfile(profile))
                    }
                }
            }
            .padding(8)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func profileChart(_ profile: String, color: Color) -> some View {
        let tokens = dailyTokens(for: profile)
        let maxVal = tokens.max() ?? 1

        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(profile)
                    .font(.caption2)
                    .fontWeight(.medium)
                Spacer()
                if let day = hoveredDay, day < tokens.count {
                    Text("\(dayLabels[day])  \(TokenFormatter.format(tokens[day]))")
                        .font(.system(size: 9).monospacedDigit())
                        .foregroundStyle(.secondary)
                } else {
                    Text(TokenFormatter.format(tokens.reduce(0, +)))
                        .font(.system(size: 9).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            GeometryReader { geo in
                let barSpacing: CGFloat = 1
                let barWidth = max(1, (geo.size.width - barSpacing * CGFloat(dayCount - 1)) / CGFloat(dayCount))
                let chartHeight = geo.size.height

                HStack(alignment: .bottom, spacing: barSpacing) {
                    ForEach(0..<dayCount, id: \.self) { day in
                        let t = tokens[day]
                        let barH = maxVal > 0
                            ? max(t > 0 ? 2 : 0, chartHeight * CGFloat(t) / CGFloat(maxVal))
                            : CGFloat(0)
                        let ratio = maxVal > 0 ? Double(t) / Double(maxVal) : 0

                        VStack(spacing: 0) {
                            Spacer(minLength: 0)
                            RoundedRectangle(cornerRadius: 1)
                                .fill(hoveredDay == day ? color : color.opacity(0.3 + 0.7 * ratio))
                                .frame(width: barWidth, height: barH)
                        }
                        .frame(height: chartHeight)
                        .onHover { isHovered in
                            hoveredDay = isHovered ? day : nil
                        }
                    }
                }
            }
            .frame(height: 48)

            // X-axis labels
            HStack {
                Text(dayLabels.first ?? "")
                Spacer()
                Text(dayLabels[dayCount / 2])
                Spacer()
                Text(dayLabels.last ?? "")
            }
            .font(.system(size: 8))
            .foregroundStyle(.tertiary)
        }
        .padding(6)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 4))
    }
}
