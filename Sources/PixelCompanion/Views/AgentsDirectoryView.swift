import PixelCompanionCore
import SwiftUI

/// Pure, local search over fields Paperclip has already supplied. Never queries the server.
enum AgentsDirectoryFilter {
    static func results(
        _ sessions: [AgentSessionSnapshot],
        query: String,
        scope: AgentUsageScope,
        isLive: Bool
    ) -> [AgentSessionSnapshot] {
        guard isLive else { return [] }
        let scoped = scope.sessions(sessions)
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return scoped }
        return scoped.filter { session in
            [
                session.agentName, session.agentTitle, session.taskTitle,
                session.provider, session.model, session.agentStatus,
                AgentSessionPresentation.stateLabel(session)
            ]
            .compactMap { $0 }
            .contains { $0.localizedStandardContains(term) }
        }
    }

    static func emptyMessage(
        total: Int, scope: AgentUsageScope, query: String, isLive: Bool
    ) -> String {
        if !isLive { return "Live agent information is unavailable until Paperclip reconnects." }
        if total == 0 { return "No agents reported by this connector." }
        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "No agents match your search. Try another name, task or model."
        }
        return scope == .active
            ? "No active agents. Select All to see the full list."
            : "No agents match this filter."
    }
}

/// Agent directory and the existing inspector share the same live snapshot and selection.
struct AgentsDirectoryView: View {
    let sessions: [AgentSessionSnapshot]
    let isLive: Bool
    var tasks: [TaskSnapshot] = []
    @Binding var selectedAgentID: String?
    @State private var query = ""
    @State private var scope: AgentUsageScope = .all

    private var visible: [AgentSessionSnapshot] {
        AgentsDirectoryFilter.results(sessions, query: query, scope: scope, isLive: isLive)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !isLive || sessions.isEmpty {
                Placeholder(text: AgentsDirectoryFilter.emptyMessage(
                    total: sessions.count, scope: scope, query: query, isLive: isLive
                ))
            } else if let selected = AgentInspectorSelection.resolve(
                agentID: selectedAgentID, sessions: sessions, isLive: isLive
            ) {
                AgentInspectorView(
                    session: selected,
                    assignedTasks: CompanyTaskPresentation.assigned(
                        tasks, to: selected.agentID, isLive: isLive
                    )
                ) { selectedAgentID = nil }
            } else {
                directory
            }
        }
        .onChange(of: sessions.map(\.agentID)) { _, currentIDs in
            if let selectedAgentID, !currentIDs.contains(selectedAgentID) {
                self.selectedAgentID = nil
            }
        }
        .onChange(of: isLive) { _, live in
            if !live { selectedAgentID = nil }
        }
    }

    private var directory: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                SectionTitle(text: AgentSessionPresentation.sectionTitle(sessions))
                Spacer(minLength: 0)
                Text("\(visible.count) of \(sessions.count)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("\(visible.count) of \(sessions.count) agents")
            }

            TextField("Search agents, tasks, models…", text: $query)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Search agents")
                .accessibilityIdentifier("companion.agents.search")

            Picker("Agent activity filter", selection: $scope) {
                ForEach(AgentUsageScope.allCases, id: \.self) { choice in
                    Text(choice.label).tag(choice)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.small)
            .accessibilityIdentifier("companion.agents.filter")

            if visible.isEmpty {
                Placeholder(text: AgentsDirectoryFilter.emptyMessage(
                    total: sessions.count, scope: scope, query: query, isLive: isLive
                ))
            } else {
                ForEach(visible) { session in
                    Button {
                        selectedAgentID = session.agentID
                    } label: {
                        AgentSessionRow(session: session)
                            .contentShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Inspect " + session.agentName)
                    .accessibilityIdentifier("companion.agent.select." + session.agentID)
                }
            }
        }
    }
}
