import Foundation
import SwiftData

@MainActor
class TokenDataStore: ObservableObject {
    private let modelContainer: ModelContainer
    private let modelContext: ModelContext
    private var pendingSaveCount = 0
    private static let saveInterval = 10

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        self.modelContext = ModelContext(modelContainer)
    }

    func record(_ event: TokenEvent) {
        let day = Calendar.current.startOfDay(for: event.timestamp)

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

        daily.inputTokens += event.inputTokens
        daily.outputTokens += event.outputTokens
        daily.cacheCreationTokens += event.cacheCreationTokens
        daily.cacheReadTokens += event.cacheReadTokens

        if let projectName = event.projectName {
            if let existing = daily.projectBreakdowns.first(where: { $0.projectName == projectName }) {
                existing.tokens += event.totalTokens
            } else {
                let projectUsage = ProjectUsage(
                    projectName: projectName,
                    tokens: event.totalTokens,
                    model: event.model
                )
                projectUsage.dailyUsage = daily
                daily.projectBreakdowns.append(projectUsage)
            }
        }

        // Session tracking
        if let sessionId = event.sessionId {
            let sessionDescriptor = FetchDescriptor<SessionUsage>(
                predicate: #Predicate { $0.sessionId == sessionId }
            )
            if let session = try? modelContext.fetch(sessionDescriptor).first {
                session.totalTokens += event.totalTokens
                session.lastTime = event.timestamp
                session.isActive = true
            } else {
                let session = SessionUsage(
                    sessionId: sessionId,
                    projectName: event.projectName ?? "Unknown",
                    startTime: event.timestamp
                )
                session.totalTokens = event.totalTokens
                session.lastTime = event.timestamp
                modelContext.insert(session)
            }
        }

        pendingSaveCount += 1
        if pendingSaveCount >= Self.saveInterval {
            try? modelContext.save()
            pendingSaveCount = 0
        }
    }

    func endSession(sessionId: String) {
        let descriptor = FetchDescriptor<SessionUsage>(
            predicate: #Predicate { $0.sessionId == sessionId }
        )
        if let session = try? modelContext.fetch(descriptor).first {
            session.isActive = false
        }
    }

    /// Refresh active status by checking running claude processes.
    nonisolated func refreshActiveStatus() {
        let activeProjects = Self.getActiveClaudeProjects()
        Task { @MainActor in
            self.applyActiveStatus(activeProjects: activeProjects)
        }
    }

    private func applyActiveStatus(activeProjects: Set<String>) {
        let descriptor = FetchDescriptor<SessionUsage>()
        guard let sessions = try? modelContext.fetch(descriptor) else { return }

        for session in sessions {
            session.isActive = false

            if activeProjects.contains(session.projectName) {
                let projectSessions = sessions
                    .filter { $0.projectName == session.projectName }
                    .sorted { $0.lastTime > $1.lastTime }
                if projectSessions.first?.sessionId == session.sessionId {
                    session.isActive = true
                }
            }
        }
        try? modelContext.save()
    }

    /// Returns project names for running claude processes (runs on background thread).
    private nonisolated static func getActiveClaudeProjects() -> Set<String> {
        let psPipe = Pipe()
        let psProc = Process()
        psProc.executableURL = URL(fileURLWithPath: "/bin/ps")
        psProc.arguments = ["-eo", "pid,comm"]
        psProc.standardOutput = psPipe
        psProc.standardError = FileHandle.nullDevice

        do { try psProc.run(); psProc.waitUntilExit() } catch { return [] }

        let psData = psPipe.fileHandleForReading.readDataToEndOfFile()
        guard let psOutput = String(data: psData, encoding: .utf8) else { return [] }

        var pids: [String] = []
        for line in psOutput.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasSuffix("/claude") || trimmed.hasSuffix(" claude") {
                let parts = trimmed.split(separator: " ", maxSplits: 1)
                if let pid = parts.first { pids.append(String(pid)) }
            }
        }
        guard !pids.isEmpty else { return [] }

        var projects = Set<String>()
        for pid in pids {
            let pipe = Pipe()
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
            proc.arguments = ["-a", "-d", "cwd", "-p", pid]
            proc.standardOutput = pipe
            proc.standardError = FileHandle.nullDevice

            do { try proc.run(); proc.waitUntilExit() } catch { continue }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else { continue }

            for line in output.components(separatedBy: "\n") {
                guard line.contains("cwd") else { continue }
                let parts = line.split(separator: " ", maxSplits: 8)
                if parts.count >= 9 {
                    let path = String(parts[8])
                    let name = URL(fileURLWithPath: path).lastPathComponent
                    projects.insert(name)
                }
            }
        }
        return projects
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

    /// Returns token totals for the last 3 hours: [h-2, h-1, h]
    func fetchHourlyBuckets() -> [Int] {
        let cal = Calendar.current
        let now = Date()
        let currentHour = cal.component(.hour, from: now)
        let today = cal.startOfDay(for: now)

        // Build hour start/end for last 3 hours
        var buckets = [0, 0, 0]
        for i in 0..<3 {
            let hour = currentHour - 2 + i
            guard let hourStart = cal.date(bySettingHour: hour, minute: 0, second: 0, of: today),
                  let hourEnd = cal.date(bySettingHour: hour, minute: 59, second: 59, of: today) else { continue }

            let descriptor = FetchDescriptor<SessionUsage>(
                predicate: #Predicate<SessionUsage> { session in
                    session.lastTime >= hourStart && session.startTime <= hourEnd
                }
            )
            if let sessions = try? modelContext.fetch(descriptor) {
                buckets[i] = sessions.reduce(0) { $0 + $1.totalTokens }
            }
        }
        return buckets
    }
}
