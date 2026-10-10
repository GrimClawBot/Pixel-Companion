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

enum AgentDirectoryLayout: String, CaseIterable {
    case list
    case byRole
    case reporting
}

/// Agent directory and the existing inspector share the same live snapshot and selection.
struct AgentsDirectoryView: View {
    let sessions: [AgentSessionSnapshot]
    let isLive: Bool
    var tasks: [TaskSnapshot] = []
    @Binding var selectedAgentID: String?
    @State private var query = ""
    @State private var scope: AgentUsageScope = .all
    @State private var layout: AgentDirectoryLayout = .list
    @State private var collapsedManagerIDs: Set<String> = []

    private var reportingRows: [AgentReportingRow] {
        AgentReportingHierarchy.rows(visible)
    }

    private var reportingManagerIDs: Set<String> {
        Set(reportingRows.filter { $0.directReportCount > 0 }.map(\.id))
    }

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
                    ),
                    verifiedTasks: isLive ? tasks : [],
                    isLive: isLive,
                    peerSessions: sessions,
                    onSelectAgent: { selectedAgentID = $0 },
                    back: { selectedAgentID = nil }
                )
                .id(selected.agentID)
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
            if !live {
                selectedAgentID = nil
                collapsedManagerIDs = []
            }
        }
        // A changed source/manager or search scope should not inherit a prior
        // disclosure decision from another reporting-tree arrangement.
        .onChange(of: visible.map { [$0.agentID, $0.managerAgentID ?? ""].joined(separator: "|") }) { _, _ in
            collapsedManagerIDs = []
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

            Picker("Agent layout", selection: $layout) {
                Text("List").tag(AgentDirectoryLayout.list)
                Text("By role").tag(AgentDirectoryLayout.byRole)
                Text("Reporting").tag(AgentDirectoryLayout.reporting)
            }
            .pickerStyle(.segmented)
            .controlSize(.small)
            .accessibilityIdentifier("companion.agents.group-layout")

            if visible.isEmpty {
                Placeholder(text: AgentsDirectoryFilter.emptyMessage(
                    total: sessions.count, scope: scope, query: query, isLive: isLive
                ))
            } else if layout == .reporting {
                HStack(spacing: 8) {
                    Text("Verified reporting lines")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    if !reportingManagerIDs.isEmpty {
                        Button(collapsedManagerIDs.isEmpty ? "Collapse all" : "Expand all") {
                            if collapsedManagerIDs.isEmpty {
                                collapsedManagerIDs = reportingManagerIDs
                            } else {
                                collapsedManagerIDs = []
                            }
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                        .accessibilityIdentifier("companion.agent.reporting.all")
                    }
                }
                ForEach(AgentReportingHierarchy.visibleRows(
                    reportingRows, collapsedManagerIDs: collapsedManagerIDs
                )) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        if let manager = entry.managerName {
                            Label("Reports to " + manager, systemImage: "arrow.turn.down.right")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        if let note = entry.note {
                            Text(note)
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                        HStack(spacing: 6) {
                            selectableAgentRow(entry.session)
                            if entry.directReportCount > 0 {
                                Button {
                                    if collapsedManagerIDs.contains(entry.id) {
                                        collapsedManagerIDs.remove(entry.id)
                                    } else {
                                        collapsedManagerIDs.insert(entry.id)
                                    }
                                } label: {
                                    Image(systemName: collapsedManagerIDs.contains(entry.id)
                                          ? "chevron.right" : "chevron.down")
                                        .font(.callout.weight(.medium))
                                        .frame(minWidth: 32, minHeight: 40)
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel(
                                    (collapsedManagerIDs.contains(entry.id) ? "Expand" : "Collapse") +
                                    " reports of " + entry.session.agentName
                                )
                                .accessibilityValue("\(entry.directReportCount) direct reports")
                                .accessibilityIdentifier("companion.agent.reporting.toggle")
                            }
                        }
                    }
                    .padding(.leading, CGFloat(min(entry.depth, 4)) * 10)
                    .accessibilityIdentifier("companion.agent.reporting-row")
                }
            } else if layout == .byRole {
                ForEach(AgentRoleGrouping.groups(visible)) { group in
                    HStack {
                        SectionTitle(text: group.label)
                        Spacer(minLength: 0)
                        Text("\(group.sessions.count)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    ForEach(group.sessions) { session in
                        selectableAgentRow(session)
                    }
                }
            } else {
                ForEach(visible) { session in
                    selectableAgentRow(session)
                }
            }
        }
    }

    private func selectableAgentRow(_ session: AgentSessionSnapshot) -> some View {
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
