import Testing
@testable import TokenGarden

@Test func heatmapLevelWithNoData() {
    let levels = HeatmapCalculator.calculateLevels(dailyTotals: [])
    #expect(levels.isEmpty)
}

@Test func heatmapLevelQuartiles() {
    let totals = [0, 100, 200, 300, 400, 500, 600, 700, 800, 900, 1000, 0]
    let levels = HeatmapCalculator.calculateLevels(dailyTotals: totals)

    #expect(levels.count == 12)
    #expect(levels[0] == 0)
    #expect(levels[11] == 0)
    #expect(levels[1] >= 1)
    #expect(levels[10] == 4)
}

@Test func heatmapLevelAllSameUsage() {
    let totals = [500, 500, 500, 500]
    let levels = HeatmapCalculator.calculateLevels(dailyTotals: totals)
    for level in levels {
        #expect(level == 4)
    }
}
