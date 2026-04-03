// TokenGarden/Views/ProfileBannerView.swift
import SwiftUI
import SwiftData

struct ProfileBannerView: View {
    @EnvironmentObject var profileManager: ProfileManager
    let onTap: () -> Void

    private var modelLabel: String {
        switch profileManager.currentModel {
        case "sonnet": return "Sonnet"
        case "haiku": return "Haiku"
        default: return "Opus"
        }
    }

    private var modelColor: Color {
        switch profileManager.currentModel {
        case "sonnet": return .orange
        case "haiku": return .mint
        default: return .purple
        }
    }

    var body: some View {
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

            // Model selector
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
                            .background(
                                isActive ? modelColor : Color.clear,
                                in: Capsule()
                            )
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
    }
}
