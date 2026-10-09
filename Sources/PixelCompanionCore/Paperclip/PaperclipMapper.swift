import Foundation

enum PaperclipMapper {
    static func map(_ input: PaperclipMappingInput) -> PaperclipRemoteState {
        PaperclipRemoteState(
            companies: input.companies,
            companyID: input.company.id,
            companyName: input.company.name,
            activity: activity(input),
            approvals: approvals(input.approvals),
            usage: usage(input.dashboard),
            agentSessions: agentSessions(input),
            tasks: tasks(input.issues)
        )
    }

    private static func activity(_ input: PaperclipMappingInput) -> [ActivityEvent] {
        let agentNames = input.agents.reduce(into: [String: String]()) { names, agent in
            names[agent.id] = agent.name
        }
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
            timestamp: timestamp,
            signal: issueSignal(issue.status),
            sourceID: "paperclip", entityID: issue.id
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
            timestamp: date(agent.updatedAt) ?? date(agent.lastHeartbeatAt) ?? .distantPast,
            signal: kind == .failed ? .agentFailure : (status == "running" ? .working : nil),
            sourceID: "paperclip", entityID: agent.id
        )
    }

    private static func tasks(_ issues: [PaperclipIssueResponse]) -> [TaskSnapshot] {
        issues.map { issue in
            TaskSnapshot(
                id: issue.id, identifier: issue.identifier, title: issue.title,
                status: issue.status, assigneeAgentID: issue.assigneeAgentId,
                updatedAt: date(issue.lastActivityAt) ?? date(issue.updatedAt)
                    ?? date(issue.createdAt)
            )
        }
        .sorted { lhs, rhs in
            let left = lhs.updatedAt ?? .distantPast
            let right = rhs.updatedAt ?? .distantPast
            return left == right ? lhs.id < rhs.id : left > right
        }
    }

    private static func agentSessions(_ input: PaperclipMappingInput) -> [AgentSessionSnapshot] {
        let issuesByID = input.issues.reduce(into: [String: PaperclipIssueResponse]()) { values, issue in
            values[issue.id] = issue
        }
        let runsByAgent = Dictionary(grouping: input.runs, by: \.agentId)
        let agentsByID = input.agents.reduce(into: [String: PaperclipAgentResponse]()) { values, agent in
            values[agent.id] = agent
        }

        return agentsByID.values.map { agent in
            session(for: agent, runs: runsByAgent[agent.id] ?? [], issuesByID: issuesByID)
        }
        .sorted { lhs, rhs in
            if lhs.isActive != rhs.isActive { return lhs.isActive }
            let leftDate = lhs.updatedAt ?? .distantPast
            let rightDate = rhs.updatedAt ?? .distantPast
            if leftDate != rightDate { return leftDate > rightDate }
            return lhs.agentName.localizedCaseInsensitiveCompare(rhs.agentName) == .orderedAscending
        }
    }

    private static func session(
        for agent: PaperclipAgentResponse,
        runs: [PaperclipHeartbeatRunResponse],
        issuesByID: [String: PaperclipIssueResponse]
    ) -> AgentSessionSnapshot {
        let runs = runs.sorted { runTimestamp($0) > runTimestamp($1) }
        let selectedRun = preferredRun(from: runs)
        let issue = selectedRun?.contextSnapshot?.issueId.flatMap { issuesByID[$0] }
        let usage = selectedRun?.usageJson
        let taskTitle = issue.map { issue in
            if let identifier = issue.identifier, !identifier.isEmpty {
            return "\(identifier) · \(issue.title)"
            }
            return issue.title
        }
        return AgentSessionSnapshot(
            id: "paperclip-agent-session-\(agent.id)",
            agentID: agent.id,
            agentName: agent.name,
            agentTitle: agent.title,
            agentRole: agent.role,
            agentStatus: agent.status,
            runID: selectedRun?.id,
            runState: runState(selectedRun?.status, agentStatus: agent.status),
            taskTitle: taskTitle,
            model: usage?.model ?? agent.adapterConfig?.model,
            provider: usage?.provider ?? agent.runtimeConfig?.aiConnection?.provider,
            sessionID: usage?.persistedSessionId
            ?? selectedRun?.sessionIdAfter
            ?? selectedRun?.sessionIdBefore,
            inputTokens: nonnegative(usage?.inputTokens),
            cachedInputTokens: nonnegative(usage?.cachedInputTokens),
            outputTokens: nonnegative(usage?.outputTokens),
            monthlySpendCents: nonnegative(agent.spentMonthlyCents),
            monthlyBudgetCents: nonnegative(agent.budgetMonthlyCents),
            contextUsedTokens: nonnegative(usage?.contextUsedTokens),
            contextWindowTokens: positive(usage?.contextWindowTokens),
            recentRuns: recentRuns(runs, issuesByID: issuesByID),
            startedAt: date(selectedRun?.startedAt),
            finishedAt: date(selectedRun?.finishedAt),
            updatedAt: date(selectedRun?.updatedAt)
            ?? date(selectedRun?.createdAt)
            ?? date(agent.updatedAt)
            ?? date(agent.lastHeartbeatAt)
        )
    }

    /// This is a bounded sample, not a complete run audit log. Run IDs are authoritative;
    /// issue titles describe their current state and may have changed since the run.
    private static func recentRuns(
        _ runs: [PaperclipHeartbeatRunResponse],
        issuesByID: [String: PaperclipIssueResponse]
    ) -> [AgentRunSnapshot] {
        var seen = Set<String>()
        let unique = runs.sorted { lhs, rhs in
            let left = runTimestamp(lhs)
            let right = runTimestamp(rhs)
            return left == right ? lhs.id < rhs.id : left > right
        }.filter { seen.insert($0.id).inserted }

        return unique.prefix(5).map { run in
            let issue = run.contextSnapshot?.issueId.flatMap { issuesByID[$0] }
            let task = issue.map { value in
                [value.identifier, value.title].compactMap { $0 }.joined(separator: " · ")
            }
            return AgentRunSnapshot(
                id: run.id,
                state: runState(run.status, agentStatus: ""),
                issueID: run.contextSnapshot?.issueId.flatMap { $0.isEmpty ? nil : $0 },
                taskTitle: task,
                model: run.usageJson?.model,
                provider: run.usageJson?.provider,
                inputTokens: nonnegative(run.usageJson?.inputTokens),
                cachedInputTokens: nonnegative(run.usageJson?.cachedInputTokens),
                outputTokens: nonnegative(run.usageJson?.outputTokens),
                startedAt: date(run.startedAt),
                finishedAt: date(run.finishedAt),
                updatedAt: date(run.updatedAt) ?? date(run.createdAt) ?? date(run.startedAt)
            )
        }
    }

    private static func preferredRun(
        from runs: [PaperclipHeartbeatRunResponse]
    ) -> PaperclipHeartbeatRunResponse? {
        runs.first(where: { isActiveRun($0.status) })
            ?? runs.first(where: { isConfirmedRecentRun($0.status) })
            ?? runs.first
    }

    private static func runTimestamp(_ run: PaperclipHeartbeatRunResponse) -> Date {
        date(run.updatedAt) ?? date(run.createdAt) ?? date(run.startedAt) ?? .distantPast
    }

    private static func nonnegative(_ value: Int?) -> Int? {
        guard let value, value >= 0 else { return nil }
        return value
    }

    private static func positive(_ value: Int?) -> Int? {
        guard let value, value > 0 else { return nil }
        return value
    }

    private static func isActiveRun(_ status: String) -> Bool {
        ["queued", "running"].contains(status.lowercased())
    }

    private static func isConfirmedRecentRun(_ status: String) -> Bool {
        let value = status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return ["completed", "succeeded", "success", "failed", "error", "cancelled", "canceled"].contains(value)
    }

    private static func runState(
        _ runStatus: String?,
        agentStatus: String
    ) -> AgentSessionSnapshot.RunState {
        guard let runStatus else {
            switch agentStatus.lowercased() {
            case "idle", "paused": return .idle
            case "error", "failed": return .failed
            default: return .unknown
            }
        }
        switch runStatus.lowercased() {
        case "queued": return .queued
        case "running": return .running
        case "completed", "succeeded", "success": return .completed
        case "failed", "error": return .failed
        case "cancelled", "canceled": return .cancelled
        default: return .unknown
        }
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
