import PixelCompanionCore
import SwiftUI

enum AgentRunHistoryPresentation {
    static func stateLabel(_ state: AgentSessionSnapshot.RunState) -> String {
        switch state {
        case .queued: return "Queued"
        case .running: return "Running"
        case .completed: return "Completed"
        case .failed: return "Failed"
        case .cancelled: return "Cancelled"
        case .idle: return "Idle"
        case .unknown: return "Unconfirmed"
        }
    }

    static func tokenLabel(_ run: AgentRunSnapshot) -> String {
        var parts: [String] = []
        if let value = run.inputTokens { parts.append("\(value.formatted()) in") }
        if let value = run.cachedInputTokens { parts.append("\(value.formatted()) cached") }
        if let value = run.outputTokens { parts.append("\(value.formatted()) out") }
        return parts.isEmpty ? "Run tokens not reported" : parts.joined(separator: " · ")
    }
}

/// Paperclip only sends a bounded recent sample (40 heartbeats + 50 live runs).
/// The app must not suggest this panel represents all historical runs.
struct AgentRunHistoryView: View {
    let runs: [AgentRunSnapshot]

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("Recent runs")
                    .font(.callout.weight(.semibold))
                Spacer()
                Text("\(runs.count) shown")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if runs.isEmpty {
                Text("No recent run history reported")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(runs) { run in
                runRow(run)
            }
            Text("Recent available runs only · Not a complete run history")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityIdentifier("companion.agent.run-history")
    }

    private func runRow(_ run: AgentRunSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: symbol(run.state))
                    .foregroundStyle(tint(run.state))
                    .accessibilityHidden(true)
                Text(AgentRunHistoryPresentation.stateLabel(run.state))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint(run.state))
                Spacer(minLength: 4)
                if let updatedAt = run.updatedAt {
                    Text(updatedAt, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Time not reported")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            if let task = run.taskTitle, !task.isEmpty {
                Text(task)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Run \(String(run.id.prefix(8)))")
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
            if run.model != nil || run.provider != nil {
                Text([run.provider, run.model].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(AgentRunHistoryPresentation.tokenLabel(run))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .companionCard()
        .accessibilityElement(children: .combine)
    }

    private func symbol(_ state: AgentSessionSnapshot.RunState) -> String {
        AgentSessionPresentation.symbol(state)
    }

    private func tint(_ state: AgentSessionSnapshot.RunState) -> Color {
        AgentSessionPresentation.tint(state)
    }
}
