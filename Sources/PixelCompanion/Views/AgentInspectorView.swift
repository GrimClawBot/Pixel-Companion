import PixelCompanionCore
import SwiftUI

/// Selection is always re-resolved against the latest live connector snapshot.
/// A disappeared agent or stale feed cannot be presented as a current agent.
enum AgentInspectorSelection {
    static func resolve(
        agentID: String?,
        sessions: [AgentSessionSnapshot],
        isLive: Bool
    ) -> AgentSessionSnapshot? {
        guard isLive, let agentID, !agentID.isEmpty else { return nil }
        return sessions.first { $0.agentID == agentID }
    }
}

/// The assigned-task drilldown is resolved afresh from *current* source
/// evidence. IDs must be unique across the whole bounded task feed.
/// A title, run text or old assignment never authorizes a link.
enum AgentAssignedTaskSelection {
    static func resolve(
        taskID: String?,
        agentID: String,
        tasks: [TaskSnapshot],
        isLive: Bool
    ) -> TaskSnapshot? {
        guard isLive, !agentID.isEmpty, let taskID, !taskID.isEmpty else { return nil }
        let matches = tasks.filter { $0.id == taskID }
        guard matches.count == 1, matches[0].assigneeAgentID == agentID else { return nil }
        return matches[0]
    }
}

/// Read-only, optional field-aware detail for the selected agent.
struct AgentInspectorView: View {
    let session: AgentSessionSnapshot
    var assignedTasks: [TaskSnapshot] = []
    var verifiedTasks: [TaskSnapshot] = []
    var isLive = false
    var peerSessions: [AgentSessionSnapshot] = []
    var onSelectAgent: ((String) -> Void)?
    let back: () -> Void
    @State private var selectedAssignedTaskID: String?

    private var selectedAssignedTask: TaskSnapshot? {
        AgentAssignedTaskSelection.resolve(
            taskID: selectedAssignedTaskID, agentID: session.agentID,
            tasks: verifiedTasks, isLive: isLive
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: back) {
                Label("All agents", systemImage: "chevron.left")
                    .font(.callout.weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
            .accessibilityIdentifier("companion.agent.back")

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: AgentSessionPresentation.symbol(session.runState))
                        .foregroundStyle(AgentSessionPresentation.tint(session.runState))
                    Text(session.agentName)
                        .font(.headline.weight(.semibold))
                        .lineLimit(2)
                    Spacer(minLength: 0)
                    Text(AgentSessionPresentation.stateLabel(session))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AgentSessionPresentation.tint(session.runState))
                }
                if let title = session.agentTitle {
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let role = session.agentRole, !role.isEmpty {
                    Text("Reported role · " + role)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let manager = AgentReportingHierarchy.manager(
                    for: session, in: peerSessions
                ) {
                    Button {
                        onSelectAgent?(manager.agentID)
                    } label: {
                        Label("Reports to " + manager.agentName, systemImage: "arrow.up.right")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
                    .accessibilityIdentifier("companion.agent.reported-manager")
                } else if session.managerAgentID != nil {
                    Text("Reporting manager unavailable or unverified")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let task = session.taskTitle {
                    Text(task)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("No task reported")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .companionCard()

            AgentSessionMonitorView(session: session)

            VStack(alignment: .leading, spacing: 7) {
                Text("Latest reported session")
                    .font(.callout.weight(.semibold))
                field("Model", value: session.model)
                field("Provider", value: session.provider)
                if let identity = AgentSessionPresentation.identityLabel(session) {
                    field("Identifier", value: identity)
                }
                if let startedAt = session.startedAt {
                    timeField("Started", date: startedAt)
                }
                if let finishedAt = session.finishedAt {
                    timeField("Finished", date: finishedAt)
                }
                if let updatedAt = session.updatedAt {
                    timeField("Updated", date: updatedAt)
                }
            }
            .companionCard()

            Text("Reported usage")
                .font(.callout.weight(.semibold))
            AgentUsageCard(session: session, showsContext: false)
            Text("Context & next steps")
                .font(.callout.weight(.semibold))
            ContextHealthSummaryView(
                reportedUsed: session.contextUsedTokens,
                reportedWindow: session.contextWindowTokens,
                evidenceID: session.agentID + ":" + (session.runID ?? "")
            )
            .companionCard()
            SessionHandoffChecklistView(
                session: session, assignedTasks: assignedTasks, isLive: isLive
            )
            .id(SessionHandoffSelectionIdentity(session: session))
            .companionCard()
            if !assignedTasks.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text("Assigned tasks")
                            .font(.callout.weight(.semibold))
                        Spacer()
                        Text("\(assignedTasks.count) reported")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    if let selectedAssignedTask {
                        CompanyTaskEvidenceView(
                            task: selectedAssignedTask, sessions: peerSessions,
                            isLive: isLive, onBack: { selectedAssignedTaskID = nil },
                            onSelectAgent: { onSelectAgent?($0) },
                            backLabel: "Assigned tasks"
                        )
                        .id(selectedAssignedTask.id)
                    } else {
                        ForEach(assignedTasks.prefix(5)) { task in
                            if AgentAssignedTaskSelection.resolve(
                                taskID: task.id, agentID: session.agentID,
                                tasks: verifiedTasks, isLive: isLive
                            ) != nil {
                                Button {
                                    selectedAssignedTaskID = task.id
                                } label: {
                                    ReadOnlyTaskRow(task: task)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(
                                    "Inspect assigned task " + CompanyTaskPresentation.title(task)
                                )
                                .accessibilityIdentifier("companion.agent.assigned-task-select")
                            } else {
                                ReadOnlyTaskRow(task: task)
                            }
                        }
                    }
                }
                .accessibilityIdentifier("companion.agent.assigned-tasks")
            }
            AgentRunHistoryView(
                runs: session.recentRuns, verifiedTasks: verifiedTasks, isLive: isLive
            )
            .id(session.agentID)
            Text("Read-only · Fields not supplied by the runtime remain unavailable")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onChange(of: isLive) { _, live in
            if !live { selectedAssignedTaskID = nil }
        }
        .onChange(of: session.agentID) { _, _ in
            selectedAssignedTaskID = nil
        }
        .onChange(of: verifiedTasks.map { [$0.id, $0.assigneeAgentID ?? ""].joined(separator: "|") }) { _, _ in
            if selectedAssignedTask == nil { selectedAssignedTaskID = nil }
        }
        .accessibilityIdentifier("companion.agent.inspector")
    }

    private func field(_ title: String, value: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .leading)
            Text(value.flatMap { $0.isEmpty ? nil : $0 } ?? "Not reported")
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .font(.caption)
    }

    private func timeField(_ title: String, date: Date) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .leading)
            Text(date, style: .relative)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.caption)
    }
}
