import Foundation

/// Sanitized read-only task metadata from a connector. No logs, secrets or mutations.
public struct TaskSnapshot: Identifiable, Hashable, Sendable {
    public let id: String
    public let identifier: String?
    public let title: String
    public let status: String
    /// Only structured authoritative assignment; nil means not reported/unassigned.
    public let assigneeAgentID: String?
    public let updatedAt: Date?

    public init(
        id: String, identifier: String? = nil, title: String,
        status: String, assigneeAgentID: String? = nil, updatedAt: Date? = nil
    ) {
        self.id = id
        self.identifier = identifier
        self.title = title
        self.status = status
        self.assigneeAgentID = assigneeAgentID
        self.updatedAt = updatedAt
    }
}
