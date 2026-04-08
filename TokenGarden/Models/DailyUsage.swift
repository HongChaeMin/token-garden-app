import Foundation
import SwiftData

@Model
class DailyUsage {
    @Attribute(.unique) var date: Date
    var inputTokens: Int
    var outputTokens: Int
    var cacheCreationTokens: Int
    var cacheReadTokens: Int
    var codexTokens: Int
    @Relationship(deleteRule: .cascade, inverse: \ProjectUsage.dailyUsage)
    var projectBreakdowns: [ProjectUsage]

    var totalTokens: Int {
        inputTokens + outputTokens + codexTokens
    }

    var claudeTokens: Int {
        inputTokens + outputTokens
    }

    init(date: Date) {
        self.date = date
        self.inputTokens = 0
        self.outputTokens = 0
        self.cacheCreationTokens = 0
        self.cacheReadTokens = 0
        self.codexTokens = 0
        self.projectBreakdowns = []
    }
}
