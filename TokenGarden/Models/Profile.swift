// TokenGarden/Models/Profile.swift
import Foundation
import SwiftData

enum PlanLimit {
    static let free = 500_000
    static let pro = 10_000_000
    static let max = 50_000_000

    static func defaultLimit(for plan: String) -> Int {
        switch plan.lowercased() {
        case "max": return max
        case "pro": return pro
        default: return free
        }
    }
}

enum ProfileColor: String, CaseIterable {
    case blue, green, orange, purple, pink, mint, red, yellow

    var color: Color {
        switch self {
        case .blue: return .blue
        case .green: return .green
        case .orange: return .orange
        case .purple: return .purple
        case .pink: return .pink
        case .mint: return .mint
        case .red: return .red
        case .yellow: return .yellow
        }
    }
}

import SwiftUI

@Model
class Profile {
    @Attribute(.unique) var name: String
    var email: String
    var plan: String
    var credentialsJSON: Data
    var isActive: Bool
    var createdAt: Date
    var monthlyLimit: Int
    var colorName: String

    init(name: String, email: String, plan: String, credentialsJSON: Data) {
        self.name = name
        self.email = email
        self.plan = plan
        self.credentialsJSON = credentialsJSON
        self.isActive = false
        self.createdAt = Date()
        self.monthlyLimit = PlanLimit.defaultLimit(for: plan)
        self.colorName = ProfileColor.blue.rawValue
    }

    var profileColor: Color {
        let colors = ProfileColor.allCases
        let hash = name.unicodeScalars.reduce(0) { $0 &+ Int($1.value) &* 31 }
        let index = abs(hash) % colors.count
        return colors[index].color
    }
}
