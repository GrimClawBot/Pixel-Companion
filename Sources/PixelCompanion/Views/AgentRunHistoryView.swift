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

/// A drilldown must re-resolve every fact from the currently verified feed.
/// Matching titles and a current assignment do not prove historical links.
enum AgentRunInspection {
    static func resolve(
        runID: String?,
        runs: [AgentRunSnapshot],
        isLive: Bool
    ) -> AgentRunSnapshot? {
        guard isLive, let runID, !runID.isEmpty else { return nil }
        let matches = runs.filter { $0.id == runID }
        return matches.count == 1 ? matches[0] : nil
    }

    static func verifiedTask(
        for run: AgentRunSnapshot,
        tasks: [TaskSnapshot],
        isLive: Bool
    ) -> TaskSnapshot? {
        guard isLive, let issueID = run.issueID, !issueID.isEmpty else { return nil }
        let matches = tasks.filter { $0.id == issueID && !$0.id.isEmpty }
        return matches.count == 1 ? matches[0] : nil
    }
}

/// Paperclip only sends a bounded recent sample (40 heartbeats + 50 live runs).
/// The app must not suggest this panel represents all historical runs.
struct AgentRunHistoryView: View {
    let runs: [AgentRunSnapshot]
    var verifiedTasks: [TaskSnapshot] = []
    var isLive = false
    @State private var selectedRunID: String?

    private var selectedRun: AgentRunSnapshot? {
        AgentRunInspection.resolve(runID: selectedRunID, runs: runs, isLive: isLive)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            if let selectedRun {
                Button {
                    selectedRunID = nil
                } label: {
                    Label("Recent runs", systemImage: "chevron.left")
                        .font(.callout.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
                .accessibilityIdentifier("companion.agent.run-back")
                verifiedRunDetail(selectedRun)
            } else {
                historyList
            }
        }
        .onChange(of: isLive) { _, live in
            if !live { selectedRunID = nil }
        }
        .onChange(of: runs.map(\.id)) { _, IDs in
            if let selectedRunID, !IDs.contains(selectedRunID) {
                self.selectedRunID = nil
            }
        }
        .accessibilityIdentifier("companion.agent.run-history")
    }

    private var historyList: some View {
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
                if isLive, !run.id.isEmpty {
                    Button {
                        selectedRunID = run.id
                    } label: {
                        runRow(run)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        "Inspect run " + String(run.id.prefix(12)) + ", " +
                        AgentRunHistoryPresentation.stateLabel(run.state)
                    )
                    .accessibilityIdentifier("companion.agent.inspect-run")
                } else {
                    runRow(run)
                }
            }
            Text("Recent available runs only · Not a complete run history")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
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

    private func verifiedRunDetail(_ run: AgentRunSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Verified recent run · read-only")
                .font(.callout.weight(.semibold))
            LabeledContent("Run ID") {
                Text(run.id)
                    .font(.caption.monospaced())
                    .lineLimit(3)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            LabeledContent("Status", value: AgentRunHistoryPresentation.stateLabel(run.state))
            if let provider = run.provider, !provider.isEmpty {
                LabeledContent("Provider", value: provider)
            }
            if let model = run.model, !model.isEmpty {
                LabeledContent("Model", value: model)
            }
            if let started = run.startedAt {
                LabeledContent("Started") { Text(started, style: .relative) }
            }
            if let finished = run.finishedAt {
                LabeledContent("Finished") { Text(finished, style: .relative) }
            }
            if let updated = run.updatedAt {
                LabeledContent("Updated") { Text(updated, style: .relative) }
            }
            Text(AgentRunHistoryPresentation.tokenLabel(run))
                .font(.caption.monospacedDigit())
            if let task = AgentRunInspection.verifiedTask(
                for: run, tasks: verifiedTasks, isLive: isLive
            ) {
                Text("Verified linked task")
                    .font(.caption.weight(.semibold))
                LabeledContent("Task", value: task.identifier ?? task.id)
                Text(task.title)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                LabeledContent("Task status", value: task.status)
                Text("Linked by backend-reported issue ID · " + task.id)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            } else {
                Text(run.issueID == nil
                     ? "No task ID was reported for this run."
                     : "Linked task not verified in the current bounded task feed.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text("Logs unavailable — no verified redacted run logs were supplied.")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("Recent source evidence only · no backend actions")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .companionCard()
        .accessibilityIdentifier("companion.agent.verified-run-detail")
    }

    private func symbol(_ state: AgentSessionSnapshot.RunState) -> String {
        AgentSessionPresentation.symbol(state)
    }

    private func tint(_ state: AgentSessionSnapshot.RunState) -> Color {
        AgentSessionPresentation.tint(state)
    }
}
