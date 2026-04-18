import CryptoKit
import Foundation

/// Result of a token-count query. `isExact` distinguishes authoritative
/// Anthropic API counts from char-based fallback estimates so the UI can
/// badge appropriately (📊 vs ≈).
struct TokenCountResult: Equatable {
    let tokens: Int
    let isExact: Bool
    let cached: Bool
}

/// Errors that surface to callers. Network/HTTP failures are swallowed
/// internally and converted to `.fallback` results — only programmer
/// errors (malformed input) throw.
enum TokenCounterError: Error {
    case invalidPayload
}

/// Wrapper around Anthropic's free `/v1/messages/count_tokens` endpoint
/// (https://platform.claude.com/docs/en/api/messages-count-tokens).
///
/// - Caches results by SHA-256 of the request payload in a JSON file under
///   `~/Library/Caches/TokenGarden/token_counts.json`.
/// - Spaces API calls by `minInterval` seconds to respect rate limits
///   (Tier 1 = 100 RPM → 0.6 s minimum).
/// - Falls back to char-based estimation (≈3.5 chars/token) when no API
///   key is configured or when the API call fails. Fallback results are
///   **not cached** so a later key install can upgrade accuracy.
///
/// The struct is a value type; state lives in the injected `cacheStore`
/// and the in-memory `session` (an `Actor` guarding the last-call timestamp
/// and rate-limit sleep).
actor TokenCounterSession {
    private var lastCallAt: Date?
    private let minInterval: TimeInterval

    init(minInterval: TimeInterval) {
        self.minInterval = minInterval
    }

    /// Sleeps just long enough to keep successive calls spaced by
    /// `minInterval`. Safe to call from any task — actor serializes access.
    func waitForSlot() async {
        let now = Date()
        if let last = lastCallAt {
            let elapsed = now.timeIntervalSince(last)
            if elapsed < minInterval {
                let remaining = minInterval - elapsed
                try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
            }
        }
        lastCallAt = Date()
    }
}

/// Persistent cache for token counts keyed by SHA-256 of the request
/// payload. Stored as a single JSON dictionary on disk — simple, durable,
/// and human-readable for debugging.
final class TokenCountCache {
    private let url: URL
    private var store: [String: CacheEntry] = [:]
    private let lock = NSLock()

    struct CacheEntry: Codable {
        let tokens: Int
        let model: String
        let cachedAt: Date
    }

    init(url: URL) {
        self.url = url
        load()
    }

    private func load() {
        guard let data = try? Data(contentsOf: url) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        store = (try? decoder.decode([String: CacheEntry].self, from: data)) ?? [:]
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(store) else { return }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: url)
    }

    func get(_ key: String) -> CacheEntry? {
        lock.lock()
        defer { lock.unlock() }
        return store[key]
    }

    func set(_ key: String, _ entry: CacheEntry) {
        lock.lock()
        store[key] = entry
        lock.unlock()
        save()
    }
}

/// Protocol for injecting HTTP transport so tests can swap in a stub
/// without touching the network. Matches `URLSession.data(for:)` shape.
protocol HTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: HTTPTransport {}

struct TokenCounter {
    static let defaultModel = "claude-opus-4-7"
    static let endpoint = URL(string: "https://api.anthropic.com/v1/messages/count_tokens")!
    static let apiVersion = "2023-06-01"
    /// ≈ 3.5 chars/token is a rough heuristic for mixed English/Korean text.
    /// Used only when API access is unavailable.
    static let fallbackCharsPerToken: Double = 3.5

    let model: String
    let apiKey: String?
    let cache: TokenCountCache
    let transport: HTTPTransport
    let session: TokenCounterSession

    init(
        model: String = TokenCounter.defaultModel,
        apiKey: String? = nil,
        cache: TokenCountCache? = nil,
        transport: HTTPTransport = URLSession.shared,
        minIntervalSeconds: TimeInterval = 0.6
    ) {
        self.model = model
        self.apiKey = apiKey ?? Self.resolvedApiKey()
        self.cache = cache ?? TokenCountCache(url: Self.defaultCacheURL())
        self.transport = transport
        self.session = TokenCounterSession(minInterval: minIntervalSeconds)
    }

    /// Look up the API key from env var first (parity with rtb-ai-usage
    /// Python prototype) then ProcessInfo. Keychain retrieval is caller's
    /// responsibility — pass via `apiKey:`.
    static func resolvedApiKey() -> String? {
        if let v = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"],
           !v.isEmpty {
            return v
        }
        return nil
    }

    static func defaultCacheURL() -> URL {
        let caches = FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library/Caches")
        return caches
            .appendingPathComponent("TokenGarden", isDirectory: true)
            .appendingPathComponent("token_counts.json")
    }

    /// Count a raw system-prompt string. The API requires a `messages`
    /// field so we attach a minimal empty-user placeholder; Anthropic's
    /// tokenizer discounts the placeholder to ~0 tokens.
    func countSystem(_ systemText: String) async -> TokenCountResult {
        await count(system: systemText, messages: [["role": "user", "content": ""]])
    }

    /// Count a single user-message text.
    func countText(_ text: String) async -> TokenCountResult {
        await count(system: nil, messages: [["role": "user", "content": text]])
    }

    /// General entry point — builds the payload, consults the cache,
    /// calls the API, or falls back to char estimation. Never throws.
    func count(
        system: String? = nil,
        messages: [[String: Any]],
        tools: [[String: Any]]? = nil
    ) async -> TokenCountResult {
        var payload: [String: Any] = [
            "model": model,
            "messages": messages,
        ]
        if let system { payload["system"] = system }
        if let tools { payload["tools"] = tools }

        let key = Self.cacheKey(for: payload)
        if let hit = cache.get(key) {
            return TokenCountResult(tokens: hit.tokens, isExact: true, cached: true)
        }

        if apiKey != nil, let tokens = await callAPI(payload: payload) {
            cache.set(key, .init(tokens: tokens, model: model, cachedAt: Date()))
            return TokenCountResult(tokens: tokens, isExact: true, cached: false)
        }

        // Fallback: char count from user-visible text in the payload.
        let text = Self.extractText(payload)
        let approx = max(1, Int(Double(text.count) / Self.fallbackCharsPerToken))
        return TokenCountResult(tokens: approx, isExact: false, cached: false)
    }

    private func callAPI(payload: [String: Any]) async -> Int? {
        guard let apiKey,
              let body = try? JSONSerialization.data(withJSONObject: payload) else {
            return nil
        }
        var req = URLRequest(url: Self.endpoint)
        req.httpMethod = "POST"
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.httpBody = body
        req.timeoutInterval = 30

        await session.waitForSlot()
        do {
            let (data, resp) = try await transport.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tokens = json["input_tokens"] as? Int else {
                return nil
            }
            return tokens
        } catch {
            return nil
        }
    }

    // MARK: - Payload utilities

    /// SHA-256 of canonical JSON representation of the request payload.
    /// Sorted keys ensure cache hits across semantically identical calls.
    static func cacheKey(for payload: [String: Any]) -> String {
        let data = (try? JSONSerialization.data(
            withJSONObject: payload,
            options: [.sortedKeys]
        )) ?? Data()
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Pull user-visible text from a payload for fallback char counting.
    /// Mirrors the Python prototype's extraction so fallback numbers match.
    static func extractText(_ payload: [String: Any]) -> String {
        var parts: [String] = []
        if let sys = payload["system"] as? String {
            parts.append(sys)
        } else if let sysBlocks = payload["system"] as? [[String: Any]] {
            for blk in sysBlocks {
                if let t = blk["text"] as? String { parts.append(t) }
            }
        }
        if let messages = payload["messages"] as? [[String: Any]] {
            for msg in messages {
                if let c = msg["content"] as? String {
                    parts.append(c)
                } else if let blocks = msg["content"] as? [[String: Any]] {
                    for blk in blocks {
                        if let t = blk["text"] as? String { parts.append(t) }
                    }
                }
            }
        }
        if let tools = payload["tools"] as? [[String: Any]] {
            for tool in tools {
                if let d = try? JSONSerialization.data(withJSONObject: tool),
                   let s = String(data: d, encoding: .utf8) {
                    parts.append(s)
                }
            }
        }
        return parts.joined(separator: "\n")
    }
}
