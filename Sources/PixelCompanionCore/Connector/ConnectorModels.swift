import Foundation

/// Stable identifier of a connector, persisted in settings.
public struct ConnectorID: RawRepresentable, Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public var description: String { rawValue }
}

/// Transport-level state of a connector.
public enum ConnectionState: String, CaseIterable, Sendable {
    case connected
    case connecting
    case disconnected
    case error

    public var displayName: String {
        switch self {
        case .connected: return "Connected"
        case .connecting: return "Connecting…"
        case .disconnected: return "Disconnected"
        case .error: return "Error"
        }
    }
}

/// Whether the backing service considers the user identified. Status only: the app never
/// requests, stores or displays credentials.
public enum AuthStatus: Equatable, Sendable {
    case notRequired
    case unauthenticated
    case authenticated(displayName: String)
}

/// One entry in an agent's activity feed.
public struct ActivityEvent: Identifiable, Hashable, Sendable {
    public enum Kind: String, CaseIterable, Sendable {
        case note
        case running
        case completed
        case failed
    }

    public let id: String
    public let kind: Kind
    public let title: String
    public let detail: String?
    public let timestamp: Date
    /// Optional canonical signal from a source-provided status, never inferred from free text.
    public let signal: CompanionSignalKind?
    /// Exact connector and backend entity identifiers, when supplied.
    public let sourceID: String?
    public let entityID: String?
    /// Explicit source-reported progress only; do not infer progress from tokens or elapsed time.
    public let progress: CompanionReportedProgress?

    public init(
        id: String, kind: Kind, title: String, detail: String? = nil,
        timestamp: Date, signal: CompanionSignalKind? = nil,
        sourceID: String? = nil, entityID: String? = nil,
        progress: CompanionReportedProgress? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.detail = detail
        self.timestamp = timestamp
        self.signal = signal
        self.sourceID = sourceID
        self.entityID = entityID
        self.progress = progress
    }
}

/// Something an agent is waiting on a human for. Read-only: the app shows it but cannot act on it.
public struct ApprovalRequest: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let requestedAt: Date

    public init(id: String, title: String, requestedAt: Date) {
        self.id = id
        self.title = title
        self.requestedAt = requestedAt
    }
}

/// Consumption against an optional quota for the current period.
public struct UsageSnapshot: Hashable, Sendable {
    public let used: Int
    public let limit: Int?
    public let unit: String
    public let periodLabel: String

    public init(used: Int, limit: Int?, unit: String, periodLabel: String) {
        self.used = used
        self.limit = limit
        self.unit = unit
        self.periodLabel = periodLabel
    }

    /// `used / limit` clamped to 0...1, or `nil` when there is no limit.
    public var fractionUsed: Double? {
        guard let limit, limit > 0 else { return nil }
        return min(max(Double(used) / Double(limit), 0), 1)
    }
}

/// A line of an agent conversation.
public struct ChatMessage: Identifiable, Hashable, Sendable {
    public enum Role: String, Sendable {
        case user
        case assistant
        case system
    }

    public let id: String
    public let role: Role
    public let text: String
    public let timestamp: Date

    public init(id: String, role: Role, text: String, timestamp: Date) {
        self.id = id
        self.role = role
        self.text = text
        self.timestamp = timestamp
    }
}

/// Read-only summary of one agent and its active or most recent execution session.
public struct AgentSessionSnapshot: Identifiable, Hashable, Sendable {
    public enum RunState: String, CaseIterable, Sendable {
        case queued
        case running
        case completed
        case failed
        case cancelled
        case idle
        case unknown
    }

    public let id: String
    public let agentID: String
    public let agentName: String
    public let agentTitle: String?
    /// Optional role exactly reported by the source; never an inferred department.
    public let agentRole: String?
    /// Structured reporting parent ID from the connected runtime, never inferred from role.
    public let managerAgentID: String?
    public let agentStatus: String
    public let runID: String?
    public let runState: RunState
    public let taskTitle: String?
    public let model: String?
    public let provider: String?
    public let sessionID: String?
    public let inputTokens: Int?
    public let cachedInputTokens: Int?
    public let outputTokens: Int?
    /// Paperclip agent monthly totals; these are not estimates of this run's cost.
    public let monthlySpendCents: Int?
    public let monthlyBudgetCents: Int?
    /// Context occupancy is known only if the runtime reports both exact values.
    public let contextUsedTokens: Int?
    public let contextWindowTokens: Int?
    /// At most five recent runs returned by the current bounded telemetry fetch.
    public let recentRuns: [AgentRunSnapshot]
    public let startedAt: Date?
    public let finishedAt: Date?
    public let updatedAt: Date?

    public init(
        id: String,
        agentID: String,
        agentName: String,
        agentTitle: String? = nil,
        agentRole: String? = nil,
        managerAgentID: String? = nil,
        agentStatus: String,
        runID: String? = nil,
        runState: RunState,
        taskTitle: String? = nil,
        model: String? = nil,
        provider: String? = nil,
        sessionID: String? = nil,
        inputTokens: Int? = nil,
        cachedInputTokens: Int? = nil,
        outputTokens: Int? = nil,
        monthlySpendCents: Int? = nil,
        monthlyBudgetCents: Int? = nil,
        contextUsedTokens: Int? = nil,
        contextWindowTokens: Int? = nil,
        recentRuns: [AgentRunSnapshot] = [],
        startedAt: Date? = nil,
        finishedAt: Date? = nil,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.agentID = agentID
        self.agentName = agentName
        self.agentTitle = agentTitle
        self.agentRole = agentRole
        self.managerAgentID = managerAgentID
        self.agentStatus = agentStatus
        self.runID = runID
        self.runState = runState
        self.taskTitle = taskTitle
        self.model = model
        self.provider = provider
        self.sessionID = sessionID
        self.inputTokens = inputTokens
        self.cachedInputTokens = cachedInputTokens
        self.outputTokens = outputTokens
        self.monthlySpendCents = monthlySpendCents
        self.monthlyBudgetCents = monthlyBudgetCents
        self.contextUsedTokens = contextUsedTokens
        self.contextWindowTokens = contextWindowTokens
        self.recentRuns = recentRuns
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.updatedAt = updatedAt
    }

    public var isActive: Bool {
        runState == .queued || runState == .running
    }
}
