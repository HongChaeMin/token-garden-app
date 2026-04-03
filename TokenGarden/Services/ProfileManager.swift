import Foundation
import SwiftData
import SwiftUI

@MainActor
class ProfileManager: ObservableObject {
    private let modelContext: ModelContext
    private let credentialsManager: CredentialsManager

    @Published var activeProfile: Profile?
    @Published var usageLimitsCache: [String: UsageLimits] = [:]  // profileName → limits
    @Published var currentModel: String = ClaudeSettingsManager.currentModel() ?? "opus"
    private let cacheTTL: TimeInterval = 300  // 5 minutes
    private let modelDowngradeThreshold: Double = 0.80

    init(modelContext: ModelContext, credentialsManager: CredentialsManager = CredentialsManager()) {
        self.modelContext = modelContext
        self.credentialsManager = credentialsManager
        self.activeProfile = Self.fetchActive(context: modelContext)
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

        let profile = Profile(name: name, email: authInfo.email, plan: authInfo.plan, credentialsJSON: credentials)
        profile.isActive = true
        modelContext.insert(profile)
        try? modelContext.save()
        activeProfile = profile
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
        return true
    }

    // MARK: - Switch

    @discardableResult
    func switchTo(profileName: String) -> Bool {
        let descriptor = FetchDescriptor<Profile>(
            predicate: #Predicate { $0.name == profileName }
        )
        guard let target = try? modelContext.fetch(descriptor).first else { return false }

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
        try? modelContext.save()

        // Write credentials to disk
        _ = credentialsManager.writeCredentials(target.credentialsJSON)
        return true
    }

    // MARK: - Auto Balancing

    func balanceIfNeeded() {
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
        let descriptor = FetchDescriptor<Profile>()
        guard let profiles = try? modelContext.fetch(descriptor) else { return }
        for profile in profiles {
            refreshUsageLimits(for: profile)
        }
    }

    func refreshUsageLimits(for profile: Profile) {
        let cached = usageLimitsCache[profile.name]
        guard cached == nil || Date().timeIntervalSince(cached!.fetchedAt) > cacheTTL else { return }

        let creds = profile.credentialsJSON
        let profileName = profile.name
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let token = CredentialsManager.oauthToken(from: creds)
                ?? CredentialsManager.currentOAuthToken()
            guard let token else { return }
            let limits = CredentialsManager.fetchUsageLimits(oauthToken: token)
            DispatchQueue.main.async {
                if let limits {
                    self?.usageLimitsCache[profileName] = limits
                }
            }
        }
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
        let activeCredentials = activeProfile?.credentialsJSON
        let credsMgr = credentialsManager

        DispatchQueue.global(qos: .utility).async { [weak self] in
            for (_, credentials) in credentialPairs {
                guard credsMgr.writeCredentials(credentials) else { continue }

                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                process.arguments = ["claude", "--print-access-token"]
                process.standardOutput = FileHandle.nullDevice
                process.standardError = FileHandle.nullDevice

                do {
                    try process.run()
                    process.waitUntilExit()
                } catch {
                    continue
                }
            }

            // Read back refreshed credentials and restore active
            DispatchQueue.main.async {
                guard let self else { return }
                MainActor.assumeIsolated {
                    let descriptor = FetchDescriptor<Profile>()
                    guard let profiles = try? self.modelContext.fetch(descriptor) else { return }
                    for profile in profiles {
                        if let refreshed = self.credentialsManager.readCredentials() {
                            profile.credentialsJSON = refreshed
                        }
                    }
                    // Restore active profile's credentials
                    if let activeCreds = activeCredentials {
                        _ = self.credentialsManager.writeCredentials(activeCreds)
                    }
                    try? self.modelContext.save()
                }
            }
        }
    }
}
