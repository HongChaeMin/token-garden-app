import Foundation
import SwiftData

@MainActor
class TokenDataStore: ObservableObject {
    private let modelContainer: ModelContainer
    private let modelContext: ModelContext
    private var pendingSaveCount = 0
    var activeProfileName: String?
    private var emailToProfileName: [String: String] = [:]
    private var cachedEmail: String?
    private var cachedEmailAt: Date = .distantPast
    private let cache = RecordCache()
    private static let saveInterval = 10
    private static let emailCacheTTL: TimeInterval = 60

    func updateProfileRegistry(_ profiles: [Profile]) {
        emailToProfileName = Dictionary(
            profiles.map { ($0.email, $0.name) },
            uniquingKeysWith: { first, _ in first }
        )
        cachedEmailAt = .distantPast
    }

    private func resolveProfileName() -> String? {
        let now = Date()
        if now.timeIntervalSince(cachedEmailAt) > Self.emailCacheTTL {
            cachedEmail = CredentialsManager.fetchAuthStatus()?.email
            cachedEmailAt = now
        }
        if let email = cachedEmail, let name = emailToProfileName[email] {
            return name
        }
        return activeProfileName
    }

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        self.modelContext = modelContainer.mainContext
    }

    func record(_ event: TokenEvent) {
        let day = Calendar.current.startOfDay(for: event.timestamp)
        let daily = dailyUsage(for: day)

        daily.inputTokens += event.inputTokens
        daily.outputTokens += event.outputTokens
        daily.cacheCreationTokens += event.cacheCreationTokens
        daily.cacheReadTokens += event.cacheReadTokens

        accumulateHourlyTokens(
            day: day,
            hour: Calendar.current.component(.hour, from: event.timestamp),
            tokens: event.totalTokens,
            source: "claude"
        )

        let resolvedProfile = resolveProfileName()

        if let projectName = event.projectName {
            if let existing = daily.projectBreakdowns.first(where: {
                $0.projectName == projectName && $0.profileName == resolvedProfile
            }) {
                existing.tokens += event.totalTokens
            } else {
                let projectUsage = ProjectUsage(
                    projectName: projectName,
                    tokens: event.totalTokens,
                    model: event.model,
                    profileName: resolvedProfile
                )
                projectUsage.dailyUsage = daily
                daily.projectBreakdowns.append(projectUsage)
            }
        }

        if let profileName = resolvedProfile {
            let usage = profileTokenUsage(for: profileName, day: day)
            usage.tokens += event.totalTokens
        }

        if let sessionId = event.sessionId {
            let session = sessionUsage(
                for: sessionId,
                projectName: event.projectName ?? "Unknown",
                startTime: event.timestamp,
                source: "claude"
            )
            session.totalTokens += event.totalTokens
            session.lastTime = event.timestamp
        }

        pendingSaveCount += 1
        if pendingSaveCount >= Self.saveInterval {
            try? modelContext.save()
            pendingSaveCount = 0
        }
    }

    // MARK: - Cached fetch helpers

    /// Returns the `DailyUsage` for `day`, fetching once per day and caching
    /// the live `@Model` reference. Subsequent events on the same day reuse
    /// the cached row with zero fetches.
    private func dailyUsage(for day: Date) -> DailyUsage {
        cache.invalidateIfDayChanged(to: day)
        if let cached = cache.daily { return cached }

        let descriptor = FetchDescriptor<DailyUsage>(
            predicate: #Predicate { $0.date == day }
        )
        let daily: DailyUsage
        if let existing = try? modelContext.fetch(descriptor).first {
            daily = existing
        } else {
            daily = DailyUsage(date: day)
            modelContext.insert(daily)
        }
        cache.setDaily(daily)
        return daily
    }

    private func profileTokenUsage(for profileName: String, day: Date) -> ProfileTokenUsage {
        cache.invalidateIfDayChanged(to: day)
        if let cached = cache.profileTokens[profileName] { return cached }

        let descriptor = FetchDescriptor<ProfileTokenUsage>(
            predicate: #Predicate { $0.profileName == profileName && $0.date == day }
        )
        let usage: ProfileTokenUsage
        if let existing = try? modelContext.fetch(descriptor).first {
            usage = existing
        } else {
            usage = ProfileTokenUsage(profileName: profileName, date: day, tokens: 0)
            modelContext.insert(usage)
        }
        cache.setProfileTokens(usage, forProfile: profileName)
        return usage
    }

    private func sessionUsage(for sessionId: String, projectName: String, startTime: Date, source: String) -> SessionUsage {
        if let cached = cache.sessions[sessionId] { return cached }

        let descriptor = FetchDescriptor<SessionUsage>(
            predicate: #Predicate { $0.sessionId == sessionId }
        )
        let session: SessionUsage
        if let existing = try? modelContext.fetch(descriptor).first {
            session = existing
        } else {
            session = SessionUsage(
                sessionId: sessionId,
                projectName: projectName,
                startTime: startTime,
                source: source
            )
            modelContext.insert(session)
        }
        cache.setSession(session)
        return session
    }

    func recordCodex(_ event: CodexThreadEvent) {
        let day = Calendar.current.startOfDay(for: event.updatedAt)
        let daily = dailyUsage(for: day)

        daily.codexTokens += event.tokensUsed
        accumulateHourlyTokens(
            day: day,
            hour: Calendar.current.component(.hour, from: event.updatedAt),
            tokens: event.tokensUsed,
            source: "codex"
        )

        let codexProfileName = "Codex/" + event.accountEmail
        if let existing = daily.projectBreakdowns.first(where: {
            $0.projectName == event.projectName && $0.profileName == codexProfileName
        }) {
            existing.tokens += event.tokensUsed
        } else {
            let projectUsage = ProjectUsage(
                projectName: event.projectName,
                tokens: event.tokensUsed,
                model: event.model,
                profileName: codexProfileName
            )
            projectUsage.dailyUsage = daily
            daily.projectBreakdowns.append(projectUsage)
        }

        let session = sessionUsage(
            for: event.threadId,
            projectName: event.projectName,
            startTime: event.updatedAt,
            source: "codex"
        )
        session.totalTokens += event.tokensUsed
        session.lastTime = event.updatedAt
        session.isActive = true
        // Force-correct the source on every event in case the sessionId was
        // previously recorded under a different source.
        session.source = "codex"

        pendingSaveCount += 1
        if pendingSaveCount >= Self.saveInterval {
            try? modelContext.save()
            pendingSaveCount = 0
        }
    }

    private func accumulateHourlyTokens(day: Date, hour: Int, tokens: Int, source: String) {
        cache.invalidateIfDayChanged(to: day)
        if let cached = cache.hourly[RecordCache.HourlyKey(hour: hour, source: source)] {
            cached.tokens += tokens
            return
        }
        let hourlyDescriptor = FetchDescriptor<HourlyUsage>(
            predicate: #Predicate { $0.date == day && $0.hour == hour && $0.source == source }
        )
        let hourly: HourlyUsage
        if let existing = try? modelContext.fetch(hourlyDescriptor).first {
            existing.tokens += tokens
            hourly = existing
        } else {
            let inserted = HourlyUsage(date: day, hour: hour, tokens: tokens, source: source)
            modelContext.insert(inserted)
            hourly = inserted
        }
        cache.setHourly(hourly, forHour: hour, source: source)
    }

    func endSession(sessionId: String) {
        let descriptor = FetchDescriptor<SessionUsage>(
            predicate: #Predicate { $0.sessionId == sessionId }
        )
        if let session = try? modelContext.fetch(descriptor).first {
            session.isActive = false
        }
    }

    /// Apply active status with pre-fetched project names. Must be called on MainActor.
    ///
    /// Rewritten from O(n²) — the previous implementation, for each session
    /// in an active project, filtered and sorted the full session list to
    /// find that project's newest session. Now runs in a single linear pass
    /// over sessions matching `source`:
    ///   1. Track the newest `SessionUsage` per project in one dictionary.
    ///   2. Each session is active iff its project is in `activeProjects`
    ///      AND it is the newest session in that project.
    /// Same result, O(n) instead of O(n²), plus a predicate so the DB hands
    /// us only the rows for the matching source.
    func applyActiveStatus(source: String, activeProjects: Set<String>) {
        let descriptor = FetchDescriptor<SessionUsage>(
            predicate: #Predicate<SessionUsage> { $0.source == source }
        )
        guard let sessions = try? modelContext.fetch(descriptor) else { return }

        var latestPerProject: [String: SessionUsage] = [:]
        for session in sessions {
            if let current = latestPerProject[session.projectName] {
                if session.lastTime > current.lastTime {
                    latestPerProject[session.projectName] = session
                }
            } else {
                latestPerProject[session.projectName] = session
            }
        }

        for session in sessions {
            let isInActive = activeProjects.contains(session.projectName)
            let isNewest = latestPerProject[session.projectName]?.sessionId == session.sessionId
            session.isActive = isInActive && isNewest
        }
        try? modelContext.save()
    }

    /// Returns project names for running CLI processes. Safe to call from any thread.
    /// Single lsof call with all PIDs at once to minimize overhead.
    private nonisolated static func getActiveProjects(
        matching: @escaping (_ command: String, _ args: String) -> Bool
    ) -> Set<String> {
        let psPipe = Pipe()
        let psProc = Process()
        psProc.executableURL = URL(fileURLWithPath: "/bin/ps")
        psProc.arguments = ["-eo", "pid,comm,args"]
        psProc.standardOutput = psPipe
        psProc.standardError = FileHandle.nullDevice

        do { try psProc.run() } catch { return [] }
        let psData = psPipe.fileHandleForReading.readDataToEndOfFile()
        psProc.waitUntilExit()
        guard let psOutput = String(data: psData, encoding: .utf8) else { return [] }

        var pids: [String] = []
        for line in psOutput.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let parts = trimmed.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard parts.count >= 3 else { continue }
            let pid = String(parts[0])
            let command = String(parts[1])
            let args = String(parts[2])
            if matching(command, args) {
                pids.append(pid)
            }
        }
        guard !pids.isEmpty else { return [] }

        let pipe = Pipe()
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        proc.arguments = ["-a", "-d", "cwd", "-p", pids.joined(separator: ",")]
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice

        do { try proc.run() } catch { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        guard let output = String(data: data, encoding: .utf8) else { return [] }

        var projects = Set<String>()
        for line in output.components(separatedBy: "\n") {
            guard line.contains("cwd") else { continue }
            let parts = line.split(separator: " ", maxSplits: 8)
            if parts.count >= 9 {
                let path = String(parts[8])
                let name = URL(fileURLWithPath: path).lastPathComponent
                projects.insert(name)
            }
        }
        return projects
    }

    nonisolated static func getActiveClaudeProjects() -> Set<String> {
        getActiveProjects { command, args in
            command.hasSuffix("/claude") || command == "claude" || args.hasSuffix("/claude") || args == "claude"
        }
    }

    nonisolated static func getActiveCodexProjects() -> Set<String> {
        getActiveProjects { command, args in
            if command == "codex" || command.hasSuffix("/codex") {
                return true
            }
            if command == "node" {
                return args.contains("/bin/codex") || args.contains("/codex/codex")
            }
            return args.contains("/bin/codex") || args.contains("/codex/codex")
        }
    }

    /// One-time migration: rename legacy Codex placeholder profile names to "Codex/<email>"
    func migrateCodexProfileNames(to email: String) {
        let newName = "Codex/" + email
        let descriptor = FetchDescriptor<ProjectUsage>(
            predicate: #Predicate { $0.profileName == "Codex" || $0.profileName == "Codex/Codex" }
        )
        guard let usages = try? modelContext.fetch(descriptor), !usages.isEmpty else { return }
        for usage in usages {
            usage.profileName = newName
        }
        try? modelContext.save()
    }

    func flush() {
        if pendingSaveCount > 0 {
            try? modelContext.save()
            pendingSaveCount = 0
        }
    }

    func fetchDailyUsages(from startDate: Date, to endDate: Date) -> [DailyUsage] {
        let start = Calendar.current.startOfDay(for: startDate)
        let end = Calendar.current.startOfDay(for: endDate)
        let descriptor = FetchDescriptor<DailyUsage>(
            predicate: #Predicate { $0.date >= start && $0.date <= end },
            sortBy: [SortDescriptor(\.date)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    /// Returns 24 hourly token totals for a given day from HourlyUsage.
    func fetchHourlyTokens(for date: Date, source: String? = nil) -> [Int] {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: date)
        let descriptor: FetchDescriptor<HourlyUsage>
        if let source {
            descriptor = FetchDescriptor<HourlyUsage>(
                predicate: #Predicate { $0.date == dayStart && $0.source == source }
            )
        } else {
            descriptor = FetchDescriptor<HourlyUsage>(
                predicate: #Predicate { $0.date == dayStart }
            )
        }
        guard let usages = try? modelContext.fetch(descriptor), !usages.isEmpty else {
            return Array(repeating: 0, count: 24)
        }

        var buckets = Array(repeating: 0, count: 24)
        for usage in usages where (0..<24).contains(usage.hour) {
            buckets[usage.hour] += usage.tokens
        }
        return buckets
    }

    /// Returns token totals for the last 3 hours: [h-2, h-1, h]
    func fetchHourlyBuckets(source: String? = nil) -> [Int] {
        let cal = Calendar.current
        let now = Date()
        let currentHour = cal.component(.hour, from: now)
        let today = cal.startOfDay(for: now)
        let todayBuckets = fetchHourlyTokens(for: today, source: source)

        var buckets = [0, 0, 0]
        for i in 0..<3 {
            let hour = currentHour - 2 + i
            if (0..<24).contains(hour) {
                buckets[i] = todayBuckets[hour]
            }
        }
        return buckets
    }
}
