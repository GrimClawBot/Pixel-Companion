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

/// Read-only, optional field-aware detail for the selected agent.
struct AgentInspectorView: View {
    let session: AgentSessionSnapshot
    var assignedTasks: [TaskSnapshot] = []
    let back: () -> Void

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
                    ForEach(assignedTasks.prefix(5)) { task in
                        ReadOnlyTaskRow(task: task)
                    }
                }
                .accessibilityIdentifier("companion.agent.assigned-tasks")
            }
            AgentRunHistoryView(runs: session.recentRuns)
            Text("Read-only · Fields not supplied by the runtime remain unavailable")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
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
