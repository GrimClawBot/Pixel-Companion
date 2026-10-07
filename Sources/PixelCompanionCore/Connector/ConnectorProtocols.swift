import Foundation

// Every protocol here is read-only by contract: implementations report state, they never
// mutate anything on the backing service. Service-specific behaviour (Pixel HQ, Paperclip or
// anything else) lives behind these protocols; the app itself knows no endpoints.

/// Reports identity status. Never exposes credentials.
public protocol AuthProvider: AnyObject {
    var authStatus: AuthStatus { get }
}

/// Supplies the agent activity feed.
public protocol ActivitySource: AnyObject {
    /// The most recent event, or `nil` when nothing has happened yet.
    var currentActivity: ActivityEvent? { get }

    /// Up to `limit` events, newest first.
    func recentActivity(limit: Int) -> [ActivityEvent]
}

/// Lists work that is waiting on a human. Approving or rejecting is out of scope.
public protocol ApprovalProvider: AnyObject {
    func pendingApprovals() -> [ApprovalRequest]
}

/// Reports consumption for the current period.
public protocol UsageProvider: AnyObject {
    func currentUsage() -> UsageSnapshot?
}

/// Exposes sanitized read-only agent and session summaries.
public protocol AgentSessionSource: AnyObject {
    /// Up to `limit` agent/session summaries, active first and otherwise most recent first.
    func agentSessions(limit: Int) -> [AgentSessionSnapshot]
}

/// Exposes recent conversation lines. Sending messages is out of scope.
public protocol ChatBackend: AnyObject {
    /// Up to `limit` messages, oldest first.
    func recentMessages(limit: Int) -> [ChatMessage]
}

/// A source of companion state. Every capability is optional so a connector can be as small
/// as an identifier plus a connection state.
public protocol Connector: AnyObject {
    var id: ConnectorID { get }
    var displayName: String { get }
    var connectionState: ConnectionState { get }
    /// Human-readable reason for `.error`; `nil` otherwise.
    var lastError: String? { get }

    var auth: (any AuthProvider)? { get }
    var activity: (any ActivitySource)? { get }
    var approvals: (any ApprovalProvider)? { get }
    var usage: (any UsageProvider)? { get }
    var sessions: (any AgentSessionSource)? { get }
    var chat: (any ChatBackend)? { get }

    /// Pulls the latest state from the source. Must not mutate the source.
    func refresh()
}

public extension Connector {
    var lastError: String? { nil }
    var auth: (any AuthProvider)? { nil }
    var activity: (any ActivitySource)? { nil }
    var approvals: (any ApprovalProvider)? { nil }
    var usage: (any UsageProvider)? { nil }
    var sessions: (any AgentSessionSource)? { nil }
    var chat: (any ChatBackend)? { nil }
    func refresh() {}
}
