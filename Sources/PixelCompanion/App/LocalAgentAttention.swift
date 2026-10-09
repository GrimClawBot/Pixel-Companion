import Combine
import Foundation

/// Only milestones that can honestly benefit from a quiet reminder.
/// Never interpret an event as an approval request or successful task.
enum LocalAgentAlert: Equatable {
    case codexTurnEnded
    case claudeResponseEnded
    case claudeResponseFailed

    static func from(_ event: LocalAgentActivityEvent) -> Self? {
        switch (event.source, event.label) {
        case (.codex, "Turn finished (outcome unknown)"):
            return .codexTurnEnded
        case (.claudeCode, "Response finished"):
            return .claudeResponseEnded
        case (.claudeCode, "Response ended with API error"):
            return .claudeResponseFailed
        default:
            return nil
        }
    }

    var title: String {
        switch self {
        case .codexTurnEnded: "Codex turn ended"
        case .claudeResponseEnded: "Claude Code response ended"
        case .claudeResponseFailed: "Claude Code reported an API error"
        }
    }

    var detail: String {
        switch self {
        case .codexTurnEnded: "Outcome not reported"
        case .claudeResponseEnded: "Task outcome not verified"
        case .claudeResponseFailed: "Response ended due to an API error"
        }
    }
}

/// No durable event history and no notifications on startup/enable.
/// No prompt, response, agent ID or workspace data flows to the alert.
@MainActor
final class LocalAgentAttention: ObservableObject {
    static let minimumNotificationGap: TimeInterval = 90
    static let maximumNotificationAge: TimeInterval = 30

    @Published private(set) var latest: [LocalAgentActivityEvent] = []
    private var subscription: AnyCancellable?
    private var recognizedIDs = Set<String>()
    private var lastNotificationAt: Date?
    private var notificationsEnabled = false
    private let now: () -> Date
    private var deliver: ((LocalAgentAlert) -> Void)?

    init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    func bind(
        timeline: LocalAgentActivityTimeline,
        deliver notice: @escaping (LocalAgentAlert) -> Void
    ) {
        deliver = notice
        subscription = timeline.$events.sink { [weak self] events in
            MainActor.assumeIsolated { self?.observe(events) }
        }
    }

    func configureNotifications(enabled: Bool) {
        guard notificationsEnabled != enabled else { return }
        notificationsEnabled = enabled
        // Enabling notification delivery NEVER replays already-observed events.
        recognizedIDs.formUnion(latest.map(\.id))
        // Preserve cooldown across OFF/ON changes to avoid alert bursts.
    }

    private func observe(_ events: [LocalAgentActivityEvent]) {
        latest = Array(events.filter { LocalAgentAlert.from($0) != nil }.prefix(2))
        let previouslySeen = recognizedIDs
        recognizedIDs.formUnion(events.map(\.id))
        // Bounded by source monitors and current timeline; no unbounded ID history.
        if recognizedIDs.count > 100 {
            recognizedIDs = Set(events.map(\.id))
        }
        guard notificationsEnabled else { return }
        let reference = now()
        let newEvents = events.filter { !previouslySeen.contains($0.id) }
            .sorted { $0.timestamp < $1.timestamp }
        for event in newEvents {
            guard let alert = LocalAgentAlert.from(event) else { continue }
            let age = reference.timeIntervalSince(event.timestamp)
            guard age >= -5 && age <= Self.maximumNotificationAge else { continue }
            if let lastNotificationAt,
               reference.timeIntervalSince(lastNotificationAt) < Self.minimumNotificationGap {
                continue
            }
            lastNotificationAt = reference
            deliver?(alert)
            // At most one per received snapshot, even across multiple sources.
            break
        }
    }
}
