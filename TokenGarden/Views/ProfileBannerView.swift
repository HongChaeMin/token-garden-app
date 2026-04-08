// TokenGarden/Views/ProfileBannerView.swift
import SwiftUI
import SwiftData

struct ProfileBannerView: View {
    @EnvironmentObject var profileManager: ProfileManager
    let onTap: () -> Void
    var onCodexTap: (() -> Void)?

    @Query private var codexProfiles: [CodexProfile]
    @AppStorage("codexModel") private var codexModel: String = "gpt-5.4"

    private var activeCodexProfile: CodexProfile? {
        guard let email = CodexWatcher.currentAccount()?.email else { return nil }
        return codexProfiles.first { $0.email == email }
    }

    private var codexModels: [String] {
        let path = NSHomeDirectory() + "/.codex/models_cache.json"
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["models"] as? [[String: Any]]
        else { return ["gpt-5.4"] }
        return models.compactMap { $0["slug"] as? String }
    }

    private var modelColor: Color {
        switch profileManager.currentModel {
        case "sonnet": return .orange
        case "haiku": return .mint
        default: return .purple
        }
    }

    private var codexExists: Bool {
        FileManager.default.fileExists(atPath: NSHomeDirectory() + "/.codex/state_5.sqlite")
    }

    var body: some View {
        VStack(spacing: 8) {
            // Claude Code section
            Text("Claude Code")
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 6) {
                Button(action: onTap) {
                    if let profile = profileManager.activeProfile {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 8, height: 8)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(profile.name)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                Text("\(profile.email) · \(profile.plan)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    } else {
                        HStack {
                            Image(systemName: "person.crop.circle.badge.plus")
                                .foregroundStyle(.secondary)
                            Text("Add Profile")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .buttonStyle(.plain)

                // Claude model selector
                HStack(spacing: 4) {
                    ForEach(["opus", "sonnet", "haiku"], id: \.self) { model in
                        let isActive = profileManager.currentModel == model
                        Button(action: { profileManager.setModel(model) }) {
                            Text(model.capitalized)
                                .font(.caption2)
                                .fontWeight(isActive ? .semibold : .regular)
                                .foregroundStyle(isActive ? .white : .secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(isActive ? modelColor : Color.clear, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                    Text("Next session")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(8)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))

            // Codex section
            if codexExists {
                Text("Codex")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                VStack(spacing: 6) {
                    Button(action: { onCodexTap?() }) {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 8, height: 8)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(activeCodexProfile?.name ?? "Codex")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                Text((CodexWatcher.currentAccount()?.email ?? "OpenAI") + " · Codex CLI")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)

                    // Codex model selector
                    HStack(spacing: 4) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 4) {
                                ForEach(codexModels, id: \.self) { model in
                                    let isActive = codexModel == model
                                    Button(action: { setCodexModel(model) }) {
                                        Text(model)
                                            .font(.system(size: 9))
                                            .fontWeight(isActive ? .semibold : .regular)
                                            .foregroundStyle(isActive ? .white : .secondary)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 3)
                                            .background(isActive ? codexModelColor(model) : Color.clear, in: Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        Text("Next session")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(8)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private func codexModelColor(_ model: String) -> Color {
        let colors: [Color] = [.green, .blue, .purple, .orange, .pink, .indigo, .brown]
        let hash = model.unicodeScalars.reduce(0) { $0 &+ Int($1.value) &* 31 }
        return colors[abs(hash) % colors.count]
    }

    private func setCodexModel(_ model: String) {
        codexModel = model
        let configPath = NSHomeDirectory() + "/.codex/config.toml"
        let configURL = URL(fileURLWithPath: configPath)
        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        var lines = (try? String(contentsOf: configURL, encoding: .utf8))?.components(separatedBy: "\n") ?? []
        let newLine = "model = \"\(model)\""
        if let idx = lines.firstIndex(where: {
            $0.trimmingCharacters(in: .whitespaces).hasPrefix("model =")
        }) {
            lines[idx] = newLine
        } else {
            lines.insert(newLine, at: 0)
        }
        try? lines.joined(separator: "\n").write(to: configURL, atomically: true, encoding: .utf8)
    }
}
