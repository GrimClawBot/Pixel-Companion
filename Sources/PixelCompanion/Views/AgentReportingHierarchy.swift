import Foundation
import PixelCompanionCore

/// Read-only reporting, never a guessed department or inferred security authority.
struct AgentReportingRow: Identifiable {
    let session: AgentSessionSnapshot
    let depth: Int
    let managerName: String?
    let note: String?

    var id: String { session.agentID }
}

enum AgentReportingHierarchy {
    private struct ReportingLink {
        let parent: String?
        let note: String?
    }

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
            let link = verifiedLink(for: session, in: byID)
            if let parent = link.parent { parents[session.agentID] = parent }
            if let note = link.note { notes[session.agentID] = note }
        }
        return flattenedRows(ordered: ordered, byID: byID, parents: parents, notes: notes)
    }

    /// Fail closed if any ancestor is absent, filtered out, cyclic or self-referencing.
    private static func verifiedLink(
        for session: AgentSessionSnapshot, in byID: [String: AgentSessionSnapshot]
    ) -> ReportingLink {
        guard let parentID = normalized(session.managerAgentID) else {
            return ReportingLink(parent: nil, note: nil)
        }
        var seen = Set<String>()
        var current = session.agentID
        while true {
            guard seen.insert(current).inserted else {
                return ReportingLink(parent: nil, note: "Reporting cycle not verified")
            }
            guard let node = byID[current] else {
                return ReportingLink(parent: nil, note: "Manager chain not in this view")
            }
            guard let next = normalized(node.managerAgentID) else {
                return ReportingLink(parent: parentID, note: nil)
            }
            guard byID[next] != nil else {
                return ReportingLink(parent: nil, note: "Manager not in this view")
            }
            current = next
        }
    }

    private static func flattenedRows(
        ordered: [AgentSessionSnapshot],
        byID: [String: AgentSessionSnapshot],
        parents: [String: String],
        notes: [String: String]
    ) -> [AgentReportingRow] {
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
        let verified = rows(sessions).first { $0.session.agentID == session.agentID }
        guard verified?.managerName != nil,
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
