import SwiftUI

enum HeatmapCalculator {
    static func calculateLevels(dailyTotals: [Int]) -> [Int] {
        guard !dailyTotals.isEmpty else { return [] }

        let nonZero = dailyTotals.filter { $0 > 0 }.sorted()
        guard !nonZero.isEmpty else {
            return dailyTotals.map { _ in 0 }
        }

        let maxVal = nonZero.last!
        let q1 = nonZero[nonZero.count / 4]
        let q2 = nonZero[nonZero.count / 2]
        let q3 = nonZero[nonZero.count * 3 / 4]

        return dailyTotals.map { total in
            if total == 0 { return 0 }
            if total == maxVal { return 4 }
            if total <= q1 { return 1 }
            if total <= q2 { return 2 }
            if total <= q3 { return 3 }
            return 4
        }
    }
}

struct HeatmapView: View {
    let dailyUsages: [(date: Date, tokens: Int)]
    @Binding var selectedDate: Date?
    private let columns = 12
    private let rows = 7
    private let cellSize: CGFloat = 16
    private let spacing: CGFloat = 2

    private let dayLabels = ["", "Mon", "", "Wed", "", "Fri", ""]

    private let colors: [Color] = [
        Color(.systemGray).opacity(0.15),
        Color.green.opacity(0.3),
        Color.green.opacity(0.5),
        Color.green.opacity(0.7),
        Color.green,
    ]

    var body: some View {
        let gridData = buildGrid()

        VStack(alignment: .leading, spacing: 0) {
            // Month labels
            HStack(spacing: 0) {
                // Spacer for day label column
                Text("")
                    .frame(width: 28)

                let monthLabels = buildMonthLabels(gridData: gridData)
                ForEach(monthLabels, id: \.offset) { label in
                    Text(label.text)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .frame(width: CGFloat(label.span) * (cellSize + spacing), alignment: .leading)
                }
            }
            .padding(.bottom, 2)

            // Grid with day labels
            HStack(alignment: .top, spacing: 4) {
                // Day labels
                VStack(spacing: spacing) {
                    ForEach(0..<rows, id: \.self) { row in
                        Text(dayLabels[row])
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .frame(width: 24, height: cellSize, alignment: .trailing)
                    }
                }

                // Grid cells
                VStack(alignment: .leading, spacing: spacing) {
                    ForEach(0..<rows, id: \.self) { row in
                        HStack(spacing: spacing) {
                            ForEach(0..<columns, id: \.self) { col in
                                let index = col * rows + row
                                if index < gridData.count {
                                    let cell = gridData[index]
                                    let isSelected = selectedDate != nil &&
                                        Calendar.current.isDate(cell.date, inSameDayAs: selectedDate!)
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(colors[cell.level])
                                        .frame(width: cellSize, height: cellSize)
                                        .overlay(
                                            isSelected ?
                                                RoundedRectangle(cornerRadius: 2)
                                                    .stroke(Color.primary, lineWidth: 1.5) : nil
                                        )
                                        .help(cell.tooltip)
                                        .onTapGesture {
                                            withAnimation(.easeInOut(duration: 0.15)) {
                                                if isSelected {
                                                    selectedDate = nil
                                                } else {
                                                    selectedDate = cell.date
                                                }
                                            }
                                        }
                                } else {
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(Color.gray.opacity(0.1))
                                        .frame(width: cellSize, height: cellSize)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private struct GridCell {
        let date: Date
        let tokens: Int
        let level: Int
        let tooltip: String
    }

    private struct MonthLabel {
        let text: String
        let span: Int
        let offset: Int
    }

    private func buildGrid() -> [GridCell] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let totalDays = columns * rows

        let startDate = calendar.date(byAdding: .day, value: -(totalDays - 1), to: today)!

        var usageByDate: [Date: Int] = [:]
        for usage in dailyUsages {
            let day = calendar.startOfDay(for: usage.date)
            usageByDate[day] = (usageByDate[day] ?? 0) + usage.tokens
        }

        var totals: [Int] = []
        var dates: [Date] = []
        for i in 0..<totalDays {
            let date = calendar.date(byAdding: .day, value: i, to: startDate)!
            dates.append(date)
            totals.append(usageByDate[date] ?? 0)
        }
        let gridLevels = HeatmapCalculator.calculateLevels(dailyTotals: totals)

        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium

        var grid: [GridCell] = []
        for i in 0..<totalDays {
            let tooltip = "\(dateFormatter.string(from: dates[i])): \(TokenFormatter.format(totals[i]))"
            grid.append(GridCell(
                date: dates[i],
                tokens: totals[i],
                level: i < gridLevels.count ? gridLevels[i] : 0,
                tooltip: tooltip
            ))
        }

        return grid
    }

    private func buildMonthLabels(gridData: [GridCell]) -> [MonthLabel] {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"

        var labels: [MonthLabel] = []
        var currentMonth = -1
        var currentSpan = 0
        var labelOffset = 0

        for col in 0..<columns {
            let index = col * rows // first day of the column (Sunday/Monday)
            guard index < gridData.count else { break }
            let month = calendar.component(.month, from: gridData[index].date)

            if month != currentMonth {
                if currentMonth != -1 {
                    labels.append(MonthLabel(text: formatter.string(from: gridData[(col - currentSpan) * rows].date),
                                             span: currentSpan, offset: labelOffset))
                    labelOffset += currentSpan
                }
                currentMonth = month
                currentSpan = 1
            } else {
                currentSpan += 1
            }
        }
        // Last month
        if currentSpan > 0 {
            let col = columns - currentSpan
            let index = col * rows
            if index < gridData.count {
                labels.append(MonthLabel(text: formatter.string(from: gridData[index].date),
                                         span: currentSpan, offset: labelOffset))
            }
        }

        return labels
    }
}
