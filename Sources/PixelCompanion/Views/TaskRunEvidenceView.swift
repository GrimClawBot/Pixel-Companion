import PixelCompanionCore
import SwiftUI

/// Only backend-supplied run.contextSnapshot.issueId establishes a task/run link.
/// An agent's current assignment or a coincidentally similar title is not proof.
struct TaskRunEvidence: Identifiable {
    let agentID: String
    let agentName: String
    let run: AgentRunSnapshot

    var id: String { agentID + ":" + run.id }
}

enum CompanyTaskRunTrace {
    static func currentAssignee(
        task: TaskSnapshot, sessions: [AgentSessionSnapshot], isLive: Bool
    ) -> AgentSessionSnapshot? {
        guard isLive, let agentID = task.assigneeAgentID, !agentID.isEmpty else { return nil }
        return sessions.first { $0.agentID == agentID }
    }

    static func linkedRuns(
        task: TaskSnapshot, sessions: [AgentSessionSnapshot], isLive: Bool
    ) -> [TaskRunEvidence] {
        guard isLive, !task.id.isEmpty else { return [] }
        var results: [TaskRunEvidence] = []
        var seen = Set<String>()
        for session in sessions where !session.agentID.isEmpty {
            for run in session.recentRuns where run.issueID == task.id && !run.id.isEmpty {
                let identity = session.agentID + ":" + run.id
                guard seen.insert(identity).inserted else { continue }
                results.append(TaskRunEvidence(
                    agentID: session.agentID, agentName: session.agentName, run: run
                ))
            }
        }
        return results.sorted { lhs, rhs in
            let lhsDate = lhs.run.updatedAt ?? lhs.run.finishedAt
                ?? lhs.run.startedAt ?? .distantPast
            let rhsDate = rhs.run.updatedAt ?? rhs.run.finishedAt
                ?? rhs.run.startedAt ?? .distantPast
            return lhsDate == rhsDate ? lhs.id < rhs.id : lhsDate > rhsDate
        }
    }
}

/// All controls are navigation within the current verified snapshot; no backend actions.
struct CompanyTaskEvidenceView: View {
    let task: TaskSnapshot
    let sessions: [AgentSessionSnapshot]
    let isLive: Bool
    let onBack: () -> Void
    let onSelectAgent: (String) -> Void
    var backLabel = "All tasks"

    @State private var selectedRunID: String?

    private var assignee: AgentSessionSnapshot? {
        CompanyTaskRunTrace.currentAssignee(task: task, sessions: sessions, isLive: isLive)
    }

    private var relatedRuns: [TaskRunEvidence] {
        CompanyTaskRunTrace.linkedRuns(task: task, sessions: sessions, isLive: isLive)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            if let selectedRunID,
               let selected = relatedRuns.first(where: { $0.id == selectedRunID }) {
                Button {
                    self.selectedRunID = nil
                } label: {
                    Label("Task details", systemImage: "chevron.left")
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("companion.task.run.back")
                TaskRunEvidenceDetailView(task: task, link: selected)
            } else {
                Button(action: onBack) {
                    Label(backLabel, systemImage: "chevron.left")
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("companion.task.back")
                ReadOnlyTaskRow(task: task)
                Text("Current assignment")
                    .font(.caption.weight(.semibold))
                if let assignee {
                    Button {
                        onSelectAgent(assignee.agentID)
                    } label: {
                        Label("Inspect " + assignee.agentName, systemImage: "person.crop.circle")
                    }
                    .accessibilityIdentifier("companion.task.current-assignee")
                } else {
                    Text(task.assigneeAgentID == nil
                         ? "No assignee reported"
                         : "Assigned agent unavailable in verified telemetry")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("Runs explicitly linked to this task")
                    .font(.caption.weight(.semibold))
                if relatedRuns.isEmpty {
                    Text("No recent run with a matching reported issue ID.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(relatedRuns.prefix(8)) { link in
                        Button {
                            selectedRunID = link.id
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(link.agentName + " · " +
                                     AgentRunHistoryPresentation.stateLabel(link.run.state))
                                    .font(.caption.weight(.medium))
                                Text("Run " + String(link.run.id.prefix(12)))
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .companionCard()
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Inspect linked run by " + link.agentName)
                        .accessibilityIdentifier("companion.task.linked-run")
                    }
                }
                Text("Only a bounded sample of source-linked runs is available. " +
                     "Reported roles are not verified departments.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityIdentifier("companion.task.evidence")
    }
}

private struct TaskRunEvidenceDetailView: View {
    let task: TaskSnapshot
    let link: TaskRunEvidence

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(CompanyTaskPresentation.title(task))
                .font(.callout.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            Text("Run " + link.run.id)
                .font(.caption.monospaced())
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)
            LabeledContent("Status", value: AgentRunHistoryPresentation.stateLabel(link.run.state))
            LabeledContent("Reported agent", value: link.agentName)
            if let provider = link.run.provider {
                LabeledContent("Provider", value: provider)
            }
            if let model = link.run.model {
                LabeledContent("Model", value: model)
            }
            if let started = link.run.startedAt {
                LabeledContent("Started") { Text(started, style: .relative) }
            }
            if let finished = link.run.finishedAt {
                LabeledContent("Finished") { Text(finished, style: .relative) }
            }
            Text(AgentRunHistoryPresentation.tokenLabel(link.run))
                .font(.caption.monospacedDigit())
            Text("Logs unavailable — no verified redacted run logs were supplied.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Read-only · Linked by the run's structured issue ID, not its title.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .companionCard()
        .accessibilityIdentifier("companion.task.run-detail")
    }
}
