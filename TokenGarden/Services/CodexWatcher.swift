import Foundation
import SQLite3

struct CodexThreadEvent {
    let threadId: String
    let updatedAt: Date
    let tokensUsed: Int
    let projectName: String
    let model: String?
    let accountEmail: String  // from auth.json at time of recording
}

struct CodexAccount {
    let email: String
    let name: String
    let accountId: String
    let authData: Data  // full auth.json content
}

struct CodexUsageLimits {
    let fiveHourUtilization: Double   // 0.0–1.0
    let fiveHourResetAt: Date
    let sevenDayUtilization: Double   // 0.0–1.0
    let sevenDayResetAt: Date
    let fetchedAt: Date = Date()
}

@MainActor
class CodexWatcher {
    private let dbPath = NSHomeDirectory() + "/.codex/state_5.sqlite"
    private let threadTokenSnapshotsKey = "CodexWatcherThreadTokenSnapshots"
    private var timer: Timer?
    private var threadTokenSnapshots: [String: Int] = [:]
    private let onEvent: @MainActor (CodexThreadEvent) -> Void

    init(onEvent: @escaping @MainActor (CodexThreadEvent) -> Void) {
        self.onEvent = onEvent
        threadTokenSnapshots = Self.loadThreadTokenSnapshots()
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        poll()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Current account info

    nonisolated static func currentAccount() -> CodexAccount? {
        let path = NSHomeDirectory() + "/.codex/auth.json"
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tokens = json["tokens"] as? [String: Any],
              let accountId = tokens["account_id"] as? String
        else { return nil }

        var email = "Unknown"
        var name = "Unknown"
        if let idToken = tokens["id_token"] as? String {
            let parts = idToken.components(separatedBy: ".")
            if parts.count >= 2 {
                var payload = parts[1]
                    .replacingOccurrences(of: "-", with: "+")
                    .replacingOccurrences(of: "_", with: "/")
                payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
                if let payloadData = Data(base64Encoded: payload),
                   let payloadJson = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any] {
                    email = payloadJson["email"] as? String ?? email
                    name = payloadJson["name"] as? String ?? name
                }
            }
        }
        return CodexAccount(email: email, name: name, accountId: accountId, authData: data)
    }

    nonisolated static func clearSnapshots() {
        UserDefaults.standard.removeObject(forKey: "CodexWatcherThreadTokenSnapshots")
    }

    /// Fetches rate limit utilization from chatgpt.com/api/codex/usage using the stored access token.
    nonisolated static func fetchUsageLimits() async -> CodexUsageLimits? {
        let authPath = NSHomeDirectory() + "/.codex/auth.json"
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: authPath)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tokens = json["tokens"] as? [String: Any],
              let accessToken = tokens["access_token"] as? String,
              let url = URL(string: "https://chatgpt.com/api/codex/usage")
        else { return nil }

        var request = URLRequest(url: url, timeoutInterval: 10)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        guard let (responseData, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              http.statusCode == 200,
              let body = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
              let rateLimitInfo = body["rate_limit"] as? [String: Any],
              let primary = rateLimitInfo["primary_window"] as? [String: Any],
              let secondary = rateLimitInfo["secondary_window"] as? [String: Any]
        else { return nil }

        let fiveUtil = (primary["used_percent"] as? Double ?? 0) / 100.0
        let sevenUtil = (secondary["used_percent"] as? Double ?? 0) / 100.0

        let fiveResetAt: Date
        if let ts = primary["reset_at"] as? Double {
            fiveResetAt = Date(timeIntervalSince1970: ts)
        } else if let ts = primary["reset_at"] as? String, let d = ISO8601DateFormatter().date(from: ts) {
            fiveResetAt = d
        } else {
            fiveResetAt = Date().addingTimeInterval(5 * 3600)
        }

        let sevenResetAt: Date
        if let ts = secondary["reset_at"] as? Double {
            sevenResetAt = Date(timeIntervalSince1970: ts)
        } else if let ts = secondary["reset_at"] as? String, let d = ISO8601DateFormatter().date(from: ts) {
            sevenResetAt = d
        } else {
            sevenResetAt = Date().addingTimeInterval(7 * 24 * 3600)
        }

        return CodexUsageLimits(
            fiveHourUtilization: fiveUtil,
            fiveHourResetAt: fiveResetAt,
            sevenDayUtilization: sevenUtil,
            sevenDayResetAt: sevenResetAt
        )
    }

    // MARK: - Poll

    private func poll() {
        let path = dbPath
        let snapshots = threadTokenSnapshots
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let account = Self.currentAccount()
            let email = account?.email ?? "Codex"
            let result = Self.fetchThreads(from: path, previousSnapshots: snapshots, accountEmail: email)
            DispatchQueue.main.async {
                guard let self else { return }
                self.threadTokenSnapshots = result.snapshots
                for event in result.events {
                    self.onEvent(event)
                }
                Self.saveThreadTokenSnapshots(result.snapshots)
            }
        }
    }

    // MARK: - SQLite read

    private nonisolated static func loadThreadTokenSnapshots() -> [String: Int] {
        UserDefaults.standard.dictionary(forKey: "CodexWatcherThreadTokenSnapshots") as? [String: Int] ?? [:]
    }

    private nonisolated static func saveThreadTokenSnapshots(_ snapshots: [String: Int]) {
        UserDefaults.standard.set(snapshots, forKey: "CodexWatcherThreadTokenSnapshots")
    }

    private nonisolated static func fetchThreads(
        from path: String,
        previousSnapshots: [String: Int],
        accountEmail: String
    ) -> (events: [CodexThreadEvent], snapshots: [String: Int]) {
        guard FileManager.default.fileExists(atPath: path) else {
            return ([], previousSnapshots)
        }
        var db: OpaquePointer?
        // Use URI with immutable=1 so SQLite skips WAL file creation in read-only mode.
        // Without this, SQLite prints "cannot open sqlite-wal" warnings to stderr when
        // the WAL file doesn't exist (e.g. after a clean DB checkpoint).
        let uri = "file:\(path)?immutable=1&mode=ro"
        guard sqlite3_open_v2(uri, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX | SQLITE_OPEN_URI, nil) == SQLITE_OK else {
            return ([], previousSnapshots)
        }
        defer { sqlite3_close(db) }

        let sql = """
            SELECT id, updated_at, tokens_used, cwd, model
            FROM threads
            WHERE tokens_used > 0
            ORDER BY updated_at ASC
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return ([], previousSnapshots)
        }
        defer { sqlite3_finalize(stmt) }

        var snapshots = previousSnapshots
        var events: [CodexThreadEvent] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let threadId = sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? ""
            let updatedAtUnix = sqlite3_column_int64(stmt, 1)
            let tokensUsed = Int(sqlite3_column_int64(stmt, 2))
            let cwd = sqlite3_column_text(stmt, 3).map { String(cString: $0) } ?? ""
            let model = sqlite3_column_text(stmt, 4).map { String(cString: $0) }
            let previousTokens = snapshots[threadId] ?? 0

            snapshots[threadId] = tokensUsed
            guard tokensUsed > previousTokens else { continue }

            let updatedAt = Date(timeIntervalSince1970: Double(updatedAtUnix))
            let projectName = URL(fileURLWithPath: cwd).lastPathComponent

            events.append(CodexThreadEvent(
                threadId: threadId,
                updatedAt: updatedAt,
                tokensUsed: tokensUsed - previousTokens,
                projectName: projectName.isEmpty ? "Unknown" : projectName,
                model: model,
                accountEmail: accountEmail
            ))
        }
        return (events, snapshots)
    }
}
