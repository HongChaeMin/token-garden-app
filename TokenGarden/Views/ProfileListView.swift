import SwiftUI
import SwiftData

struct ProfileListView: View {
    @EnvironmentObject var profileManager: ProfileManager
    @Query(sort: \Profile.createdAt) private var profiles: [Profile]
    @State private var showAddSheet = false
    @State private var newName = ""
    @State private var detectedAuth: ClaudeAuthInfo?
    @State private var isDetecting = false
    @State private var errorMessage: String?
    @AppStorage("autoBalancingEnabled") private var autoBalancingEnabled = false
    @AppStorage("modelAutoBalancingEnabled") private var modelAutoBalancingEnabled = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption2)
                    .foregroundStyle(.red)
            }

            if let switchError = profileManager.switchError {
                Text(switchError)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Profile list
            if profiles.isEmpty {
                Text("No profiles saved")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 16)
            } else {
                VStack(spacing: 6) {
                    ForEach(profiles, id: \.name) { profile in
                        ProfileRow(
                            profile: profile,
                            monthlyTokens: profileManager.monthlyTokens(for: profile.name),
                            usageLimits: profileManager.usageLimitsCache[profile.name],
                            isLoadingLimits: profileManager.loadingProfiles.contains(profile.name),
                            onRename: { newName in
                                if profileManager.renameProfile(from: profile.name, to: newName) {
                                    errorMessage = nil
                                } else {
                                    errorMessage = "Failed to rename profile. Name may already be in use."
                                }
                            },
                            onSwitch: { profileManager.switchTo(profileName: profile.name) },
                            onDelete: { profileManager.delete(profileName: profile.name) }
                        )
                    }
                }
                .task(id: profileManager.activeProfile?.name) {
                    for profile in profiles {
                        profileManager.refreshUsageLimits(for: profile)
                    }
                }
            }

            Divider()

            // Add current account
            if showAddSheet {
                VStack(alignment: .leading, spacing: 8) {
                    if isDetecting {
                        HStack {
                            ProgressView().controlSize(.small)
                            Text("Detecting account...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else if let auth = detectedAuth {
                        HStack(spacing: 6) {
                            Circle().fill(.green).frame(width: 6, height: 6)
                            Text("\(auth.email) · \(auth.plan)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        TextField("Profile Name", text: $newName)
                            .textFieldStyle(.roundedBorder)
                            .font(.caption)
                        HStack {
                            Button("Cancel") {
                                showAddSheet = false
                                newName = ""
                                detectedAuth = nil
                            }
                            .controlSize(.small)
                            Spacer()
                            Button("Save") {
                                if profileManager.saveCurrentAccount(name: newName) {
                                    showAddSheet = false
                                    newName = ""
                                    detectedAuth = nil
                                }
                            }
                            .controlSize(.small)
                            .disabled(newName.isEmpty)
                        }
                    } else {
                        HStack {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                            Text("Not logged in to Claude Code")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Button("Cancel") {
                            showAddSheet = false
                        }
                        .controlSize(.small)
                    }
                }
                .padding(8)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            } else {
                Button(action: {
                    showAddSheet = true
                    isDetecting = true
                    DispatchQueue.global(qos: .userInitiated).async {
                        let auth = CredentialsManager.fetchAuthStatus()
                        DispatchQueue.main.async {
                            detectedAuth = auth
                            isDetecting = false
                        }
                    }
                }) {
                    Label("Save Current Account", systemImage: "plus.circle")
                        .font(.caption)
                }
                .buttonStyle(.plain)
            }

            Divider()

            // Settings toggles
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Toggle("Auto Balancing", isOn: $autoBalancingEnabled)
                    .controlSize(.small)
                    #if DEBUG
                    Spacer()
                    Button("Force Balance") {
                        profileManager.balanceIfNeeded(force: true)
                    }
                    .controlSize(.small)
                    #endif
                }

                Toggle("Model Auto Balancing", isOn: $modelAutoBalancingEnabled)
                .controlSize(.small)

                Toggle("Token Keeper", isOn: Binding(
                    get: { profileManager.tokenKeeperEnabled },
                    set: {
                        profileManager.tokenKeeperEnabled = $0
                        if $0 { profileManager.startTokenKeeper() }
                        else { profileManager.stopTokenKeeper() }
                    }
                ))
                .controlSize(.small)
            }
        }
        .padding(12)
    }
}

// MARK: - Claude profile row

private struct ProfileRow: View {
    let profile: Profile
    let monthlyTokens: Int
    let usageLimits: UsageLimits?
    let isLoadingLimits: Bool
    let onRename: (String) -> Void
    let onSwitch: () -> Void
    let onDelete: () -> Void
    @State private var isEditingName = false
    @State private var draftName = ""

    private var usageRatio: Double {
        guard profile.monthlyLimit > 0 else { return 0 }
        return min(Double(monthlyTokens) / Double(profile.monthlyLimit), 1.0)
    }

    private func formatPercent(_ ratio: Double) -> String {
        let pct = ratio * 100
        if pct < 1 { return String(format: "%.1f%%", pct) }
        return "\(Int(pct))%"
    }

    private func resetLabel(for date: Date) -> String {
        let diff = date.timeIntervalSinceNow
        if diff <= 0 { return "Reset" }
        let hours = Int(diff / 3600)
        let minutes = Int((diff.truncatingRemainder(dividingBy: 3600)) / 60)
        if hours > 0 { return "Resets in \(hours)h \(minutes)m" }
        return "Resets in \(minutes)m"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Circle()
                    .fill(profile.isActive ? Color.green : .gray.opacity(0.3))
                    .frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 1) {
                    if isEditingName {
                        TextField("Profile Name", text: $draftName)
                            .textFieldStyle(.roundedBorder)
                            .font(.caption)
                            .onSubmit(saveRename)
                    } else {
                        Text(profile.name)
                            .font(.caption)
                            .fontWeight(profile.isActive ? .medium : .regular)
                    }
                    Text("\(profile.email) · \(profile.plan)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                HStack(spacing: 4) {
                    if isEditingName {
                        Button("Cancel") {
                            draftName = profile.name
                            isEditingName = false
                        }
                        .controlSize(.mini)
                        Button("Save", action: saveRename)
                            .controlSize(.mini)
                            .disabled(draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    } else {
                        Button("Rename") {
                            draftName = profile.name
                            isEditingName = true
                        }
                        .controlSize(.mini)
                    }
                    if !profile.isActive {
                        Button("Switch") { onSwitch() }
                            .controlSize(.mini)
                    }
                    if profile.isActive {
                        Text("Active")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    }
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.caption2)
                            .foregroundStyle(.red.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                }
                .fixedSize()
            }

            if let limits = usageLimits {
                UsageLimitRow(
                    label: "5h session",
                    utilization: limits.fiveHourUtilization,
                    resetLabel: resetLabel(for: limits.fiveHourResetAt)
                )
                UsageLimitRow(
                    label: "7d week",
                    utilization: limits.sevenDayUtilization,
                    resetLabel: resetLabel(for: limits.sevenDayResetAt)
                )
            } else if isLoadingLimits {
                ShimmerUsageRow(label: "5h session")
                ShimmerUsageRow(label: "7d week")
            } else {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.secondary.opacity(0.15))
                            .frame(height: 4)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(usageRatio >= 0.9 ? Color.red : usageRatio >= 0.7 ? Color.orange : Color.green)
                            .frame(width: geo.size.width * usageRatio, height: 4)
                    }
                }
                .frame(height: 4)

                HStack {
                    Text("\(TokenFormatter.format(monthlyTokens)) this month")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(formatPercent(usageRatio)) used this month")
                        .font(.caption2)
                        .foregroundStyle(Color.secondary.opacity(0.5))
                }
            }
        }
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
        .onAppear {
            draftName = profile.name
        }
        .onChange(of: profile.name) { _, newValue in
            if !isEditingName {
                draftName = newValue
            }
        }
    }

    private func saveRename() {
        let trimmedName = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        onRename(trimmedName)
        isEditingName = false
    }
}

private struct ShimmerUsageRow: View {
    let label: String
    @State private var shimmerPhase: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.secondary.opacity(shimmerPhase ? 0.25 : 0.12))
                    .frame(width: 48, height: 8)
            }
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.secondary.opacity(shimmerPhase ? 0.25 : 0.12))
                .frame(height: 4)
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.secondary.opacity(shimmerPhase ? 0.18 : 0.08))
                .frame(width: 80, height: 7)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                shimmerPhase = true
            }
        }
    }
}

private struct UsageLimitRow: View {
    let label: String
    let utilization: Double
    let resetLabel: String

    private var barColor: Color {
        if utilization >= 0.9 { return .red }
        if utilization >= 0.7 { return .orange }
        return .blue
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.0f%% used", utilization * 100))
                    .font(.caption2)
                    .foregroundStyle(utilization >= 0.9 ? Color.red : Color.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.secondary.opacity(0.15))
                        .frame(height: 4)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(barColor)
                        .frame(width: geo.size.width * min(utilization, 1.0), height: 4)
                }
            }
            .frame(height: 4)
            Text(resetLabel)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}
