import Foundation
import Testing
@testable import TokenGarden

// MARK: - HTTP transport stub

/// Stub transport that returns a preconfigured response or throws. Stores
/// each request so tests can assert the payload/headers sent.
/// Actor-based for Swift 6 strict concurrency compliance.
actor StubTransportState {
    var outcomes: [StubTransport.Outcome]
    private(set) var recordedRequests: [URLRequest] = []

    init(outcomes: [StubTransport.Outcome]) {
        self.outcomes = outcomes
    }

    func next(request: URLRequest) -> StubTransport.Outcome? {
        recordedRequests.append(request)
        guard !outcomes.isEmpty else { return nil }
        return outcomes.removeFirst()
    }

    func recorded() -> [URLRequest] { recordedRequests }
}

final class StubTransport: HTTPTransport, @unchecked Sendable {
    enum Outcome {
        case success(statusCode: Int, body: Data)
        case failure(Error)
    }

    let state: StubTransportState

    init(outcomes: [Outcome]) {
        self.state = StubTransportState(outcomes: outcomes)
    }

    var recordedRequests: [URLRequest] {
        get async { await state.recorded() }
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        guard let outcome = await state.next(request: request) else {
            throw URLError(.badServerResponse)
        }
        switch outcome {
        case .success(let status, let body):
            let resp = HTTPURLResponse(
                url: request.url!,
                statusCode: status,
                httpVersion: "HTTP/1.1",
                headerFields: ["content-type": "application/json"]
            )!
            return (body, resp)
        case .failure(let error):
            throw error
        }
    }
}

// MARK: - Helpers

private func makeTempCache() -> (TokenCountCache, URL) {
    let tmp = FileManager.default.temporaryDirectory
        .appendingPathComponent("tg-test-\(UUID().uuidString).json")
    return (TokenCountCache(url: tmp), tmp)
}

private func jsonBody(_ tokens: Int) -> Data {
    #"{"input_tokens":\#(tokens)}"#.data(using: .utf8)!
}

// MARK: - Fallback behavior (no API key)

@Test func fallbackReturnsApproxWhenNoApiKey() async {
    let (cache, url) = makeTempCache()
    defer { try? FileManager.default.removeItem(at: url) }
    let counter = TokenCounter(
        apiKey: nil,
        cache: cache,
        transport: StubTransport(outcomes: []),
        minIntervalSeconds: 0
    )
    let result = await counter.countText("hello world")
    #expect(result.isExact == false)
    #expect(result.cached == false)
    #expect(result.tokens >= 1)
}

@Test func fallbackScalesWithTextLength() async {
    let (cache, url) = makeTempCache()
    defer { try? FileManager.default.removeItem(at: url) }
    let counter = TokenCounter(
        apiKey: nil,
        cache: cache,
        transport: StubTransport(outcomes: []),
        minIntervalSeconds: 0
    )
    let short = await counter.countText("hi")
    let long = await counter.countText(String(repeating: "hi", count: 500))
    #expect(long.tokens > short.tokens)
}

@Test func fallbackForEmptyStringReturnsAtLeastOne() async {
    // 경계값 — 빈 입력
    let (cache, url) = makeTempCache()
    defer { try? FileManager.default.removeItem(at: url) }
    let counter = TokenCounter(
        apiKey: nil,
        cache: cache,
        transport: StubTransport(outcomes: []),
        minIntervalSeconds: 0
    )
    let result = await counter.countText("")
    #expect(result.tokens >= 1)
}

// MARK: - API success path

@Test func apiSuccessReturnsExactResult() async {
    let (cache, url) = makeTempCache()
    defer { try? FileManager.default.removeItem(at: url) }
    let transport = StubTransport(outcomes: [.success(statusCode: 200, body: jsonBody(42))])
    let counter = TokenCounter(
        apiKey: "sk-test",
        cache: cache,
        transport: transport,
        minIntervalSeconds: 0
    )
    let result = await counter.countText("hello")
    #expect(result.tokens == 42)
    #expect(result.isExact == true)
    #expect(result.cached == false)
    let recorded = await transport.recordedRequests
    #expect(recorded.count == 1)
    let req = recorded[0]
    #expect(req.value(forHTTPHeaderField: "x-api-key") == "sk-test")
    #expect(req.value(forHTTPHeaderField: "anthropic-version") == TokenCounter.apiVersion)
}

@Test func secondCallHitsCacheNotApi() async {
    let (cache, url) = makeTempCache()
    defer { try? FileManager.default.removeItem(at: url) }
    let transport = StubTransport(outcomes: [.success(statusCode: 200, body: jsonBody(99))])
    let counter = TokenCounter(
        apiKey: "sk-test",
        cache: cache,
        transport: transport,
        minIntervalSeconds: 0
    )
    _ = await counter.countText("cached input")
    let second = await counter.countText("cached input")
    #expect(second.tokens == 99)
    #expect(second.cached == true)
    let recorded = await transport.recordedRequests
    #expect(recorded.count == 1)
}

@Test func cachePersistsAcrossCounterInstances() async throws {
    let (_, url) = makeTempCache()
    defer { try? FileManager.default.removeItem(at: url) }
    let cache1 = TokenCountCache(url: url)
    let transport1 = StubTransport(outcomes: [.success(statusCode: 200, body: jsonBody(7))])
    let counter1 = TokenCounter(
        apiKey: "sk-test", cache: cache1, transport: transport1, minIntervalSeconds: 0
    )
    _ = await counter1.countText("persist me")

    // New counter with new cache instance pointing at same URL should hit disk cache
    let cache2 = TokenCountCache(url: url)
    let transport2 = StubTransport(outcomes: [])  // would throw if called
    let counter2 = TokenCounter(
        apiKey: "sk-test", cache: cache2, transport: transport2, minIntervalSeconds: 0
    )
    let result = await counter2.countText("persist me")
    #expect(result.tokens == 7)
    #expect(result.cached == true)
    let recorded = await transport2.recordedRequests
    #expect(recorded.isEmpty)
}

// MARK: - Failure modes

@Test func networkErrorFallsBackToApprox() async {
    let (cache, url) = makeTempCache()
    defer { try? FileManager.default.removeItem(at: url) }
    let transport = StubTransport(outcomes: [.failure(URLError(.notConnectedToInternet))])
    let counter = TokenCounter(
        apiKey: "sk-test",
        cache: cache,
        transport: transport,
        minIntervalSeconds: 0
    )
    let result = await counter.countText("still works")
    #expect(result.isExact == false)
    #expect(result.tokens >= 1)
}

@Test func httpErrorStatusFallsBackToApprox() async {
    let (cache, url) = makeTempCache()
    defer { try? FileManager.default.removeItem(at: url) }
    let transport = StubTransport(outcomes: [.success(statusCode: 500, body: Data())])
    let counter = TokenCounter(
        apiKey: "sk-test",
        cache: cache,
        transport: transport,
        minIntervalSeconds: 0
    )
    let result = await counter.countText("server down")
    #expect(result.isExact == false)
}

@Test func malformedJsonFallsBackToApprox() async {
    let (cache, url) = makeTempCache()
    defer { try? FileManager.default.removeItem(at: url) }
    let badBody = "not json".data(using: .utf8)!
    let transport = StubTransport(outcomes: [.success(statusCode: 200, body: badBody)])
    let counter = TokenCounter(
        apiKey: "sk-test",
        cache: cache,
        transport: transport,
        minIntervalSeconds: 0
    )
    let result = await counter.countText("corrupt response")
    #expect(result.isExact == false)
}

// MARK: - Payload helpers

@Test func cacheKeyIsStableForEquivalentPayloads() {
    let p1: [String: Any] = ["model": "claude-opus-4-7", "messages": [["role": "user", "content": "hi"]]]
    let p2: [String: Any] = ["messages": [["role": "user", "content": "hi"]], "model": "claude-opus-4-7"]
    #expect(TokenCounter.cacheKey(for: p1) == TokenCounter.cacheKey(for: p2))
}

@Test func cacheKeyDiffersForDifferentModels() {
    let p1: [String: Any] = ["model": "claude-opus-4-7", "messages": [["role": "user", "content": "hi"]]]
    let p2: [String: Any] = ["model": "claude-sonnet-4-6", "messages": [["role": "user", "content": "hi"]]]
    #expect(TokenCounter.cacheKey(for: p1) != TokenCounter.cacheKey(for: p2))
}

@Test func extractTextHandlesAllContentShapes() {
    let payload: [String: Any] = [
        "system": "system-prompt-text",
        "messages": [
            ["role": "user", "content": "plain-string"],
            ["role": "user", "content": [["type": "text", "text": "block-text"]]],
        ],
    ]
    let text = TokenCounter.extractText(payload)
    #expect(text.contains("system-prompt-text"))
    #expect(text.contains("plain-string"))
    #expect(text.contains("block-text"))
}
