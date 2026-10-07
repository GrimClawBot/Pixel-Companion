import Foundation

/// The only connector in PC-001: replays a `MockScript` with no network, credentials or side
/// effects. All state is a pure function of `tick`, `script` and `simulatedConnectionState`.
public final class MockConnector: Connector {
    public let id: ConnectorID
    public let displayName: String
    public let script: MockScript

    /// Number of steps played since the start; the current step is `script.step(at: tick)`.
    public private(set) var tick: Int

    /// Lets settings simulate transport problems. The script only advances while `.connected`.
    public var simulatedConnectionState: ConnectionState

    public init(
        id: ConnectorID,
        displayName: String,
        script: MockScript,
        connectionState: ConnectionState = .connected,
        startTick: Int = 0
    ) {
        self.id = id
        self.displayName = displayName
        self.script = script
        self.simulatedConnectionState = connectionState
        self.tick = max(startTick, 0)
    }

    public var currentStep: MockStep { script.step(at: tick) }

    /// Moves the script forward by `steps` regardless of connection state (for tests and demos).
    public func advance(by steps: Int = 1) {
        tick = max(tick + steps, 0)
    }

    public func reset() {
        tick = 0
    }

    // MARK: Connector

    public var connectionState: ConnectionState { simulatedConnectionState }

    public var lastError: String? {
        simulatedConnectionState == .error ? "Simulated connection error" : nil
    }

    public var auth: (any AuthProvider)? { self }
    public var activity: (any ActivitySource)? { self }
    public var approvals: (any ApprovalProvider)? { self }
    public var usage: (any UsageProvider)? { self }
    public var chat: (any ChatBackend)? { self }

    public func refresh() {
        guard simulatedConnectionState == .connected else { return }
        advance()
    }

    private func event(at tick: Int) -> ActivityEvent {
        let step = script.step(at: tick)
        return ActivityEvent(
            id: "mock-\(tick)",
            kind: step.kind,
            title: step.title,
            detail: step.detail,
            timestamp: script.timestamp(at: tick)
        )
    }
}

extension MockConnector: AuthProvider {
    public var authStatus: AuthStatus { .notRequired }
}

extension MockConnector: ActivitySource {
    public var currentActivity: ActivityEvent? { event(at: tick) }

    public func recentActivity(limit: Int) -> [ActivityEvent] {
        guard limit > 0 else { return [] }
        let oldest = max(tick - limit + 1, 0)
        return (oldest...tick).reversed().map { event(at: $0) }
    }
}

extension MockConnector: ApprovalProvider {
    public func pendingApprovals() -> [ApprovalRequest] {
        currentStep.pendingApprovals.enumerated().map { index, title in
            ApprovalRequest(id: "mock-\(tick)-approval-\(index)", title: title, requestedAt: script.timestamp(at: tick))
        }
    }
}

extension MockConnector: UsageProvider {
    public func currentUsage() -> UsageSnapshot? {
        UsageSnapshot(used: currentStep.usageUsed, limit: script.usageLimit, unit: "requests", periodLabel: "Today")
    }
}

extension MockConnector: ChatBackend {
    public func recentMessages(limit: Int) -> [ChatMessage] {
        guard limit > 0 else { return [] }
        var messages: [ChatMessage] = []
        var cursor = tick
        // The script loops, so look back at most one full cycle.
        let earliest = max(tick - script.steps.count + 1, 0)
        while cursor >= earliest, messages.count < limit {
            if let text = script.step(at: cursor).message {
                let message = ChatMessage(
                    id: "mock-\(cursor)-message", role: .assistant, text: text, timestamp: script.timestamp(at: cursor)
                )
                messages.append(message)
            }
            cursor -= 1
        }
        return messages.reversed()
    }
}
