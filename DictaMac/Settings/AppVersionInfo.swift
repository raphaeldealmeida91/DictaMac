import Foundation

struct AppVersionInfo: Equatable, Sendable {
    let marketingVersion: String
    let buildNumber: String

    var description: String {
        "Version \(marketingVersion) (build \(buildNumber))"
    }

    static var current: AppVersionInfo {
        let dictionary = Bundle.main.infoDictionary
        return AppVersionInfo(
            marketingVersion: dictionary?["CFBundleShortVersionString"] as? String ?? "—",
            buildNumber: dictionary?["CFBundleVersion"] as? String ?? "—"
        )
    }
}
