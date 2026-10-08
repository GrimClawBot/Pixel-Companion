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
                        if let agentID = task.assigneeAgentID,
                           agents.contains(where: { $0.agentID == agentID }) {
                            Button { onSelectAgent(agentID) } label: {
                                ReadOnlyTaskRow(task: task)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Inspect assigned agent for " + task.title)
                        } else {
                            ReadOnlyTaskRow(task: task)
                        }
                    }
                }
            }
            .padding(.top, 8)
        } label: {
            SectionTitle(text: isLive ? "Company tasks · \(tasks.count)" : "Company tasks")
        }
        .accessibilityIdentifier("companion.tasks.company")
    }
}
