import Foundation

extension PaperclipMapper {
    /// Only confirmed, structured issue status determines semantic classification.
    /// Names containing "testing", "security", or "deploy" are not authority.
    static func issueSignal(_ status: String) -> CompanionSignalKind? {
        switch status.lowercased() {
        case "done", "completed", "closed": return .success
        case "failed", "error": return .failure
        case "in_progress", "running", "started": return .working
        default: return nil
        }
    }

    static func issueKind(_ rawStatus: String) -> ActivityEvent.Kind {
        let status = rawStatus.lowercased()
        if ["done", "completed", "closed"].contains(status) { return .completed }
        if ["failed", "error", "cancelled"].contains(status) { return .failed }
        if ["in_progress", "running", "started"].contains(status) { return .running }
        return .note
    }

}
