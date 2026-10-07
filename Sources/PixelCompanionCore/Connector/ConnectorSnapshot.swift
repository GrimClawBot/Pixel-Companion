import Foundation

/// An immutable view of everything the UI shows, captured from a connector in one pass.
public struct ConnectorSnapshot: Equatable, Sendable {
    public var connectorName: String
    public var connectionState: ConnectionState
    public var lastError: String?
    public var authStatus: AuthStatus
    public var currentActivity: ActivityEvent?
    public var recentActivity: [ActivityEvent]
    public var pendingApprovals: [ApprovalRequest]
    public var usage: UsageSnapshot?
    public var agentSessions: [AgentSessionSnapshot]
    public var recentMessages: [ChatMessage]

    public init(
        connectorName: String,
        connectionState: ConnectionState,
        lastError: String? = nil,
        authStatus: AuthStatus = .notRequired,
        currentActivity: ActivityEvent? = nil,
        recentActivity: [ActivityEvent] = [],
        pendingApprovals: [ApprovalRequest] = [],
        usage: UsageSnapshot? = nil,
        agentSessions: [AgentSessionSnapshot] = [],
        recentMessages: [ChatMessage] = []
    ) {
        self.connectorName = connectorName
        self.connectionState = connectionState
        self.lastError = lastError
        self.authStatus = authStatus
        self.currentActivity = currentActivity
        self.recentActivity = recentActivity
        self.pendingApprovals = pendingApprovals
        self.usage = usage
        self.agentSessions = agentSessions
        self.recentMessages = recentMessages
    }

    /// Captures `connector`; missing capabilities become empty values. A `nil` connector yields
    /// `noConnector`, so the app works with no backing service at all.
    public init(
        capturing connector: (any Connector)?,
        activityLimit: Int = 8,
        sessionLimit: Int = 8,
        messageLimit: Int = 8
    ) {
        guard let connector else {
            self.init(connectorName: Self.noConnectorName, connectionState: .disconnected)
            return
        }
        self.init(
            connectorName: connector.displayName,
            connectionState: connector.connectionState,
            lastError: connector.connectionState == .error ? connector.lastError : nil,
            authStatus: connector.auth?.authStatus ?? .notRequired,
            currentActivity: connector.activity?.currentActivity,
            recentActivity: connector.activity?.recentActivity(limit: max(activityLimit, 0)) ?? [],
            pendingApprovals: connector.approvals?.pendingApprovals() ?? [],
            usage: connector.usage?.currentUsage(),
            agentSessions: connector.sessions?.agentSessions(limit: max(sessionLimit, 0)) ?? [],
            recentMessages: connector.chat?.recentMessages(limit: max(messageLimit, 0)) ?? []
        )
    }

    public static let noConnector = ConnectorSnapshot(capturing: nil)

    private static let noConnectorName = "No connector"
}
