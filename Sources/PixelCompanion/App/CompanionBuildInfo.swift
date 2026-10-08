import Foundation

/// Identifies a packaged release or local QA update without relying on the app filename.
enum CompanionBuildInfo {
    static var version: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let shortVersion = info["CFBundleShortVersionString"] as? String ?? "Development"
        let build = info["CFBundleVersion"] as? String ?? "local"
        return "\(shortVersion) (build \(build))"
    }

    static var qaUpdate: String? {
        guard let number = Bundle.main.infoDictionary?["PCQAUpdateNumber"] as? String,
              !number.isEmpty else { return nil }
        return "QA Update #\(number)"
    }

    static var settingsTitle: String {
        guard let qaUpdate else { return "Pixel Companion Settings" }
        return "Pixel Companion Settings — \(qaUpdate)"
    }
}
