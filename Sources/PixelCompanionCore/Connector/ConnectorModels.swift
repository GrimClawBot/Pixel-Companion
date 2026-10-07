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

    public init(id: String, kind: Kind, title: String, detail: String? = nil, timestamp: Date) {
        self.id = id
        self.kind = kind
        self.title = title
        self.detail = detail
        self.timestamp = timestamp
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
