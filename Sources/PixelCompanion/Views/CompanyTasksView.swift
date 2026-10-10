import PixelCompanionCore
import SwiftUI

/// Task search and attribution use structured task fields, never activity string parsing.
enum CompanyTaskPresentation {
    static func filtered(_ tasks: [TaskSnapshot], query: String) -> [TaskSnapshot] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return tasks }
        return tasks.filter { task in
            [task.identifier, task.title, task.status]
                .compactMap { $0 }
                .contains { $0.localizedStandardContains(term) }
        }
    }

    static func assigned(
        _ tasks: [TaskSnapshot], to agentID: String, isLive: Bool
    ) -> [TaskSnapshot] {
        guard isLive, !agentID.isEmpty else { return [] }
        return tasks.filter { $0.assigneeAgentID == agentID }
    }

    static func status(_ task: TaskSnapshot) -> String {
        task.status.replacingOccurrences(of: "_", with: " ").capitalized
    }

    static func title(_ task: TaskSnapshot) -> String {
        guard let identifier = task.identifier, !identifier.isEmpty else { return task.title }
        return identifier + " · " + task.title
    }
}

struct ReadOnlyTaskRow: View {
    let task: TaskSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(CompanyTaskPresentation.title(task))
                .font(.callout.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                Text(CompanyTaskPresentation.status(task))
                if let date = task.updatedAt {
                    Text("·")
                    Text(date, style: .relative)
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .companionCard()
        .accessibilityElement(children: .combine)
    }
}

/// Bounded company issue preview. Verified assigned tasks may open agent inspector.
struct CompanyTasksView: View {
    let tasks: [TaskSnapshot]
    let agents: [AgentSessionSnapshot]
    let isLive: Bool
    let onSelectAgent: (String) -> Void
    @State private var query = ""
    @State private var expanded = false
    @State private var selectedTaskID: String?

    private var selectedTask: TaskSnapshot? {
        guard isLive, let selectedTaskID else { return nil }
        return tasks.first { $0.id == selectedTaskID }
    }

    private var filtered: [TaskSnapshot] {
        CompanyTaskPresentation.filtered(tasks, query: query)
    }

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 8) {
                if !isLive {
                    Placeholder(text: "Tasks unavailable until the feed is fresh.")
                } else if tasks.isEmpty {
                    Placeholder(text: "No tasks reported by this connector.")
                } else if let selectedTask {
                    CompanyTaskEvidenceView(
                        task: selectedTask, sessions: agents, isLive: isLive,
                        onBack: { selectedTaskID = nil }, onSelectAgent: onSelectAgent
                    )
                    .id(selectedTask.id)
                } else {
                    TextField("Search tasks…", text: $query)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Search tasks")
                        .accessibilityIdentifier("companion.tasks.search")
                    Text("\(filtered.count) matching tasks · showing up to 12")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if filtered.isEmpty {
                        Placeholder(text: "No tasks match your search.")
                    }
                    ForEach(filtered.prefix(12)) { task in
                        HStack(alignment: .top, spacing: 6) {
                            Button { selectedTaskID = task.id } label: {
                                ReadOnlyTaskRow(task: task)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Inspect task " + task.title)
                            .accessibilityIdentifier("companion.task.select")
                            // Preserve the existing direct navigation to an assigned agent.
                            if let agentID = task.assigneeAgentID,
                               agents.contains(where: { $0.agentID == agentID }) {
                                Button { onSelectAgent(agentID) } label: {
                                    Image(systemName: "person.crop.circle")
                                        .font(.title3)
                                        .frame(minWidth: 28, minHeight: 44)
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Inspect assigned agent for " + task.title)
                                .accessibilityIdentifier("companion.task.agent-shortcut")
                            }
                        }
                    }
                }
            }
            .padding(.top, 8)
        } label: {
            SectionTitle(text: isLive ? "Company tasks · \(tasks.count)" : "Company tasks")
        }
        .accessibilityIdentifier("companion.tasks.company")
        .onChange(of: isLive) { _, live in
            if !live { selectedTaskID = nil }
        }
        .onChange(of: tasks.map(\.id)) { _, currentIDs in
            if let selectedTaskID, !currentIDs.contains(selectedTaskID) {
                self.selectedTaskID = nil
            }
        }
    }
}
