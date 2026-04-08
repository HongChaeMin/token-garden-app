import Foundation
import SwiftData

@Model
class CodexProfile {
    @Attribute(.unique) var email: String
    var name: String
    var authData: Data
    var isActive: Bool
    var createdAt: Date

    init(name: String, email: String, authData: Data) {
        self.name = name
        self.email = email
        self.authData = authData
        self.isActive = false
        self.createdAt = Date()
    }
}
