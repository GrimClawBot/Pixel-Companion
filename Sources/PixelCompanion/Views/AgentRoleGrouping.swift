import Foundation
import PixelCompanionCore

struct AgentRoleGroup: Identifiable {
    let id: String
    let label: String
    let sessions: [AgentSessionSnapshot]
}

enum AgentRoleGrouping {
    static func groups(_ sessions: [AgentSessionSnapshot]) -> [AgentRoleGroup] {
        var buckets: [String: [AgentSessionSnapshot]] = [:]
        var labels: [String: String] = [:]
        for session in sessions {
            let normalized = session.agentRole?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let key = normalized.isEmpty ? "unknown" : "role:" + normalized.lowercased()
            let label = normalized.isEmpty ? "Role not reported" : normalized.capitalized
            buckets[key, default: []].append(session)
            if labels[key] == nil { labels[key] = label }
        }
        return buckets.map { key, members in
            AgentRoleGroup(
                id: key,
                label: labels[key] ?? "Role not reported",
                sessions: members
            )
        }.sorted {
            if $0.id == "unknown" { return false }
            if $1.id == "unknown" { return true }
            return $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending
        }
    }
}
