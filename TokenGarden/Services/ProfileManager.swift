import Foundation
import SwiftData
import SwiftUI

extension Notification.Name {
    static let activeProfileNameDidChange = Notification.Name("activeProfileNameDidChange")
    static let profileRegistryDidChange = Notification.Name("profileRegistryDidChange")
}

@MainActor
class ProfileManager: ObservableObject {
    private let modelContext: ModelContext
    private let credentialsManager: CredentialsManager

    @Published var activeProfile: Profile?
    @Published var usageLimitsCache: [String: UsageLimits] = [:]  // profileName → limits
    @Published var loadingProfiles: Set<String> = []
    @Published var switchError: String?
    @Published var currentModel: String = ClaudeSettingsManager.currentModel() ?? "opus"
    private let cacheTTL: TimeInterval = 300  // 5 minutes
    private let modelDowngradeThreshold: Double = 0.80
    private var lastManualSwitchAt: Date = .distantPast
    private let manualSwitchLockout: TimeInterval = 300  // ignore auto-overrides for 5min after manual switch

    init(modelContext: ModelContext, credentialsManager: CredentialsManager = CredentialsManager()) {
        self.modelContext = modelContext
        self.credentialsManager = credentialsManager
        self.activeProfile = Self.fetchActive(context: modelContext)
    }

    func allProfiles() -> [Profile] {
        (try? modelContext.fetch(FetchDescriptor<Profile>())) ?? []
    }

    private static func fetchActive(context: ModelContext) -> Profile? {
        let descriptor = FetchDescriptor<Profile>(
            predicate: #Predicate { $0.isActive == true }
        )
        return try? context.fetch(descriptor).first
    }

    // MARK: - CRUD

    func saveCurrentAccount(name: String) -> Bool {
        guard let authInfo = CredentialsManager.fetchAuthStatus() else { return false }
        let credentials = credentialsManager.readCredentials() ?? Data()

        // Deactivate all existing profiles
        let allDescriptor = FetchDescriptor<Profile>()
        if let existing = try? modelContext.fetch(allDescriptor) {
            existing.forEach { $0.isActive = false }
        }

        // Update existing profile if email matches, otherwise create new
        let email = authInfo.email
        let existingDesc = FetchDescriptor<Profile>(predicate: #Predicate { $0.email == email })
        let profile: Profile
        if let existing = try? modelContext.fetch(existingDesc).first {
            existing.name = name
            existing.credentialsJSON = credentials
            existing.plan = authInfo.plan
            existing.isActive = true
            profile = existing
        } else {
            profile = Profile(name: name, email: authInfo.email, plan: authInfo.plan, credentialsJSON: credentials)
            profile.isActive = true
            modelContext.insert(profile)
        }

        try? modelContext.save()
        activeProfile = profile
        NotificationCenter.default.post(name: .profileRegistryDidChange, object: self)
        return true
    }

    @discardableResult
    func delete(profileName: String) -> Bool {
        let descriptor = FetchDescriptor<Profile>(
            predicate: #Predicate { $0.name == profileName }
        )
        guard let profile = try? modelContext.fetch(descriptor).first else { return false }
        let wasActive = profile.isActive
        modelContext.delete(profile)
        try? modelContext.save()
        if wasActive { activeProfile = nil }
        NotificationCenter.default.post(name: .profileRegistryDidChange, object: self)
        return true
    }

    @discardableResult
    func renameProfile(from oldName: String, to newName: String) -> Bool {
        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return false }
        guard trimmedName != oldName else { return true }

        let duplicateDescriptor = FetchDescriptor<Profile>(
            predicate: #Predicate { $0.name == trimmedName }
        )
        if let duplicate = try? modelContext.fetch(duplicateDescriptor).first, duplicate.name != oldName {
            return false
        }

        let descriptor = FetchDescriptor<Profile>(
            predicate: #Predicate { $0.name == oldName }
        )
        guard let profile = try? modelContext.fetch(descriptor).first else { return false }

        let tokenUsageDescriptor = FetchDescriptor<ProfileTokenUsage>(
            predicate: #Predicate { $0.profileName == oldName }
        )
        let projectUsageDescriptor = FetchDescriptor<ProjectUsage>(
            predicate: #Predicate { $0.profileName == oldName }
        )

        let tokenUsages = (try? modelContext.fetch(tokenUsageDescriptor)) ?? []
        let projectUsages = (try? modelContext.fetch(projectUsageDescriptor)) ?? []

        for usage in tokenUsages {
            usage.profileName = trimmedName
        }
        for usage in projectUsages {
            usage.profileName = trimmedName
        }

        profile.name = trimmedName
        try? modelContext.save()

        if let cached = usageLimitsCache.removeValue(forKey: oldName) {
            usageLimitsCache[trimmedName] = cached
        }

        if activeProfile?.persistentModelID == profile.persistentModelID {
            activeProfile = profile
            NotificationCenter.default.post(
                name: .activeProfileNameDidChange,
                object: self,
                userInfo: ["profileName": trimmedName]
            )
        }

        return true
    }

    // MARK: - Switch

    @discardableResult
    func switchTo(profileName: String) -> Bool {
        switchError = nil
        let descriptor = FetchDescriptor<Profile>(
            predicate: #Predicate { $0.name == profileName }
        )
        guard let target = try? modelContext.fetch(descriptor).first else {
            print("[Switch] FAIL: profile '\(profileName)' not found in DB")
            return false
        }

        // Validate stored credentials before switching
        guard !target.credentialsJSON.isEmpty,
              CredentialsManager.oauthToken(from: target.credentialsJSON) != nil else {
            print("[Switch] FAIL: no valid credentials for '\(profileName)'")
            switchError = "No credentials saved for \"\(profileName)\". Save this account first."
            return false
        }

        print("[Switch] START: \(activeProfile?.name ?? "nil") → \(profileName)")

        // Save current keychain credentials to the outgoing profile
        // (Claude Code may have refreshed the token since we last saved)
        if let current = activeProfile,
           let freshCreds = credentialsManager.readCredentials() {
            current.credentialsJSON = freshCreds
            print("[Switch] Saved outgoing profile '\(current.name)' creds from keychain")
        }

        // Deactivate all currently active profiles
        let activeDescriptor = FetchDescriptor<Profile>(
            predicate: #Predicate { $0.isActive == true }
        )
        if let activeProfiles = try? modelContext.fetch(activeDescriptor) {
            for profile in activeProfiles {
                profile.isActive = false
            }
        }

        // Activate target
        target.isActive = true
        activeProfile = target
        lastManualSwitchAt = Date()
        try? modelContext.save()

        // Write target's credentials to keychain
        let writeOK = credentialsManager.writeCredentials(target.credentialsJSON)
        print("[Switch] writeCredentials → \(writeOK ? "OK" : "FAILED")")
        if !writeOK {
            switchError = "Failed to write credentials to keychain."
        }

        // Clear all caches: the keychain now holds the new profile's token,
        // so any cached limit fetched with the previous token is stale.
        usageLimitsCache.removeAll()

        // Notify dataStore to update activeProfileName
        NotificationCenter.default.post(
            name: .activeProfileNameDidChange,
            object: self,
            userInfo: ["profileName": target.name]
        )

        // Refresh token in background — stored accessToken may be expired.
        // claude --print-access-token uses the refresh token to get a fresh one
        // and writes it back to keychain automatically.
        let switchedName = target.name
        let credsMgr = credentialsManager
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            print("[Switch] refreshOAuthToken start")
            let refreshed = CredentialsManager.refreshOAuthToken()
            print("[Switch] refreshOAuthToken → \(refreshed != nil ? "got token" : "nil/failed")")
            // Persist the freshly-written keychain credentials back into the profile
            if let fresh = credsMgr.readCredentials() {
                DispatchQueue.main.async {
                    self?.updateStoredCredentials(name: switchedName, credentials: fresh)
                    // Fetch usage limits for the switched profile with the fresh token
                    if let profile = self?.allProfiles().first(where: { $0.name == switchedName }) {
                        self?.usageLimitsCache.removeValue(forKey: switchedName)
                        self?.refreshUsageLimits(for: profile)
                    }
                }
            } else {
                print("[Switch] readCredentials after refresh returned nil")
            }
        }

        print("[Switch] DONE: activeProfile=\(activeProfile?.name ?? "nil")")
        return true
    }

    // MARK: - Auto Balancing

    func balanceIfNeeded() {
        // Don't auto-balance right after a manual switch — user chose this profile intentionally.
        guard Date().timeIntervalSince(lastManualSwitchAt) > manualSwitchLockout else { return }
        let allDescriptor = FetchDescriptor<Profile>()
        guard let profiles = try? modelContext.fetch(allDescriptor),
              profiles.count >= 2 else {
            // Single profile: still check model downgrade
            autoBalanceModel()
            return
        }

        // Only consider profiles with cached API usage data
        var leastUsed: Profile?
        var leastScore = Double.greatestFiniteMagnitude

        for profile in profiles {
            guard let limits = usageLimitsCache[profile.name] else { continue }
            let score = max(limits.fiveHourUtilization, limits.sevenDayUtilization)
            if score < leastScore {
                leastScore = score
                leastUsed = profile
            }
        }

        if let target = leastUsed, target.name != activeProfile?.name {
            switchTo(profileName: target.name)
        }

        autoBalanceModel()
    }

    /// Downgrades to Sonnet when all profiles' Opus is near limit, upgrades back when headroom available
    private func autoBalanceModel() {
        guard UserDefaults.standard.bool(forKey: "modelAutoBalancingEnabled") else { return }
        guard !usageLimitsCache.isEmpty else { return }

        let allAboveThreshold = usageLimitsCache.values.allSatisfy { limits in
            max(limits.fiveHourUtilization, limits.sevenDayUtilization) >= modelDowngradeThreshold
        }

        let anyBelowHalf = usageLimitsCache.values.contains { limits in
            max(limits.fiveHourUtilization, limits.sevenDayUtilization) < 0.5
        }

        if allAboveThreshold && currentModel != "sonnet" {
            setModel("sonnet")
        } else if !allAboveThreshold && anyBelowHalf && currentModel != "opus" {
            setModel("opus")
        }
    }

    func setModel(_ model: String) {
        let settingsModel: String? = (model == "opus") ? nil : model
        ClaudeSettingsManager.setModel(settingsModel)
        currentModel = model
    }

    func todayTokens(for profileName: String) -> Int {
        let today = Calendar.current.startOfDay(for: Date())
        let descriptor = FetchDescriptor<ProfileTokenUsage>(
            predicate: #Predicate { $0.profileName == profileName && $0.date == today }
        )
        return (try? modelContext.fetch(descriptor).first)?.tokens ?? 0
    }

    func prefetchAllUsageLimits() {
        // Sync active profile first, then fetch — serial execution prevents the race
        // where refreshUsageLimits starts before applyActiveProfileByEmail completes.
        Task.detached(priority: .userInitiated) { [weak self] in
            if let authInfo = CredentialsManager.fetchAuthStatus() {
                await MainActor.run { self?.applyActiveProfileByEmail(authInfo.email) }
            }
            await MainActor.run { [weak self] in
                guard let self else { return }
                let profiles = (try? self.modelContext.fetch(FetchDescriptor<Profile>())) ?? []
                for profile in profiles {
                    self.refreshUsageLimits(for: profile)
                }
            }
        }
    }

    /// Detects the actual logged-in account from keychain and updates isActive flags.
    /// Fixes desync when the user switches accounts outside the app (e.g. via claude auth login).
    func syncActiveProfileWithKeychain() {
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let authInfo = CredentialsManager.fetchAuthStatus() else { return }
            await MainActor.run { [weak self] in
                self?.applyActiveProfileByEmail(authInfo.email)
            }
        }
    }

    private func applyActiveProfileByEmail(_ email: String) {
        // Don't override a manual switch for the lockout period — the keychain
        // may still reflect the previous profile's email while the token refresh completes.
        let elapsed = Date().timeIntervalSince(lastManualSwitchAt)
        guard elapsed > manualSwitchLockout else {
            print("[AutoSync] SKIPPED: manual switch \(Int(elapsed))s ago (lockout=\(Int(manualSwitchLockout))s)")
            return
        }
        let all = allProfiles()
        guard let match = all.first(where: { $0.email == email }) else { return }
        guard match.email != activeProfile?.email else { return }
        print("[AutoSync] Overriding active profile: \(activeProfile?.name ?? "nil") → \(match.name) (email=\(email))")

        all.forEach { $0.isActive = ($0.email == email) }
        try? modelContext.save()
        activeProfile = match
        usageLimitsCache.removeAll()

        NotificationCenter.default.post(
            name: .activeProfileNameDidChange,
            object: self,
            userInfo: ["profileName": match.name]
        )
    }

    func refreshUsageLimits(for profile: Profile) {
        let cached = usageLimitsCache[profile.name]
        guard cached == nil || Date().timeIntervalSince(cached!.fetchedAt) > cacheTTL else { return }

        let creds = profile.credentialsJSON
        let profileName = profile.name
        let isActive = profile.name == activeProfile?.name

        loadingProfiles.insert(profileName)

        let credsMgr = credentialsManager
        // Task.detached replaces DispatchQueue.global — the underlying fetch
        // now suspends via async/await instead of blocking a GCD worker on a
        // DispatchSemaphore, and the task honours cooperative cancellation.
        Task.detached(priority: .utility) { [weak self] in
            let token: String?
            if isActive {
                // Active profile: keychain is the source of truth.
                // If the token is missing, attempt a CLI refresh before falling back
                // to the stored credentialsJSON (which may also be stale).
                if let t = CredentialsManager.currentOAuthToken() {
                    token = t
                } else if let t = CredentialsManager.refreshOAuthToken() {
                    token = t
                } else {
                    token = CredentialsManager.oauthToken(from: creds)
                }
            } else {
                token = CredentialsManager.oauthToken(from: creds)
            }

            guard let token else {
                _ = await MainActor.run { self?.loadingProfiles.remove(profileName) }
                return
            }
            let limits = await CredentialsManager.fetchUsageLimits(oauthToken: token)

            // If the active profile succeeded, refresh stored credentials from keychain
            if isActive, limits != nil, let freshCreds = credsMgr.readCredentials() {
                await MainActor.run {
                    self?.updateStoredCredentials(name: profileName, credentials: freshCreds)
                }
            }

            await MainActor.run {
                self?.loadingProfiles.remove(profileName)
                if let limits {
                    self?.usageLimitsCache[profileName] = limits
                    // Re-evaluate balancing now that fresh data is available
                    if UserDefaults.standard.bool(forKey: "autoBalancingEnabled") {
                        self?.balanceIfNeeded()
                    }
                }
            }
        }
    }


    private func updateStoredCredentials(name: String, credentials: Data) {
        let descriptor = FetchDescriptor<Profile>(predicate: #Predicate { $0.name == name })
        guard let profile = try? modelContext.fetch(descriptor).first else { return }
        profile.credentialsJSON = credentials
        try? modelContext.save()
    }

    func monthlyTokens(for profileName: String) -> Int {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: Date())
        let monthStart = cal.date(from: comps)!
        let descriptor = FetchDescriptor<ProfileTokenUsage>(
            predicate: #Predicate { $0.profileName == profileName && $0.date >= monthStart }
        )
        return (try? modelContext.fetch(descriptor))?.reduce(0) { $0 + $1.tokens } ?? 0
    }

    // MARK: - Token Keeper

    private var keeperTimer: Timer?

    @AppStorage("tokenKeeperEnabled") var tokenKeeperEnabled: Bool = false
    @AppStorage("tokenKeeperInterval") var tokenKeeperInterval: TimeInterval = 14400 // 4 hours

    func startTokenKeeper() {
        stopTokenKeeper()
        guard tokenKeeperEnabled else { return }
        keeperTimer = Timer.scheduledTimer(withTimeInterval: tokenKeeperInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshAllTokens()
            }
        }
    }

    func stopTokenKeeper() {
        keeperTimer?.invalidate()
        keeperTimer = nil
    }

    private func refreshAllTokens() {
        let descriptor = FetchDescriptor<Profile>()
        guard let profiles = try? modelContext.fetch(descriptor) else { return }

        let credentialPairs = profiles.map { ($0.name, $0.credentialsJSON) }
        let credsMgr = credentialsManager

        DispatchQueue.global(qos: .utility).async { [weak self] in
            var refreshed: [(name: String, credentials: Data)] = []

            for (name, credentials) in credentialPairs {
                guard credsMgr.writeCredentials(credentials) else { continue }

                let pipe = Pipe()
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                process.arguments = ["claude", "--print-access-token"]
                process.standardOutput = pipe
                process.standardError = FileHandle.nullDevice
                process.environment = ProcessInfo.processInfo.environment

                do {
                    try process.run()
                    process.waitUntilExit()
                } catch {
                    continue
                }

                // Capture the fresh access token from stdout and apply it directly
                // to this profile's credentialsJSON. This is more reliable than
                // reading back from the keychain, which may reflect a different
                // profile's token if Claude Code changed it during the refresh.
                let tokenData = pipe.fileHandleForReading.readDataToEndOfFile()
                if let freshToken = String(data: tokenData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                   !freshToken.isEmpty,
                   var json = try? JSONSerialization.jsonObject(with: credentials) as? [String: Any],
                   var oauth = json["claudeAiOauth"] as? [String: Any] {
                    oauth["accessToken"] = freshToken
                    json["claudeAiOauth"] = oauth
                    if let updated = try? JSONSerialization.data(withJSONObject: json) {
                        refreshed.append((name: name, credentials: updated))
                        continue
                    }
                }
                // Fallback: read back from keychain if stdout was empty or unparseable
                if let updated = credsMgr.readCredentials() {
                    refreshed.append((name: name, credentials: updated))
                }
            }

            // Restore active profile credentials and save all refreshed profiles on main actor.
            // Reading activeProfile here (not the captured activeProfileName) ensures we
            // restore the profile that is active *now*, even if the user switched mid-loop.
            DispatchQueue.main.async {
                guard let self else { return }
                MainActor.assumeIsolated {
                    // P3: use current active profile at restore time, not loop-start snapshot
                    let currentActiveName = self.activeProfile?.name
                    let restoreCreds = refreshed.first(where: { $0.name == currentActiveName })?.credentials
                        ?? self.activeProfile?.credentialsJSON
                    if let creds = restoreCreds {
                        _ = credsMgr.writeCredentials(creds)
                    }

                    for (name, credentials) in refreshed {
                        let desc = FetchDescriptor<Profile>(predicate: #Predicate { $0.name == name })
                        if let profile = try? self.modelContext.fetch(desc).first {
                            profile.credentialsJSON = credentials
                        }
                    }
                    try? self.modelContext.save()
                }
            }
        }
    }
}
