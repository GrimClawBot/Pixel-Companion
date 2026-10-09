import Foundation

/// Presentation logic only. A scrubbed marker is NOT identity verification
/// and a provider milestone is NOT proof of a successful agent task.
@MainActor
enum LocalAgentEventPresentation {
    static func codexLabel(_ date: Date, now: Date) -> String {
        CodexTurnParser.isRecent(date, at: now)
            ? "Turn completion reported"
            : "Previous turn completion (not live)"
    }

    static func claudeLabel(
        _ event: ClaudeHookEvent, at timestamp: Date, now: Date
    ) -> String {
        event.label + (
            ClaudeHookParser.isRecent(timestamp, at: now)
                ? "" : " (previous event, not live)"
        )
    }

    static func attentionIsVisible(_ timestamp: Date, at now: Date) -> Bool {
        let age = now.timeIntervalSince(timestamp)
        return age >= -30 && age <= LocalAgentActivityTimeline.retentionInterval
    }

    static func attentionTimingLabel(_ timestamp: Date, at now: Date) -> String {
        let age = now.timeIntervalSince(timestamp)
        return age >= -30 && age <= 120
            ? "Recently observed" : "Earlier event, not live"
    }

    static func timelineTimingLabel(_ timestamp: Date, at now: Date) -> String {
        let age = now.timeIntervalSince(timestamp)
        return age >= -30 && age <= 120
            ? "Recently observed" : "Earlier event, not live"
    }
}
