import SwiftUI

struct HourlyChartView: View {
    let hourlyTokens: [Int]
    var isToday: Bool = true
    @State private var isExpanded = false
    @State private var hoveredHour: Int?

    @AppStorage("heatmapTheme") private var themeName = HeatmapTheme.green.rawValue
    private var themeColor: Color {
        (HeatmapTheme(rawValue: themeName) ?? .green).colors[7]
    }

    private var maxTokens: Int {
        hourlyTokens.max() ?? 1
    }

    private var currentHour: Int {
        Calendar.current.component(.hour, from: Date())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Hourly", systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if !isExpanded, let peak = peakHourLabel {
                    Text(peak)
                        .font(.caption)
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
                VStack(spacing: 4) {
                    chartWithTooltip
                        .frame(height: 64)

                    HStack {
                        Text("0")
                        Spacer()
                        Text("6")
                        Spacer()
                        Text("12")
                        Spacer()
                        Text("18")
                        Spacer()
                        Text("23")
                    }
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private var chartWithTooltip: some View {
        GeometryReader { geo in
            let spacing: CGFloat = 1
            let barWidth = max(1, (geo.size.width - spacing * 23) / 24)
            let barStep = barWidth + spacing
            let chartHeight = geo.size.height
            let tooltipWidth: CGFloat = 90

            // Bars
            HStack(alignment: .bottom, spacing: spacing) {
                ForEach(0..<24, id: \.self) { hour in
                    let tokens = hourlyTokens[hour]
                    let barH = maxTokens > 0
                        ? max(tokens > 0 ? 2 : 0, chartHeight * CGFloat(tokens) / CGFloat(maxTokens))
                        : CGFloat(0)

                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(barColor(for: hour))
                            .frame(width: barWidth, height: barH)
                            .onHover { isHovered in
                                hoveredHour = isHovered ? hour : nil
                            }
                    }
                    .frame(height: chartHeight)
                }
            }

            // Tooltip floating above the hovered bar's top
            if let hour = hoveredHour {
                let tokens = hourlyTokens[hour]
                let barH = maxTokens > 0
                    ? max(tokens > 0 ? 2 : 0, chartHeight * CGFloat(tokens) / CGFloat(maxTokens))
                    : CGFloat(0)
                let barCenter = barStep * CGFloat(hour) + barWidth / 2
                let idealX = barCenter - tooltipWidth / 2
                let clampedX = min(max(idealX, 0), geo.size.width - tooltipWidth)
                let tooltipY = chartHeight - barH - 18

                Text("\(String(format: "%02d", hour)):00  \(TokenFormatter.format(hourlyTokens[hour]))")
                    .font(.system(size: 9).monospacedDigit())
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 3))
                    .fixedSize()
                    .frame(width: tooltipWidth, alignment: .center)
                    .position(x: clampedX + tooltipWidth / 2, y: max(tooltipY, 6))
                    .allowsHitTesting(false)
            }
        }
    }

    private func barColor(for hour: Int) -> Color {
        if hour == hoveredHour {
            return themeColor
        }
        let tokens = hourlyTokens[hour]
        guard tokens > 0, maxTokens > 0 else { return themeColor.opacity(0.2) }
        let ratio = Double(tokens) / Double(maxTokens)
        return themeColor.opacity(0.25 + 0.75 * ratio)
    }

    private var peakHourLabel: String? {
        guard let peak = hourlyTokens.enumerated().max(by: { $0.element < $1.element }),
              peak.element > 0 else { return nil }
        return "Peak \(String(format: "%02d", peak.offset)):00"
    }
}
