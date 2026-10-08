import Foundation

/// Identifies a packaged release or local QA update without relying on the app filename.
enum CompanionBuildInfo {
    static var version: String {
        version(info: Bundle.main.infoDictionary ?? [:])
    }

    static var qaUpdate: String? {
        qaUpdate(info: Bundle.main.infoDictionary ?? [:])
    }

    static var settingsTitle: String {
        settingsTitle(info: Bundle.main.infoDictionary ?? [:])
    }

    static func version(info: [String: Any]) -> String {
        let shortVersion = info["CFBundleShortVersionString"] as? String ?? "Development"
        let build = info["CFBundleVersion"] as? String ?? "local"
        return "\(shortVersion) (build \(build))"
    }

    static func qaUpdate(info: [String: Any]) -> String? {
        guard let number = info["PCQAUpdateNumber"] as? String,
              !number.isEmpty else { return nil }
        return "QA Update #\(number)"
    }

    static func settingsTitle(info: [String: Any]) -> String {
        guard let update = qaUpdate(info: info) else { return "Pixel Companion Settings" }
        return "Pixel Companion Settings — \(update)"
    }
}
