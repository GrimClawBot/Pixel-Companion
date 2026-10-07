import PixelCompanionCore
import SwiftUI

struct AgentSessionRow: View {
    let session: AgentSessionSnapshot
    var compact = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: AgentSessionPresentation.symbol(session.runState))
                .foregroundStyle(AgentSessionPresentation.tint(session.runState))
                .frame(width: 14)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(session.agentName)
                        .font(.callout.weight(session.isActive ? .semibold : .regular))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(AgentSessionPresentation.stateLabel(session))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(AgentSessionPresentation.tint(session.runState))
                }
                if let taskTitle = session.taskTitle {
                    Text(taskTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(compact ? 1 : 2)
                } else if let title = session.agentTitle {
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let runtime = AgentSessionPresentation.runtimeLabel(session) {
                    Text(runtime)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                if !compact, let identity = AgentSessionPresentation.identityLabel(session) {
                    Text(identity)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                if !compact, let tokens = AgentSessionPresentation.tokenLabel(session) {
                    Text(tokens)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            if let updatedAt = session.updatedAt {
                Text(updatedAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

enum SnapshotPrimaryContent: Equatable {
    case activity(ActivityEvent)
    case session(AgentSessionSnapshot)
}

enum AgentSessionPresentation {
    static func primary(_ sessions: [AgentSessionSnapshot]) -> AgentSessionSnapshot? {
        sessions.first(where: \.isActive) ?? sessions.first
    }

    static func snapshotPrimary(
        activity: ActivityEvent?,
        sessions: [AgentSessionSnapshot]
    ) -> SnapshotPrimaryContent? {
        if let active = sessions.first(where: \.isActive) {
            return .session(active)
        }
        if let activity {
            return .activity(activity)
        }
        if let recent = sessions.first {
            return .session(recent)
        }
        return nil
    }

    static func highlightedActivity(
        activity: ActivityEvent?,
        sessions: [AgentSessionSnapshot]
    ) -> ActivityEvent? {
        guard case let .activity(event) = snapshotPrimary(activity: activity, sessions: sessions) else {
            return nil
        }
        return event
    }

    static func sectionTitle(_ sessions: [AgentSessionSnapshot]) -> String {
        sessions.contains(where: \.isActive) ? "Agent sessions" : "Recent agent sessions"
    }

    static func stateLabel(_ session: AgentSessionSnapshot) -> String {
        switch session.runState {
        case .queued: return "Queued"
        case .running: return "Live"
        case .completed: return "Completed"
        case .failed: return "Failed"
        case .cancelled: return "Cancelled"
        case .idle: return "Idle"
        case .unknown:
            let status = session.agentStatus
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "_", with: " ")
            return status.isEmpty ? "Unknown" : status.capitalized
        }
    }

    static func runtimeLabel(_ session: AgentSessionSnapshot) -> String? {
        [session.provider, session.model]
            .compactMap { value in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
            .joined(separator: " · ")
            .nilIfEmpty
    }

    static func identityLabel(_ session: AgentSessionSnapshot) -> String? {
        if let sessionID = session.sessionID, !sessionID.isEmpty {
            return "Session \(shortID(sessionID))"
        }
        if let runID = session.runID, !runID.isEmpty {
            return "Run \(shortID(runID))"
        }
        return nil
    }

    static func tokenLabel(_ session: AgentSessionSnapshot) -> String? {
        var parts: [String] = []
        if let value = session.inputTokens { parts.append("\(count(value)) in") }
        if let value = session.cachedInputTokens { parts.append("\(count(value)) cached") }
        if let value = session.outputTokens { parts.append("\(count(value)) out") }
        return parts.joined(separator: " · ").nilIfEmpty
    }

    static func symbol(_ state: AgentSessionSnapshot.RunState) -> String {
        switch state {
        case .queued: return "clock"
        case .running: return "bolt.fill"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "xmark.octagon.fill"
        case .cancelled: return "nosign"
        case .idle: return "moon.zzz"
        case .unknown: return "questionmark.circle"
        }
    }

    static func tint(_ state: AgentSessionSnapshot.RunState) -> Color {
        switch state {
        case .queued: return .orange
        case .running: return .green
        case .completed: return .secondary
        case .failed: return .red
        case .cancelled, .idle, .unknown: return .secondary
        }
    }

    private static func shortID(_ value: String) -> String {
        value.count > 12 ? "\(value.prefix(8))…" : value
    }

    private static func count(_ value: Int) -> String {
        let safeValue = max(value, 0)
        if safeValue >= 1_000_000 {
            return String(format: "%.1fM", Double(safeValue) / 1_000_000)
        }
        if safeValue >= 1_000 {
            return String(format: "%.1fK", Double(safeValue) / 1_000)
        }
        return "\(safeValue)"
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
