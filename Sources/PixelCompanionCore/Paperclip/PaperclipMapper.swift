import Foundation

enum PaperclipMapper {
    static func map(_ input: PaperclipMappingInput) -> PaperclipRemoteState {
        PaperclipRemoteState(
            companies: input.companies,
            companyID: input.company.id,
            companyName: input.company.name,
            activity: activity(input),
            approvals: approvals(input.approvals),
            usage: usage(input.dashboard)
        )
    }

    private static func activity(_ input: PaperclipMappingInput) -> [ActivityEvent] {
        let agentNames = Dictionary(uniqueKeysWithValues: input.agents.map { ($0.id, $0.name) })
        var events = input.issues.map { issueEvent($0, agentNames: agentNames) }
        events.append(contentsOf: input.agents.compactMap(agentEvent))
        events.sort { $0.timestamp > $1.timestamp }
        return events
    }

    private static func issueEvent(
        _ issue: PaperclipIssueResponse,
        agentNames: [String: String]
    ) -> ActivityEvent {
        let timestamp = date(issue.lastActivityAt)
            ?? date(issue.updatedAt)
            ?? date(issue.createdAt)
            ?? .distantPast
        let identity = issue.identifier ?? issue.id
        var details = [identity, issue.status.replacingOccurrences(of: "_", with: " ")]
        if let agentID = issue.assigneeAgentId, let name = agentNames[agentID] {
            details.append(name)
        }
        return ActivityEvent(
            id: "paperclip-issue-\(issue.id)",
            kind: issueKind(issue.status),
            title: issue.title,
            detail: details.joined(separator: " · "),
            timestamp: timestamp
        )
    }

    private static func agentEvent(_ agent: PaperclipAgentResponse) -> ActivityEvent? {
        let status = agent.status.lowercased()
        guard status != "idle" else { return nil }
        let kind: ActivityEvent.Kind = ["error", "failed"].contains(status) ? .failed : .running
        return ActivityEvent(
            id: "paperclip-agent-\(agent.id)",
            kind: kind,
            title: "\(agent.name) · \(agent.status)",
            detail: agent.title,
            timestamp: date(agent.updatedAt) ?? date(agent.lastHeartbeatAt) ?? .distantPast
        )
    }

    private static func issueKind(_ rawStatus: String) -> ActivityEvent.Kind {
        let status = rawStatus.lowercased()
        if ["done", "completed", "closed"].contains(status) { return .completed }
        if ["failed", "error", "cancelled"].contains(status) { return .failed }
        if ["in_progress", "running", "started"].contains(status) { return .running }
        return .note
    }

    private static func approvals(_ responses: [PaperclipApprovalResponse]) -> [ApprovalRequest] {
        responses
            .filter { ($0.status ?? "pending").lowercased() == "pending" }
            .map { response in
                ApprovalRequest(
                    id: "paperclip-approval-\(response.id)",
                    title: response.title ?? response.type ?? "Approval required",
                    requestedAt: date(response.requestedAt)
                        ?? date(response.createdAt)
                        ?? .distantPast
                )
            }
            .sorted { $0.requestedAt > $1.requestedAt }
    }

    private static func usage(_ dashboard: PaperclipDashboardResponse) -> UsageSnapshot? {
        let spend = dashboard.costs.monthSpendCents
        let budget = dashboard.costs.monthBudgetCents
        guard spend > 0 || budget > 0 else { return nil }
        return UsageSnapshot(
            used: spend,
            limit: budget > 0 ? budget : nil,
            unit: "cents",
            periodLabel: "This month"
        )
    }

    private static func date(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let parsed = fractional.date(from: raw) { return parsed }
        return ISO8601DateFormatter().date(from: raw)
    }
}
