import SwiftUI
import ServiceManagement

enum MenuBarDisplayMode: String, CaseIterable {
    case iconOnly = "Icon Only"
    case iconAndNumber = "Icon + Tokens"
    case iconAndMiniGraph = "Icon + Mini Graph"
}

struct SettingsView: View {
    @EnvironmentObject var updateChecker: UpdateChecker
    @AppStorage("logPath") private var logPath = "~/.claude/"
    @AppStorage("displayMode") private var displayMode = MenuBarDisplayMode.iconOnly.rawValue
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("heatmapTheme") private var heatmapTheme = HeatmapTheme.green.rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            // Menu Bar
            VStack(alignment: .leading, spacing: 6) {
                Text("Menu Bar")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("Display", selection: $displayMode) {
                    ForEach(MenuBarDisplayMode.allCases, id: \.rawValue) { mode in
                        Text(mode.rawValue).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .controlSize(.small)
            }

            Divider()

            // Heatmap Theme
            VStack(alignment: .leading, spacing: 6) {
                Text("Heatmap Theme")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                let columns = [GridItem(.adaptive(minimum: 90), spacing: 8)]
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(HeatmapTheme.allCases, id: \.rawValue) { theme in
                        let isSelected = heatmapTheme == theme.rawValue
                        VStack(spacing: 3) {
                            HStack(spacing: 2) {
                                ForEach(1..<8, id: \.self) { i in
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(theme.colors[i])
                                        .frame(width: 10, height: 10)
                                }
                            }
                            Text(theme.rawValue)
                                .font(.system(size: 8))
                                .foregroundStyle(isSelected ? .primary : .secondary)
                        }
                        .padding(4)
                        .background(
                            isSelected ? Color.accentColor.opacity(0.15) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 6)
                        )
                        .onTapGesture {
                            heatmapTheme = theme.rawValue
                        }
                    }
                }
            }

            Divider()

            // General
            VStack(alignment: .leading, spacing: 6) {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .controlSize(.small)
                    .onChange(of: launchAtLogin) { _, newValue in
                        do {
                            if newValue {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            launchAtLogin = !newValue
                        }
                    }
            }

            Divider()

            // Update
            HStack {
                Text("v\(updateChecker.currentVersion)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if updateChecker.isChecking {
                    ProgressView()
                        .controlSize(.small)
                } else if updateChecker.hasUpdate, let version = updateChecker.latestVersion {
                    Button("Update to v\(version)") {
                        if let url = updateChecker.downloadURL {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .controlSize(.small)
                } else {
                    Button("Check for Updates") {
                        updateChecker.check()
                    }
                    .controlSize(.small)
                }
            }

            Divider()

            Button("Quit Token Garden") {
                NSApplication.shared.terminate(nil)
            }
            .controlSize(.small)
        }
        .padding(12)
    }
}
