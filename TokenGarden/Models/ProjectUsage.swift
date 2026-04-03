import Foundation
import SwiftData

@Model
class ProjectUsage {
    var projectName: String
    var tokens: Int
    var model: String?
    var profileName: String?
    var dailyUsage: DailyUsage?

    init(projectName: String, tokens: Int, model: String? = nil, profileName: String? = nil) {
        self.projectName = projectName
        self.tokens = tokens
        self.model = model
        self.profileName = profileName
    }
}
