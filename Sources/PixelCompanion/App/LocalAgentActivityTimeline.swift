import Combine
import Foundation

/// Scrubbed, local-only timeline. These are observed marker updates, not a
/// full agent audit stream: intermediate events may be lost between polls.
enum LocalAgentActivitySource: String, CaseIterable, Identifiable {
    case codex
    case claudeCode

    var id: Self { self }
    var label: String {
        switch self {
        case .codex: "Codex"
        case .claudeCode: "Claude Code"
        }
    }
}

struct LocalAgentActivityEvent: Identifiable, Equatable {
    let id: String
    let source: LocalAgentActivitySource
    let label: String
    let timestamp: Date
}

enum LocalAgentActivityFilter: String, CaseIterable {
    case all
    case codex
    case claudeCode

    var label: String {
        switch self {
        case .all: "All"
        case .codex: "Codex"
        case .claudeCode: "Claude Code"
        }
    }

    func includes(_ event: LocalAgentActivityEvent) -> Bool {
        switch self {
        case .all: true
        case .codex: event.source == .codex
        case .claudeCode: event.source == .claudeCode
        }
    }
}

/// Only keeps event type + timestamp in RAM. The original marker files
/// remain governed by the independently opt-in source monitors.
@MainActor
final class LocalAgentActivityTimeline: ObservableObject {
    static let maximumEvents = 20
    static let retentionInterval: TimeInterval = 1_800
    @Published private(set) var events: [LocalAgentActivityEvent] = []
    private var subscriptions = Set<AnyCancellable>()
    private let now: () -> Date

    init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    func bind(codex: CodexTurnMonitor, claude: ClaudeHookMonitor) {
        subscriptions.removeAll()
        codex.$status.sink { [weak self] status in
            MainActor.assumeIsolated { self?.receive(codex: status) }
        }
        .store(in: &subscriptions)
        claude.$status.sink { [weak self] status in
            MainActor.assumeIsolated { self?.receive(claude: status) }
        }
        .store(in: &subscriptions)
    }

    func receive(codex status: CodexTurnStatus) {
        switch status {
        case let .observed(date):
            record(source: .codex, kind: "agent-turn-complete",
                   label: "Turn finished (outcome unknown)", timestamp: date)
        case .off, .unconnected, .unavailable:
            clear(source: .codex)
        }
    }

    func receive(claude status: ClaudeHookStatus) {
        switch status {
        case let .observed(event, timestamp):
            record(source: .claudeCode, kind: event.rawValue,
                   label: event.label, timestamp: timestamp)
        case .off, .unconnected, .unavailable:
            clear(source: .claudeCode)
        }
    }

    func visible(
        filter: LocalAgentActivityFilter = .all,
        at reference: Date
    ) -> [LocalAgentActivityEvent] {
        events.filter { event in
            filter.includes(event)
                && event.timestamp.timeIntervalSince(reference) <= 30
                && reference.timeIntervalSince(event.timestamp) <= Self.retentionInterval
        }
    }

    private func record(
        source: LocalAgentActivitySource, kind: String,
        label: String, timestamp: Date
    ) {
        let reference = now()
        let age = reference.timeIntervalSince(timestamp)
        // Opening an old marker cannot suddenly synthesize a fresh event.
        guard age >= -30, age <= 120 else {
            prune(at: reference)
            return
        }
        // Same kind and timestamp is the same file marker, even after polling.
        let identifier = source.rawValue + ":" + kind + ":" +
            String(timestamp.timeIntervalSince1970)
        guard !events.contains(where: { $0.id == identifier }) else {
            prune(at: reference)
            return
        }
        events.append(LocalAgentActivityEvent(
            id: identifier, source: source, label: label, timestamp: timestamp
        ))
        events.sort {
            if $0.timestamp != $1.timestamp { return $0.timestamp > $1.timestamp }
            return $0.id < $1.id
        }
        prune(at: reference)
    }

    private func prune(at reference: Date) {
        let valid = events.filter {
            reference.timeIntervalSince($0.timestamp) <= Self.retentionInterval
                && $0.timestamp.timeIntervalSince(reference) <= 30
        }
        let bounded = Array(valid.prefix(Self.maximumEvents))
        if events != bounded { events = bounded }
    }

    private func clear(source: LocalAgentActivitySource) {
        let remaining = events.filter { $0.source != source }
        if events != remaining { events = remaining }
    }
}
