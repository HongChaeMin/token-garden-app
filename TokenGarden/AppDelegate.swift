import AppKit
import SwiftUI
import SwiftData
import SQLite3

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var menuBarController: MenuBarController!
    private var logWatcher: LogWatcher!
    private var codexWatcher: CodexWatcher!
    private var dataStore: TokenDataStore!
    private var modelContainer: ModelContainer!
    private var animationTimer: Timer!
    private var updateChecker: UpdateChecker!
    private var profileManager: ProfileManager!
    private var activeProfileObserver: NSObjectProtocol?

    // Session refresh: background task writes, main thread reads
    private let refreshLock = NSLock()
    private nonisolated(unsafe) var pendingClaudeProjects: Set<String>?
    private nonisolated(unsafe) var pendingCodexProjects: Set<String>?
    private var sessionRefreshTask: Task<Void, Never>?
    private var lastBalancedSessionId: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Single instance guard
        let bundleId = Bundle.main.bundleIdentifier ?? "com.tokengarden"
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
        if running.count > 1 {
            NSApp.terminate(nil)
            return
        }

        NSApp.setActivationPolicy(.accessory)

        // SwiftData
        let schema = Schema([DailyUsage.self, ProjectUsage.self, SessionUsage.self, HourlyUsage.self, Profile.self, ProfileTokenUsage.self, CodexProfile.self])
        let storeURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TokenGarden", isDirectory: true)
            .appendingPathComponent("TokenGarden.store")
        try? FileManager.default.createDirectory(at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let config = ModelConfiguration("TokenGarden", schema: schema, url: storeURL)
        do {
            modelContainer = try ModelContainer(for: schema, configurations: [config])
        } catch {
            // Backup profiles before reset
            let backup = Self.backupProfiles(from: storeURL)

            // New model added — reset store and backfill offsets to rebuild from logs
            let storeDir = storeURL.deletingLastPathComponent()
            try? FileManager.default.removeItem(at: storeDir)
            try? FileManager.default.createDirectory(at: storeDir, withIntermediateDirectories: true)
            UserDefaults.standard.removeObject(forKey: "LogWatcherOffsets")
            CodexWatcher.clearSnapshots()
            modelContainer = try! ModelContainer(for: schema, configurations: [config])

            // Restore profiles after reset
            Self.restoreProfiles(backup, into: modelContainer.mainContext)
        }
        dataStore = TokenDataStore(modelContainer: modelContainer)
        Self.restoreCodexProfiles(into: modelContainer.mainContext)

        // Profile Manager
        profileManager = ProfileManager(modelContext: modelContainer.mainContext)
        if let activeProfile = profileManager.activeProfile {
            dataStore.activeProfileName = activeProfile.name
        }
        dataStore.updateProfileRegistry(profileManager.allProfiles())
        activeProfileObserver = NotificationCenter.default.addObserver(
            forName: .activeProfileNameDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let name = notification.userInfo?["profileName"] as? String {
                Task { @MainActor [weak self] in
                    self?.dataStore.activeProfileName = name
                }
            }
        }
        profileManager.prefetchAllUsageLimits()

        // Status Item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = AnimationFrames.idleImage()
            button.action = #selector(togglePopover)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        // MenuBar Controller
        menuBarController = MenuBarController(statusItem: statusItem, initialTodayTokens: 0, initialHourlyBuckets: [0, 0, 0])

        // Animation timer — also checks for pending session refresh
        animationTimer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.menuBarController.tick()
                self?.applyPendingRefreshIfNeeded()
            }
        }
        RunLoop.main.add(animationTimer, forMode: .common)

        // Update checker
        updateChecker = UpdateChecker()
        updateChecker.check()

        // Popover
        popover = NSPopover()
        popover.behavior = .transient

        let popoverView = PopoverView()
            .environmentObject(menuBarController)
            .environmentObject(updateChecker)
            .environmentObject(profileManager)
            .modelContainer(modelContainer)
        let hostingController = NSHostingController(rootView: popoverView)
        hostingController.sizingOptions = .preferredContentSize
        popover.contentViewController = hostingController

        // Log Parser + Watcher
        let parser = ClaudeCodeLogParser()
        logWatcher = LogWatcher(watchPaths: parser.watchPaths) { [weak self] line in
            guard let event = parser.parse(logLine: line) else { return }
            self?.dataStore.record(event)
            self?.menuBarController.onTokenEvent(event)

            // Auto-balance only when session changes
            if let sessionId = event.sessionId,
               sessionId != self?.lastBalancedSessionId,
               UserDefaults.standard.bool(forKey: "autoBalancingEnabled") {
                self?.lastBalancedSessionId = sessionId
                self?.profileManager.balanceIfNeeded()
                if let name = self?.profileManager.activeProfile?.name {
                    self?.dataStore.activeProfileName = name
                }
            }
        }

        // Backfill on background thread — UI stays responsive
        logWatcher.backfill(parser: parser) { [weak self] event in
            self?.dataStore.record(event)
            self?.menuBarController.onTokenEvent(event)
        } completion: { [weak self] in
            // Trigger refresh right after backfill so dead sessions get cleared
            self?.dataStore.flush()
            self?.triggerRefresh()
            let todayTokens = self?.dataStore.fetchDailyUsages(
                from: Calendar.current.startOfDay(for: Date()),
                to: Date()
            ).first?.totalTokens ?? 0
            let hourlyBuckets = self?.dataStore.fetchHourlyBuckets() ?? [0, 0, 0]
            self?.menuBarController.reloadData(todayTokens: todayTokens, hourlyBuckets: hourlyBuckets)
        }


        logWatcher.start()

        // Codex Watcher
        codexWatcher = CodexWatcher { [weak self] event in
            self?.dataStore.recordCodex(event)
            self?.menuBarController.onTokenUsage(at: event.updatedAt, tokens: event.tokensUsed)
        }
        // Migrate legacy Codex placeholder profileName records to "Codex/<email>"
        if let email = CodexWatcher.currentAccount()?.email {
            dataStore.migrateCodexProfileNames(to: email)
        }
        codexWatcher.start()

        // Background session refresh loop
        startSessionRefreshLoop()

        profileManager.startTokenKeeper()
    }

    func applicationWillTerminate(_ notification: Notification) {
        sessionRefreshTask?.cancel()
        if let activeProfileObserver {
            NotificationCenter.default.removeObserver(activeProfileObserver)
        }
    }

    /// Run refresh immediately on background, result applied on next timer tick
    private func triggerRefresh() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let claudeProjects = TokenDataStore.getActiveClaudeProjects()
            let codexProjects = TokenDataStore.getActiveCodexProjects()
            self?.refreshLock.lock()
            self?.pendingClaudeProjects = claudeProjects
            self?.pendingCodexProjects = codexProjects
            self?.refreshLock.unlock()
        }
    }

    // MARK: - Session Refresh (background → main via polling)

    /// Runs the session scan on a cancellable background Task instead of a
    /// detached Thread that was leaked (the old `while true { Thread.sleep }`
    /// loop had no way to stop on app termination). Cancellation propagates
    /// through `Task.sleep`, so `applicationWillTerminate` winds it down.
    private func startSessionRefreshLoop() {
        sessionRefreshTask = Task.detached(priority: .utility) { [weak self] in
            while !Task.isCancelled {
                let claudeProjects = TokenDataStore.getActiveClaudeProjects()
                let codexProjects = TokenDataStore.getActiveCodexProjects()

                self?.storePendingProjects(claude: claudeProjects, codex: codexProjects)

                do {
                    try await Task.sleep(for: .seconds(30))
                } catch {
                    // Cancellation — exit loop.
                    break
                }
            }
        }
    }

    /// Lock-guarded write to the pending-projects slot. Pulled out into its
    /// own nonisolated method because `NSLock.lock()` is unavailable from
    /// async contexts.
    private nonisolated func storePendingProjects(claude: Set<String>, codex: Set<String>) {
        refreshLock.lock()
        defer { refreshLock.unlock() }
        pendingClaudeProjects = claude
        pendingCodexProjects = codex
    }

    private func applyPendingRefreshIfNeeded() {
        refreshLock.lock()
        let claudeProjects = pendingClaudeProjects
        let codexProjects = pendingCodexProjects
        pendingClaudeProjects = nil
        pendingCodexProjects = nil
        refreshLock.unlock()

        if let claudeProjects {
            dataStore.applyActiveStatus(source: "claude", activeProjects: claudeProjects)
        }
        if let codexProjects {
            dataStore.applyActiveStatus(source: "codex", activeProjects: codexProjects)
        }
    }

    // MARK: - Popover

    // MARK: - Profile Backup/Restore (survives DB reset)

    private struct ProfileBackup: Codable {
        let name: String
        let email: String
        let plan: String
        let credentialsJSON: Data
        let isActive: Bool
        let monthlyLimit: Int
        let colorName: String
    }

    private struct CodexProfileBackup: Codable {
        let name: String
        let email: String
        let authData: Data
        let isActive: Bool
    }

    private struct ProfileRestoreBackup {
        let claudeProfiles: [ProfileBackup]
        let codexProfiles: [CodexProfileBackup]
    }

    private static func backupProfiles(from storeURL: URL) -> ProfileRestoreBackup {
        // Read profiles directly via SQLite before DB is destroyed
        var db: OpaquePointer?
        guard sqlite3_open(storeURL.path, &db) == SQLITE_OK else {
            return ProfileRestoreBackup(claudeProfiles: [], codexProfiles: [])
        }
        defer { sqlite3_close(db) }

        return ProfileRestoreBackup(
            claudeProfiles: backupClaudeProfiles(from: db),
            codexProfiles: backupCodexProfiles(from: db)
        )
    }

    private static func backupClaudeProfiles(from db: OpaquePointer?) -> [ProfileBackup] {
        var stmt: OpaquePointer?
        let sql = "SELECT ZNAME, ZEMAIL, ZPLAN, ZCREDENTIALSJSON, ZISACTIVE, ZMONTHLYLIMIT, ZCOLORNAME FROM ZPROFILE"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        var backups: [ProfileBackup] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let name = sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? ""
            let email = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
            let plan = sqlite3_column_text(stmt, 2).map { String(cString: $0) } ?? ""
            let isActive = sqlite3_column_int(stmt, 4) != 0
            let monthlyLimit = Int(sqlite3_column_int(stmt, 5))
            let colorName = sqlite3_column_text(stmt, 6).map { String(cString: $0) } ?? "blue"

            guard !name.isEmpty else { continue }
            backups.append(ProfileBackup(
                name: name,
                email: email,
                plan: plan,
                credentialsJSON: sqliteBlobData(stmt: stmt, column: 3),
                isActive: isActive,
                monthlyLimit: monthlyLimit,
                colorName: colorName
            ))
        }
        return backups
    }

    private static func backupCodexProfiles(from db: OpaquePointer?) -> [CodexProfileBackup] {
        var stmt: OpaquePointer?
        let sql = "SELECT ZNAME, ZEMAIL, ZAUTHDATA, ZISACTIVE FROM ZCODEXPROFILE"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        var backups: [CodexProfileBackup] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let name = sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? ""
            let email = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
            guard !email.isEmpty else { continue }
            backups.append(CodexProfileBackup(
                name: name.isEmpty ? email : name,
                email: email,
                authData: sqliteBlobData(stmt: stmt, column: 2),
                isActive: sqlite3_column_int(stmt, 3) != 0
            ))
        }
        return backups
    }

    private static func sqliteBlobData(stmt: OpaquePointer?, column: Int32) -> Data {
        let length = sqlite3_column_bytes(stmt, column)
        guard length > 0, let ptr = sqlite3_column_blob(stmt, column) else {
            return Data()
        }
        return Data(bytes: ptr, count: Int(length))
    }

    private static func restoreProfiles(_ backup: ProfileRestoreBackup, into context: ModelContext) {
        for b in backup.claudeProfiles {
            let profile = Profile(name: b.name, email: b.email, plan: b.plan, credentialsJSON: b.credentialsJSON)
            profile.isActive = b.isActive
            profile.monthlyLimit = b.monthlyLimit
            profile.colorName = b.colorName
            context.insert(profile)
        }

        for b in backup.codexProfiles {
            let profile = CodexProfile(name: b.name, email: b.email, authData: b.authData)
            profile.isActive = b.isActive
            context.insert(profile)
        }
        try? context.save()
    }

    private static func restoreCodexProfiles(into context: ModelContext) {
        let existingProfiles = (try? context.fetch(FetchDescriptor<CodexProfile>())) ?? []
        var existingEmails = Set(existingProfiles.map(\.email))
        var inserted = false

        if let account = CodexWatcher.currentAccount(), !existingEmails.contains(account.email) {
            let displayName = account.name == "Unknown"
                ? account.email.components(separatedBy: "@").first ?? "Codex"
                : account.name
            let profile = CodexProfile(name: displayName, email: account.email, authData: account.authData)
            profile.isActive = true
            context.insert(profile)
            existingEmails.insert(account.email)
            inserted = true
        }

        let projectUsages = (try? context.fetch(FetchDescriptor<ProjectUsage>())) ?? []
        let codexEmails = Set(projectUsages.compactMap { usage -> String? in
            guard let profileName = usage.profileName, profileName.hasPrefix("Codex/") else { return nil }
            return String(profileName.dropFirst("Codex/".count))
        })

        for email in codexEmails where !existingEmails.contains(email) {
            let profile = CodexProfile(
                name: email.components(separatedBy: "@").first ?? email,
                email: email,
                authData: Data()
            )
            context.insert(profile)
            existingEmails.insert(email)
            inserted = true
        }

        if inserted {
            try? context.save()
        }
    }

    @objc func togglePopover() {
        guard let event = NSApp.currentEvent else { return }

        if event.type == .rightMouseUp {
            let menu = NSMenu()
            menu.addItem(NSMenuItem(title: "Quit Token Garden", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.statusItem.menu = nil
            }
            return
        }

        statusItem.menu = nil
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }
}
