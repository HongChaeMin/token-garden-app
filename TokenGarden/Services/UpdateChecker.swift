import Foundation

@MainActor
class UpdateChecker: ObservableObject {
    @Published var latestVersion: String?
    @Published var downloadURL: URL?
    @Published var isChecking = false

    private let repo = "HongChaeMin/token-garden-app"

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    var hasUpdate: Bool {
        guard let latest = latestVersion else { return false }
        return compare(latest, isNewerThan: currentVersion)
    }

    func check() {
        guard !isChecking else { return }
        isChecking = true

        Task {
            defer { isChecking = false }

            guard let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else { return }
            var request = URLRequest(url: url)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.timeoutInterval = 10

            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String else { return }

            let version = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
            latestVersion = version

            if let assets = json["assets"] as? [[String: Any]],
               let dmgAsset = assets.first(where: { ($0["name"] as? String)?.hasSuffix(".dmg") == true }),
               let urlStr = dmgAsset["browser_download_url"] as? String {
                downloadURL = URL(string: urlStr)
            } else if let htmlURL = json["html_url"] as? String {
                downloadURL = URL(string: htmlURL)
            }
        }
    }

    private func compare(_ a: String, isNewerThan b: String) -> Bool {
        let partsA = a.split(separator: ".").compactMap { Int($0) }
        let partsB = b.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(partsA.count, partsB.count) {
            let va = i < partsA.count ? partsA[i] : 0
            let vb = i < partsB.count ? partsB[i] : 0
            if va > vb { return true }
            if va < vb { return false }
        }
        return false
    }
}
