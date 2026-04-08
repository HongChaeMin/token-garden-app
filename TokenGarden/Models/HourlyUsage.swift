import Foundation
import SwiftData

@Model
class HourlyUsage {
    var date: Date
    var hour: Int
    var tokens: Int
    var source: String = "claude"

    init(date: Date, hour: Int, tokens: Int = 0, source: String = "claude") {
        self.date = date
        self.hour = hour
        self.tokens = tokens
        self.source = source
    }
}
