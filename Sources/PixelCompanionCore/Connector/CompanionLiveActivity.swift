import Foundation

/// Public semantic vocabulary. Connectors must supply these from structured status
/// or authorized canonical events, never guessed from a title or task text.
public enum CompanionSignalKind: String, CaseIterable, Hashable, Sendable {
    case idle
    case thinking
    case coding
    case testing
    case reviewing
    case working
    case success
    case ownerApproval
    case budgetWarning
    case agentFailure
    case failure
    case infrastructureAlert
    case securityAlert

    public var priority: Int {
        switch self {
        case .securityAlert: return 900
        case .ownerApproval: return 800
        case .infrastructureAlert: return 700
        case .agentFailure, .failure: return 600
        case .budgetWarning: return 550
        case .coding, .testing, .reviewing, .thinking: return 400
        case .working: return 350
        case .success: return 300
        case .idle: return 0
        }
    }

    public var displayName: String {
        switch self {
        case .idle: return "Quiet"
        case .thinking: return "Thinking"
        case .coding: return "Coding"
        case .testing: return "Testing"
        case .reviewing: return "Reviewing"
        case .working: return "Working"
        case .success: return "Completed"
        case .ownerApproval: return "Approval needed"
        case .budgetWarning: return "Budget warning"
        case .agentFailure, .failure: return "Run failed"
        case .infrastructureAlert: return "Infrastructure alert"
        case .securityAlert: return "Security alert"
        }
    }

    public var characterMood: CharacterMood {
        switch self {
        case .securityAlert: return .securityAlert
        case .infrastructureAlert: return .infrastructureAlert
        case .budgetWarning: return .budgetWarning
        case .ownerApproval: return .waitingForApproval
        case .failure, .agentFailure: return .error
        case .success: return .success
        case .working, .coding, .thinking, .testing, .reviewing:
            return detailedWorkingMood
        case .idle: return .idle
        }
    }

    private var detailedWorkingMood: CharacterMood {
        switch self {
        case .thinking: return .thinking
        case .coding: return .coding
        case .testing: return .testing
        case .reviewing: return .reviewing
        default: return .working
        }
    }

    /// A terminal completion should never remain a celebration forever.
    public var isTransient: Bool { self == .success || self == .failure }
}

/// Strict metadata: no denominator means no progress fraction.
public struct CompanionReportedProgress: Hashable, Sendable {
    public let current: Int
    public let total: Int

    public init?(current: Int, total: Int) {
        guard total > 0, current >= 0, current <= total else { return nil }
        self.current = current
        self.total = total
    }
}

public struct CompanionLiveSignal: Identifiable, Hashable, Sendable {
    public let id: String
    public let schemaVersion: Int
    public let sourceID: String
    public let kind: CompanionSignalKind
    public let title: String
    public let timestamp: Date
    public let entityID: String?
    public let progress: CompanionReportedProgress?

    public init(
        id: String, sourceID: String, kind: CompanionSignalKind,
        title: String, timestamp: Date, entityID: String? = nil,
        progress: CompanionReportedProgress? = nil
    ) {
        self.id = id
        self.schemaVersion = 1
        self.sourceID = sourceID
        self.kind = kind
        self.title = title
        self.timestamp = timestamp
        self.entityID = entityID
        self.progress = progress
    }
}

/// Derives a compact primary activity and a bounded expanded stack from canonical
/// signal metadata, preserving source IDs and honoring Paperclip freshness.
public enum CompanionLiveActivityResolver {
    public static let transientLifetime: TimeInterval = 90

    public static func signals(
        for snapshot: ConnectorSnapshot, isLive: Bool, now: Date = Date()
    ) -> [CompanionLiveSignal] {
        guard isLive, snapshot.connectionState == .connected else { return [] }
        var events = snapshot.recentActivity
        if let current = snapshot.currentActivity { events.insert(current, at: 0) }

        var seen = Set<String>()
        var result: [CompanionLiveSignal] = []
        if let approval = snapshot.pendingApprovals.first {
            result.append(CompanionLiveSignal(
                id: "approval:" + approval.id,
                sourceID: "connector:" + snapshot.connectorName,
                kind: .ownerApproval,
                title: "Approval requested",
                timestamp: approval.requestedAt,
                entityID: approval.id
            ))
        }

        for event in events {
            guard let kind = event.signal,
                  let source = event.sourceID, !source.isEmpty,
                  seen.insert(source + ":" + event.id).inserted else { continue }
            if kind.isTransient {
                let age = now.timeIntervalSince(event.timestamp)
                guard age >= 0, age <= transientLifetime else { continue }
            }
            guard kind != .idle else { continue }
            result.append(CompanionLiveSignal(
                id: source + ":" + event.id,
                sourceID: source,
                kind: kind,
                title: event.title,
                timestamp: event.timestamp,
                entityID: event.entityID,
                progress: event.progress
            ))
        }
        return result.sorted {
            if $0.kind.priority != $1.kind.priority {
                return $0.kind.priority > $1.kind.priority
            }
            if $0.timestamp != $1.timestamp { return $0.timestamp > $1.timestamp }
            return $0.id < $1.id
        }
    }

    public static func primary(
        for snapshot: ConnectorSnapshot, isLive: Bool, now: Date = Date()
    ) -> CompanionLiveSignal? {
        signals(for: snapshot, isLive: isLive, now: now).first
    }
}
