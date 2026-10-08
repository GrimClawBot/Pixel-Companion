import Foundation

/// Explanatory-only, derived from already opt-in monitor statuses. Nothing
/// here opens files, trusts hook authorship, or changes agent permissions.
enum AgentHookDiagnosticStage: Equatable {
    case disabled
    case needsFolder
    case noValidMarker
    case oldMarker
    case markerAvailable
    case waitingForNew
    case newlyChanged
    case timedOut
}

struct AgentHookDiagnostic: Equatable {
    let stage: AgentHookDiagnosticStage
    let summary: String
    let nextStep: String
}

enum AgentHookDiagnosticGuide {
    static func codex(
        status: CodexTurnStatus,
        check: AgentHookCheckState,
        now: Date
    ) -> AgentHookDiagnostic {
        let markerDate: Date?
        switch status {
        case .off:
            return instruction(.disabled,
                "Codex turn-event display is disabled.",
                "Enable the Codex hook display and select its private event folder.")
        case .unconnected:
            return instruction(.needsFolder,
                "No Codex event folder is connected.",
                "Use Guided local agent setup, then connect its read-only display.")
        case .unavailable:
            markerDate = nil
        case let .observed(date):
            markerDate = date
        }
        return interpret(check: check, markerDate: markerDate, now: now, provider: .codex)
    }

    static func claude(
        status: ClaudeHookStatus,
        check: AgentHookCheckState,
        now: Date
    ) -> AgentHookDiagnostic {
        let markerDate: Date?
        switch status {
        case .off:
            return instruction(.disabled,
                "Claude Code hook-event display is disabled.",
                "Enable the Claude Code hook display and select its private event folder.")
        case .unconnected:
            return instruction(.needsFolder,
                "No Claude Code event folder is connected.",
                "Use Guided local agent setup, then connect its read-only display.")
        case .unavailable:
            markerDate = nil
        case let .observed(_, date):
            markerDate = date
        }
        return interpret(check: check, markerDate: markerDate, now: now, provider: .claude)
    }

    private static func interpret(
        check: AgentHookCheckState, markerDate: Date?,
        now: Date, provider: AgentHookCheckSource
    ) -> AgentHookDiagnostic {
        let name = provider.title
        switch check {
        case .waiting:
            return instruction(.waitingForNew,
                "Watching for a new event after the baseline.",
                "Trigger a normal \(name) turn, then select Check now.")
        case .observed:
            return instruction(.newlyChanged,
                "New local event marker observed after Start check.",
                "Local marker change is verified, but provider identity is NOT authenticated.")
        case .timedOut:
            return instruction(.timedOut,
                "No new valid local event within three minutes.",
                "Confirm your external \(name) hook configuration and repeat the check.")
        case .notStarted, .needsSetup:
            break
        }
        guard let markerDate else {
            return instruction(.noValidMarker,
                "No valid status marker in the selected folder.",
                "Configure the external \(name) hook and trigger a normal turn.")
        }
        let age = now.timeIntervalSince(markerDate)
        guard age >= -30, age <= 120 else {
            return instruction(.oldMarker,
                "Only a historical event marker is available.",
                "Press Start check, then trigger a NEW normal \(name) turn.")
        }
        return instruction(.markerAvailable,
            "A recent status marker exists; its origin is unverified.",
            "Press Start check to require a different, newly observed marker.")
    }

    private static func instruction(
        _ stage: AgentHookDiagnosticStage, _ summary: String, _ next: String
    ) -> AgentHookDiagnostic {
        AgentHookDiagnostic(stage: stage, summary: summary, nextStep: next)
    }
}
