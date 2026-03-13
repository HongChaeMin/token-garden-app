import Foundation

struct TokenEvent: Sendable {
    let timestamp: Date
    let inputTokens: Int
    let outputTokens: Int
    let cacheCreationTokens: Int
    let cacheReadTokens: Int
    let model: String?
    let projectName: String?
    let sessionId: String?
    let source: String

    var totalTokens: Int {
        inputTokens + outputTokens
    }
}
