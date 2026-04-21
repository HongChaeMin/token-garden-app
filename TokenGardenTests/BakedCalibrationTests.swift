import Foundation
import Testing
@testable import TokenGarden

@Test func everyCategoryHasARatio() {
    // enum/ratios dict must stay in lock-step or token estimates silently wrong
    for cat in BakedCalibration.Category.allCases {
        #expect(BakedCalibration.ratios[cat] != nil)
    }
}

@Test func ratioMeansAreWithinReasonableBand() {
    // Sanity bounds — tokenizer ratios for text are never <1.5 or >5.
    // Catches accidental zero/overflow if the generator regresses.
    for (_, ratio) in BakedCalibration.ratios {
        #expect(ratio.mean > 1.5)
        #expect(ratio.mean < 5.0)
    }
}

@Test func estimateScalesLinearlyWithChars() {
    let small = BakedCalibration.estimate(100, as: .skillMarkdown)
    let large = BakedCalibration.estimate(10_000, as: .skillMarkdown)
    #expect(large > small * 90)  // ~100x within rounding
    #expect(large < small * 110)
}

@Test func estimateForZeroCharsIsZero() {
    // 경계값 — 빈 입력
    #expect(BakedCalibration.estimate(0, as: .skillMarkdown) == 0)
    #expect(BakedCalibration.estimate(0, as: .claudeMdProse) == 0)
    #expect(BakedCalibration.estimate(0, as: .mcpToolSchema) == 0)
    #expect(BakedCalibration.estimate(0, as: .systemReminder) == 0)
}

@Test func differentCategoriesProduceDifferentEstimates() {
    // Baked ratios should differ per category — if they collapse to one
    // value, calibration generation regressed.
    let chars = 10_000
    let skill = BakedCalibration.estimate(chars, as: .skillMarkdown)
    let json = BakedCalibration.estimate(chars, as: .mcpToolSchema)
    #expect(skill != json)
    // skill ratio (2.9) is smaller → more tokens; mcp ratio (3.8) larger → fewer tokens
    #expect(skill > json)
}

@Test func confidenceHalfWidthIsZeroWhenNIsZero() {
    // 에러 케이스 — heuristic ratios have n=0, CI half-width must be 0
    let ratio = BakedCalibration.skillMarkdownRatio
    #expect(ratio.n == 0)  // heuristic marker
    #expect(ratio.confidenceHalfWidth(chars: 10_000) == 0)
}

@Test func defaultFallbackRatioUsedForUnmappedCharCountIsSane() {
    // If `ratios` dictionary were empty (it isn't — guarded by first test)
    // `estimate` falls back to Ratio(mean:3). Simulate by constructing a
    // Ratio with mean 0 → inner fallback of chars/3.
    let degenerate = BakedCalibration.Ratio(mean: 0, stddev: 0, min: 0, max: 0, n: 0)
    // chars=300 → chars/3=100
    #expect(degenerate.estimateTokens(chars: 300) == 100)
}
