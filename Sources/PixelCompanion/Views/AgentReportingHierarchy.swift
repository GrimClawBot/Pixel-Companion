import Foundation
import PixelCompanionCore

/// A read-only forest made solely from source-reported agent IDs and reportsTo.
/// Invalid, absent or filtered-out ancestors are not repaired with role/title guesses.
struct AgentReportingRow: Identifiable {
    let session: AgentSessionSnapshot
    let depth: Int
    let managerName: String?
    let note: String?

    var id: String { session.agentID }
}

enum AgentReportingHierarchy {
    static func rows(_ sessions: [AgentSessionSnapshot]) -> [AgentReportingRow] {
        var byID: [String: AgentSessionSnapshot] = [:]
        var ordered: [AgentSessionSnapshot] = []
        for session in sessions where !session.agentID.isEmpty {
            guard byID[session.agentID] == nil else { continue }
            byID[session.agentID] = session
            ordered.append(session)
        }

        var parents: [String: String] = [:]
        var notes: [String: String] = [:]
        for session in ordered {
            let parentID = normalized(session.managerAgentID)
            guard let parentID else { continue }

            // Validate the entire chain before displaying a hierarchical edge.
            var seen = Set<String>()
            var current = session.agentID
            var valid = true
            while true {
                guard seen.insert(current).inserted else {
                    notes[session.agentID] = "Reporting cycle not verified"
                    valid = false
                    break
                }
                guard let node = byID[current] else {
                    notes[session.agentID] = "Manager chain not in this view"
                    valid = false
                    break
                }
                guard let next = normalized(node.managerAgentID) else { break }
                guard byID[next] != nil else {
                    notes[session.agentID] = "Manager not in this view"
                    valid = false
                    break
                }
                current = next
            }
            if valid {
                parents[session.agentID] = parentID
            }
        }

        var children: [String: [AgentSessionSnapshot]] = [:]
        for session in ordered {
            if let parent = parents[session.agentID] {
                children[parent, default: []].append(session)
            }
        }

        var result: [AgentReportingRow] = []
        func appendTree(_ session: AgentSessionSnapshot, depth: Int) {
            let parentName = parents[session.agentID].flatMap { byID[$0]?.agentName }
            result.append(AgentReportingRow(
                session: session, depth: depth,
                managerName: parentName, note: notes[session.agentID]
            ))
            for child in children[session.agentID] ?? [] {
                appendTree(child, depth: depth + 1)
            }
        }
        for session in ordered where parents[session.agentID] == nil {
            appendTree(session, depth: 0)
        }
        return result
    }

    static func manager(
        for session: AgentSessionSnapshot, in sessions: [AgentSessionSnapshot]
    ) -> AgentSessionSnapshot? {
        let match = rows(sessions).first { $0.session.agentID == session.agentID }
        guard match?.managerName != nil,
              let managerID = normalized(session.managerAgentID) else {
            return nil
        }
        return sessions.first { $0.agentID == managerID }
    }

    private static func normalized(_ raw: String?) -> String? {
        guard let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }
}
