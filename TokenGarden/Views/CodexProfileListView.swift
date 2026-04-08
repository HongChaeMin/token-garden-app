import SwiftUI
import SwiftData

struct CodexProfileListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CodexProfile.createdAt) private var codexProfiles: [CodexProfile]
    @State private var showAddSheet = false
    @State private var newName = ""
    @State private var detectedAccount: CodexAccount?
    @State private var activeEmail = CodexWatcher.currentAccount()?.email
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption2)
                    .foregroundStyle(.red)
            }

            // Profile list
            if codexProfiles.isEmpty {
                Text("No Codex profiles saved")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 16)
            } else {
                VStack(spacing: 6) {
                    ForEach(codexProfiles, id: \.email) { profile in
                        CodexProfileRow(
                            profile: profile,
                            activeEmail: activeEmail,
                            onRename: { newName in rename(profile, to: newName) },
                            onSwitch: { switchTo(profile) },
                            onDelete: { delete(profile) }
                        )
                    }
                }
            }

            Divider()

            // Add current Codex account
            if showAddSheet {
                addSheet
            } else {
                Button(action: {
                    showAddSheet = true
                    detectedAccount = CodexWatcher.currentAccount()
                    newName = ""
                }) {
                    Label("Save Current Codex Account", systemImage: "plus.circle")
                        .font(.caption)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .onAppear {
            refreshActiveAccount()
        }
    }

    // MARK: - Add sheet

    @ViewBuilder private var addSheet: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let account = detectedAccount {
                HStack(spacing: 6) {
                    Circle().fill(.green).frame(width: 6, height: 6)
                    Text(account.email + " · OpenAI")
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
                        detectedAccount = nil
                    }
                    .controlSize(.small)
                    Spacer()
                    Button("Save") {
                        saveAccount(name: newName, account: account)
                        showAddSheet = false
                        newName = ""
                        detectedAccount = nil
                    }
                    .controlSize(.small)
                    .disabled(newName.isEmpty)
                }
            } else {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Text("Not logged in to Codex CLI")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button("Cancel") { showAddSheet = false }
                    .controlSize(.small)
            }
        }
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Actions

    private func saveAccount(name: String, account: CodexAccount) {
        errorMessage = nil
        if let existing = codexProfiles.first(where: { $0.email == account.email }) {
            existing.name = name
            existing.authData = account.authData
        } else {
            let profile = CodexProfile(name: name, email: account.email, authData: account.authData)
            modelContext.insert(profile)
        }
        do {
            try modelContext.save()
            refreshActiveAccount()
        } catch {
            errorMessage = "Failed to save Codex profile."
        }
    }

    private func switchTo(_ profile: CodexProfile) {
        let authPath = NSHomeDirectory() + "/.codex/auth.json"
        errorMessage = nil
        do {
            try FileManager.default.createDirectory(
                at: URL(fileURLWithPath: authPath).deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try profile.authData.write(to: URL(fileURLWithPath: authPath), options: .atomic)
            refreshActiveAccount()
        } catch {
            errorMessage = "Failed to switch Codex account."
        }
    }

    private func delete(_ profile: CodexProfile) {
        errorMessage = nil
        modelContext.delete(profile)
        do {
            try modelContext.save()
            refreshActiveAccount()
        } catch {
            errorMessage = "Failed to delete Codex profile."
        }
    }

    private func refreshActiveAccount() {
        activeEmail = CodexWatcher.currentAccount()?.email
    }

    private func rename(_ profile: CodexProfile, to newName: String) {
        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "Profile name cannot be empty."
            return
        }
        errorMessage = nil
        profile.name = trimmedName
        do {
            try modelContext.save()
        } catch {
            errorMessage = "Failed to rename Codex profile."
        }
    }
}

// MARK: - Codex profile row

private struct CodexProfileRow: View {
    let profile: CodexProfile
    let activeEmail: String?
    let onRename: (String) -> Void
    let onSwitch: () -> Void
    let onDelete: () -> Void
    @State private var isEditingName = false
    @State private var draftName = ""

    private var isActive: Bool {
        activeEmail == profile.email
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Circle()
                    .fill(isActive ? Color.green : .gray.opacity(0.3))
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
                            .fontWeight(isActive ? .medium : .regular)
                    }
                    Text(profile.email + " · OpenAI")
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
                    if !isActive {
                        Button("Switch") { onSwitch() }
                            .controlSize(.mini)
                    }
                    if isActive {
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
