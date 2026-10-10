import PixelCompanionCore
import SwiftUI

/// Only the run's reported state and timestamps authorize UI status.
enum AgentSessionMonitorPresentation {
    static func phase(_ session: AgentSessionSnapshot) -> String {
        switch session.runState {
        case .queued: return "Queued · waiting to start"
        case .running: return "Running · completion not reported"
        case .completed: return "Completed"
        case .failed: return "Failed"
        case .cancelled: return "Cancelled"
        case .idle: return "No active run"
        case .unknown: return "Run state unconfirmed"
        }
    }

    /// An indeterminate spinner does not imply a percent complete.
    static func showsRunningIndicator(
        _ session: AgentSessionSnapshot, reduceMotion: Bool
    ) -> Bool {
        session.runState == .running && !reduceMotion
    }

    /// Don't mistake agent.updatedAt for a trustworthy run-start or end time.
    static func reportedDuration(_ session: AgentSessionSnapshot) -> TimeInterval? {
        guard [.completed, .failed, .cancelled].contains(session.runState),
              let start = session.startedAt,
              let end = session.finishedAt,
              start <= end else {
            return nil
        }
        return end.timeIntervalSince(start)
    }

    static func durationLabel(_ interval: TimeInterval) -> String {
        let seconds = Int(interval)
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m \(seconds % 60)s" }
        let hours = minutes / 60
        return "\(hours)h \(minutes % 60)m"
    }

    static func contextStatus(_ session: AgentSessionSnapshot) -> String {
        guard let fraction = AgentUsagePresentation.contextFraction(session) else {
            return "Context window not reported"
        }
        let percentage = Int(fraction * 100)
        if percentage >= 90 { return "Context nearly full · \(percentage)%" }
        if percentage >= 80 { return "Context above 80% · \(percentage)%" }
        return "Context reported · \(percentage)% used"
    }
}

/// Reported state, not estimated job completion. All data comes from the current live snapshot.
struct AgentSessionMonitorView: View {
    let session: AgentSessionSnapshot
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                Text("Session monitor")
                    .font(.callout.weight(.semibold))
                Spacer(minLength: 0)
                Image(systemName: AgentSessionPresentation.symbol(session.runState))
                    .foregroundStyle(AgentSessionPresentation.tint(session.runState))
                    .accessibilityHidden(true)
            }
            HStack(spacing: 9) {
                if AgentSessionMonitorPresentation.showsRunningIndicator(
                    session, reduceMotion: reduceMotion
                ) {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Run activity, completion not reported")
                }
                Text(AgentSessionMonitorPresentation.phase(session))
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(AgentSessionPresentation.tint(session.runState))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let started = session.startedAt {
                timestampRow("Reported start", date: started)
            } else {
                Text("Start time not reported")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if let updated = session.updatedAt {
                timestampRow("Last reported update", date: updated)
            }
            if let finished = session.finishedAt {
                timestampRow("Reported finish", date: finished)
            }
            if let seconds = AgentSessionMonitorPresentation.reportedDuration(session) {
                Text("Reported run duration · \(AgentSessionMonitorPresentation.durationLabel(seconds))")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Divider()
            Text(AgentSessionMonitorPresentation.contextStatus(session))
                .font(.caption.weight(.medium))
            Text(AgentUsagePresentation.contextLabel(session))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let fraction = AgentUsagePresentation.contextFraction(session) {
                ProgressView(value: fraction)
                    .progressViewStyle(.linear)
                    .tint(fraction >= 0.9 ? .red : (fraction >= 0.8 ? .orange : .green))
                    .accessibilityLabel("Reported context utilization")
                    .accessibilityValue("\(Int(fraction * 100)) percent")
            }
            if let warning = AgentUsagePresentation.contextWarning(session) {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ContextHealthSummaryView(
                reportedUsed: session.contextUsedTokens,
                reportedWindow: session.contextWindowTokens
            )
            Text("Read-only report · No run-completion percentage available")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .companionCard()
        .accessibilityIdentifier("companion.agent.session-monitor")
    }

    private func timestampRow(_ label: String, date: Date) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Text(date, style: .relative)
                .monospacedDigit()
        }
        .font(.caption2)
    }
}
