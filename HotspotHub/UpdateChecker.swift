import Foundation
import Combine

struct HotspotHubRelease: Decodable, Identifiable {
    let tagName: String
    let htmlURL: URL
    let body: String?
    var id: String { tagName }
    var version: String { tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName }
    enum CodingKeys: String, CodingKey { case tagName = "tag_name", htmlURL = "html_url", body }
}

@MainActor
final class UpdateChecker: ObservableObject {
    @Published private(set) var latest: HotspotHubRelease?
    @Published private(set) var message: String?
    @Published private(set) var isChecking = false
    private let lastCheckKey = "updateCheckTimestamp"
    private let latestReleaseURL = URL(string: "https://api.github.com/repos/naahs-lawragga/HotspotHub-iOS/releases/latest")!

    var currentVersion: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0" }
    var hasUpdate: Bool { latest.map { compare($0.version, currentVersion) > 0 } ?? false }

    func checkIfDue() async {
        let last = UserDefaults.standard.double(forKey: lastCheckKey)
        guard Date().timeIntervalSince1970 - last > 6 * 60 * 60 else { return }
        await checkNow()
    }

    func checkNow() async {
        guard !isChecking else { return }
        isChecking = true; message = nil
        defer { isChecking = false; UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastCheckKey) }
        do {
            var request = URLRequest(url: latestReleaseURL)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("HotspotHub-iOS", forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = 15
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { message = "Could not check GitHub Releases."; return }
            let release = try JSONDecoder().decode(HotspotHubRelease.self, from: data)
            guard compare(release.version, currentVersion) >= 0 else { message = "No newer stable release is available."; return }
            latest = release
            if !hasUpdate { message = "HotspotHub is up to date." }
        } catch { message = "Update check failed: \(error.localizedDescription)" }
    }

    private func compare(_ left: String, _ right: String) -> Int {
        func parts(_ value: String) -> [Int] { value.split(separator: ".").prefix(3).map { Int($0.prefix { $0.isNumber }) ?? 0 } + [0, 0, 0] }
        let a = parts(left), b = parts(right)
        for index in 0..<3 where a[index] != b[index] { return a[index] < b[index] ? -1 : 1 }
        return 0
    }
}
