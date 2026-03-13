import Foundation
import SwiftData

@Model
class SessionUsage {
    @Attribute(.unique) var sessionId: String
    var projectName: String
    var totalTokens: Int
    var startTime: Date
    var lastTime: Date
    var isActive: Bool = true

    init(sessionId: String, projectName: String, startTime: Date) {
        self.sessionId = sessionId
        self.projectName = projectName
        self.totalTokens = 0
        self.startTime = startTime
        self.lastTime = startTime
        self.isActive = true
    }
}
