import Testing
import Foundation
@testable import TokenGarden

@Test func tokenEventTotalTokens() {
    let event = TokenEvent(
        timestamp: Date(),
        inputTokens: 100,
        outputTokens: 50,
        cacheCreationTokens: 200,
        cacheReadTokens: 30,
        model: "claude-opus-4-6",
        projectName: "my-project",
        sessionId: "test-session-123",
        source: "claude-code"
    )
    #expect(event.totalTokens == 150)  // input + output only
}
