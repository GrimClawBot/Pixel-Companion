import Foundation

/// Explicit SwiftUI disclosure identity. Agent changes must invalidate the
/// checklist even if both agents have no session/run identifiers.
public struct SessionHandoffSelectionIdentity: Hashable, Sendable {
    public let agentID: String
    public let sessionID: String?
    public let runID: String?

    public init(session: AgentSessionSnapshot) {
        agentID = session.agentID
        sessionID = session.sessionID
        runID = session.runID
    }
}

/// An intentionally incomplete, in-memory handoff *checklist*, not a generated
/// prompt, transcript or transferable session. No fields come from raw logs.
public struct SessionHandoffEvidence: Hashable, Sendable {
    public struct AssignedTask: Hashable, Sendable {
        public let sourceID: String
        public let identifier: String?
        public let title: String
        public let status: String

        /// Always show an exact source identifier, even when a human-friendly
        /// task identifier is missing from this runtime's response.
        public var displayTitle: String {
            (identifier ?? sourceID) + " · " + title
        }
    }

    public let agentID: String
    public let agentName: String
    public let sessionID: String?
    public let runID: String?
    public let runState: AgentSessionSnapshot.RunState
    public let provider: String?
    public let model: String?
    public let assignedTasks: [AssignedTask]
    public let contextHealth: ContextHealth
    public let evidenceIsBounded: Bool

    /// This connector does not provide a reliable, safe handoff-ready record
    /// for these fields; never synthesize one from a task title or model output.
    public static let missingForHandoff: [String] = [
        "Objective and desired outcome",
        "Decisions and rationale",
        "Outstanding blockers and next steps",
        "Approved actions and permissions",
        "Authorized memory references"
    ]

    public static func prepare(
        session: AgentSessionSnapshot,
        assignedTasks: [TaskSnapshot],
        isLive: Bool
    ) -> SessionHandoffEvidence? {
        guard isLive, !session.agentID.isEmpty else { return nil }
        var seen = Set<String>()
        var selected: [AssignedTask] = []
        let verified = assignedTasks.filter { task in
            task.assigneeAgentID == session.agentID &&
                !task.id.isEmpty && !task.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        for task in verified {
            guard seen.insert(task.id).inserted else { continue }
            if selected.count < 5 {
                selected.append(AssignedTask(
                    sourceID: task.id, identifier: nonEmpty(task.identifier),
                    title: task.title, status: task.status
                ))
            }
        }
        return SessionHandoffEvidence(
            agentID: session.agentID,
            agentName: session.agentName,
            sessionID: nonEmpty(session.sessionID),
            runID: nonEmpty(session.runID),
            runState: session.runState,
            provider: nonEmpty(session.provider),
            model: nonEmpty(session.model),
            assignedTasks: selected,
            contextHealth: ContextHealth(
                reportedUsed: session.contextUsedTokens,
                reportedWindow: session.contextWindowTokens,
                confidence: .providerReported
            ),
            evidenceIsBounded: seen.count > selected.count
        )
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return value
    }

    private init(
        agentID: String, agentName: String, sessionID: String?, runID: String?,
        runState: AgentSessionSnapshot.RunState, provider: String?, model: String?,
        assignedTasks: [AssignedTask], contextHealth: ContextHealth,
        evidenceIsBounded: Bool
    ) {
        self.agentID = agentID
        self.agentName = agentName
        self.sessionID = sessionID
        self.runID = runID
        self.runState = runState
        self.provider = provider
        self.model = model
        self.assignedTasks = assignedTasks
        self.contextHealth = contextHealth
        self.evidenceIsBounded = evidenceIsBounded
    }
}
