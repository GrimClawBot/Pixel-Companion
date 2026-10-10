import Foundation

/// Health is about the *configured source* and its last report, NOT agent
/// identity, permission, current activity, task success or a verified session.
enum LocalConnectionHealthKind: String, Equatable {
    case off
    case needsSetup
    case detected
    case notDetected
    case empty
    case recent
    case historical
    case unavailable

    var title: String {
        switch self {
        case .off: "Off"
        case .needsSetup: "Needs setup"
        case .detected: "Process detected"
        case .notDetected: "Not detected"
        case .empty: "Empty report"
        case .recent: "Recent report"
        case .historical: "Historical"
        case .unavailable: "Unavailable"
        }
    }

    var symbol: String {
        switch self {
        case .off: "circle"
        case .needsSetup: "link.badge.plus"
        case .detected: "checkmark.circle"
        case .notDetected: "circle.dashed"
        case .empty: "tray"
        case .recent: "clock.badge.checkmark"
        case .historical: "clock"
        case .unavailable: "exclamationmark.circle"
        }
    }
}

struct LocalConnectionHealthItem: Equatable, Identifiable {
    let id: String
    let title: String
    let kind: LocalConnectionHealthKind
    let detail: String

    var accessibilitySummary: String { title + ". " + kind.title + ". " + detail }
}

enum LocalConnectionHealth {
    static func codexProcess(_ status: CodexProcessPresence) -> LocalConnectionHealthItem {
        let kind: LocalConnectionHealthKind
        let explanation: String
        switch status {
        case .off:
            kind = .off
            explanation = "Enable process detection in Connections."
        case .unavailable:
            kind = .unavailable
            explanation = "macOS process names could not be read."
        case .absent:
            kind = .notDetected
            explanation = "No matching current-user process name was found."
        case .detected:
            kind = .detected
            explanation = "Process name only; session activity and identity are not verified."
        }
        return LocalConnectionHealthItem(
            id: "codex-process", title: "Codex process", kind: kind, detail: explanation
        )
    }

    static func codexTurn(_ status: CodexTurnStatus, now: Date) -> LocalConnectionHealthItem {
        let kind: LocalConnectionHealthKind
        let explanation: String
        switch status {
        case .off:
            kind = .off
            explanation = "Turn events are disabled."
        case .unconnected:
            kind = .needsSetup
            explanation = "Choose the privacy-scrubbed event folder."
        case .unavailable:
            kind = .unavailable
            explanation = "Marker missing, unreadable or invalid; no event verified."
        case let .observed(date):
            let isFresh = CodexTurnParser.isRecent(date, at: now)
            kind = isFresh ? .recent : .historical
            explanation = isFresh
                ? "A turn end was reported; task outcome unknown."
                : "Previous turn end only; not evidence of current activity."
        }
        return LocalConnectionHealthItem(
            id: "codex-turns", title: "Codex turn events", kind: kind, detail: explanation
        )
    }

    static func claudeHook(_ status: ClaudeHookStatus, now: Date) -> LocalConnectionHealthItem {
        let kind: LocalConnectionHealthKind
        let explanation: String
        switch status {
        case .off:
            kind = .off
            explanation = "Claude Code lifecycle events are disabled."
        case .unconnected:
            kind = .needsSetup
            explanation = "Choose the privacy-scrubbed hook event folder."
        case .unavailable:
            kind = .unavailable
            explanation = "Marker missing, unreadable or invalid; no event verified."
        case let .observed(event, timestamp):
            let fresh = ClaudeHookParser.isRecent(timestamp, at: now)
            kind = fresh ? .recent : .historical
            explanation = fresh
                ? event.label + "; task activity not verified."
                : event.label + " was reported previously; not a live signal."
        }
        return LocalConnectionHealthItem(
            id: "claude-events", title: "Claude Code hooks", kind: kind, detail: explanation
        )
    }

    static func localFeed(_ status: LocalAgentFeedStatus, now: Date) -> LocalConnectionHealthItem {
        let kind: LocalConnectionHealthKind
        let explanation: String
        switch status {
        case .disabled:
            kind = .off
            explanation = "Local agent status is disabled."
        case .unconnected:
            kind = .needsSetup
            explanation = "Choose a status JSON file supplied by a trusted local agent."
        case .unavailable:
            kind = .unavailable
            explanation = "Selected status file is missing, unreadable or invalid."
        case .empty:
            kind = .empty
            explanation = "A valid status report contains no sessions."
        case let .loaded(sessions):
            let fresh = sessions.filter { $0.isFresh(at: now) }.count
            kind = fresh > 0 ? .recent : .historical
            explanation = fresh > 0
                ? "\(fresh) of \(sessions.count) sessions reported fresh; source not independently verified."
                : "All reported sessions are stale; no live status verified."
        }
        return LocalConnectionHealthItem(
            id: "local-feed", title: "Local agent status feed", kind: kind, detail: explanation
        )
    }

    static func snapshot(
        process: CodexProcessPresence,
        codex: CodexTurnStatus,
        claude: ClaudeHookStatus,
        feed: LocalAgentFeedStatus,
        now: Date
    ) -> [LocalConnectionHealthItem] {
        [
            codexProcess(process),
            codexTurn(codex, now: now),
            claudeHook(claude, now: now),
            localFeed(feed, now: now)
        ]
    }
}
