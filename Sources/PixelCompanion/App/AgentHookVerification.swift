import Combine
import Foundation

/// This checks a *change to a local marker*, NOT the unforgeable identity of
/// Codex/Claude or success of any AI task. No commands, files or hooks written.
enum AgentHookCheckSource: String, CaseIterable, Identifiable {
    case codex
    case claude

    var id: Self { self }
    var title: String { self == .codex ? "Codex CLI notify" : "Claude Code lifecycle" }
}

enum AgentHookCheckState: Equatable {
    case notStarted
    case needsSetup
    case waiting(Date)
    case observed(Date)
    case timedOut
}

struct AgentHookMarker: Equatable {
    let kind: String
    let timestamp: Date

    static func codex(_ value: CodexTurnStatus) -> Self? {
        guard case let .observed(date) = value else { return nil }
        return Self(kind: "agent-turn-complete", timestamp: date)
    }

    static func claude(_ value: ClaudeHookStatus) -> Self? {
        guard case let .observed(event, date) = value else { return nil }
        return Self(kind: event.rawValue, timestamp: date)
    }
}

@MainActor
final class AgentHookVerifier: ObservableObject {
    static let maximumWait: TimeInterval = 180
    static let maximumMarkerAge: TimeInterval = 30

    @Published private(set) var codexState: AgentHookCheckState = .notStarted
    @Published private(set) var claudeState: AgentHookCheckState = .notStarted

    private struct Attempt {
        let started: Date
        let baseline: AgentHookMarker?
    }

    private var codexAttempt: Attempt?
    private var claudeAttempt: Attempt?
    private var subscriptions = Set<AnyCancellable>()
    private let now: () -> Date

    init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    /// Subscribe to already-existing opted-in monitor statuses. No new
    /// watcher, file selection, credential access or provider execution.
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

    func start(codex monitor: CodexTurnMonitor) {
        codexAttempt = nil
        guard monitor.isConnected else { codexState = .needsSetup; return }
        // Capture the baseline AFTER a deliberate, guarded refresh.
        monitor.refresh()
        let started = now()
        codexAttempt = Attempt(started: started, baseline: .codex(monitor.status))
        codexState = .waiting(started)
    }

    func start(claude monitor: ClaudeHookMonitor) {
        claudeAttempt = nil
        guard monitor.isConnected else { claudeState = .needsSetup; return }
        monitor.refresh()
        let started = now()
        claudeAttempt = Attempt(started: started, baseline: .claude(monitor.status))
        claudeState = .waiting(started)
    }

    func stop(_ source: AgentHookCheckSource) {
        switch source {
        case .codex:
            codexAttempt = nil
            codexState = .notStarted
        case .claude:
            claudeAttempt = nil
            claudeState = .notStarted
        }
    }

    func stopAll() {
        stop(.codex)
        stop(.claude)
        subscriptions.removeAll()
    }

    func state(for source: AgentHookCheckSource, at date: Date) -> AgentHookCheckState {
        let current = source == .codex ? codexState : claudeState
        if case let .waiting(started) = current,
           date.timeIntervalSince(started) > Self.maximumWait {
            return .timedOut
        }
        return current
    }

    func receive(codex status: CodexTurnStatus) {
        switch status {
        case .off, .unconnected:
            if codexAttempt != nil || codexState != .notStarted {
                codexAttempt = nil
                codexState = .needsSetup
            }
        case .unavailable:
            break // Still waiting for the first valid file; do not claim delivery.
        case .observed:
            guard let attempt = codexAttempt else { return }
            let result = evaluate(AgentHookMarker.codex(status), attempt: attempt)
            if let result {
                codexAttempt = nil
                codexState = result
            }
        }
    }

    func receive(claude status: ClaudeHookStatus) {
        switch status {
        case .off, .unconnected:
            if claudeAttempt != nil || claudeState != .notStarted {
                claudeAttempt = nil
                claudeState = .needsSetup
            }
        case .unavailable:
            break
        case .observed:
            guard let attempt = claudeAttempt else { return }
            let result = evaluate(AgentHookMarker.claude(status), attempt: attempt)
            if let result {
                claudeAttempt = nil
                claudeState = result
            }
        }
    }

    private func evaluate(
        _ marker: AgentHookMarker?, attempt: Attempt
    ) -> AgentHookCheckState? {
        let reference = now()
        guard reference.timeIntervalSince(attempt.started) <= Self.maximumWait else {
            return .timedOut
        }
        guard let marker, marker != attempt.baseline else { return nil }
        let age = reference.timeIntervalSince(marker.timestamp)
        // Bridge timestamps have seconds precision; permit rounding down
        // at the arm boundary, but never accept old markers as new.
        guard marker.timestamp.timeIntervalSince(attempt.started) >= -1,
              age >= -5, age <= Self.maximumMarkerAge else { return nil }
        return .observed(marker.timestamp)
    }
}
