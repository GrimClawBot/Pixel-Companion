import Foundation

struct PaperclipFetchContext {
    let baseURL: URL
    let companies: [PaperclipCompany]
    let company: PaperclipCompany
}

struct PaperclipIssuePayload {
    let context: PaperclipFetchContext
    let dashboard: PaperclipDashboardResponse
    let agents: [PaperclipAgentResponse]
    let issues: [PaperclipIssueResponse]
}

struct PaperclipFetchPayload {
    let context: PaperclipFetchContext
    let dashboard: PaperclipDashboardResponse
    let agents: [PaperclipAgentResponse]
    let issues: [PaperclipIssueResponse]
    let approvals: [PaperclipApprovalResponse]
}

final class PaperclipTelemetryFetcher {
    private struct Pending {
        let payload: PaperclipFetchPayload
        let completion: (Result<[AgentSessionSnapshot], Error>) -> Void
    }

    private let client: PaperclipHTTPClient
    private let lock = NSLock()
    private var inFlight = false
    private var pending: [Pending] = []

    init(client: PaperclipHTTPClient) {
        self.client = client
    }

    func fetch(
        payload: PaperclipFetchPayload,
        completion: @escaping (Result<[AgentSessionSnapshot], Error>) -> Void
    ) {
        let shouldStart = lock.withLock {
            pending.append(Pending(payload: payload, completion: completion))
            guard !inFlight else { return false }
            inFlight = true
            return true
        }
        guard shouldStart else { return }
        fetchRecentRuns(context: payload.context)
    }

    private func fetchRecentRuns(context: PaperclipFetchContext) {
        client.getLossyArray(
            baseURL: context.baseURL,
            path: companyPath(context.company.id, resource: "heartbeat-runs"),
            queryItems: [
                URLQueryItem(name: "limit", value: "40"),
                URLQueryItem(name: "summary", value: "1")
            ],
            as: PaperclipHeartbeatRunResponse.self
        ) { [weak self] recentResult in
            guard let self else { return }
            self.fetchLiveRuns(context: context, recentResult: recentResult)
        }
    }

    private func fetchLiveRuns(
        context: PaperclipFetchContext,
        recentResult: Result<[PaperclipHeartbeatRunResponse], Error>
    ) {
        client.getLossyArray(
            baseURL: context.baseURL,
            path: companyPath(context.company.id, resource: "live-runs"),
            queryItems: [
                URLQueryItem(name: "limit", value: "50"),
                URLQueryItem(name: "minCount", value: "0")
            ],
            as: PaperclipHeartbeatRunResponse.self
        ) { [weak self] liveResult in
            self?.finish(recentResult: recentResult, liveResult: liveResult)
        }
    }

    private func finish(
        recentResult: Result<[PaperclipHeartbeatRunResponse], Error>,
        liveResult: Result<[PaperclipHeartbeatRunResponse], Error>
    ) {
        let waiters = lock.withLock {
            let current = pending
            pending = []
            inFlight = false
            return current
        }

        switch (recentResult, liveResult) {
        case let (.failure(recentError), .failure):
            waiters.forEach { $0.completion(.failure(recentError)) }
        default:
            let recent = (try? recentResult.get()) ?? []
            let live = (try? liveResult.get()) ?? []
            let merged = Self.merge(
                recent: recent,
                live: live,
                liveEndpointSucceeded: liveResult.isSuccess
            )
            waiters.forEach { waiter in
                waiter.completion(.success(Self.sessions(payload: waiter.payload, runs: merged)))
            }
        }

        restartIfNeeded()
    }

    private func restartIfNeeded() {
        let context = lock.withLock { () -> PaperclipFetchContext? in
            guard !inFlight, let first = pending.first else { return nil }
            inFlight = true
            return first.payload.context
        }
        if let context {
            fetchRecentRuns(context: context)
        }
    }

    private static func merge(
        recent: [PaperclipHeartbeatRunResponse],
        live: [PaperclipHeartbeatRunResponse],
        liveEndpointSucceeded: Bool
    ) -> [PaperclipHeartbeatRunResponse] {
        let liveIDs = Set(live.map(\.id))
        let safeRecent = recent.filter { run in
            !isActiveStatus(run.status) || (liveEndpointSucceeded && liveIDs.contains(run.id))
        }
        let merged = (safeRecent + live).reduce(into: [String: PaperclipHeartbeatRunResponse]()) {
            $0[$1.id] = $1
        }
        return Array(merged.values)
    }

    private static func isActiveStatus(_ status: String) -> Bool {
        switch status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "queued", "running": return true
        default: return false
        }
    }

    private static func sessions(
        payload: PaperclipFetchPayload,
        runs: [PaperclipHeartbeatRunResponse]
    ) -> [AgentSessionSnapshot] {
        PaperclipMapper.map(PaperclipMappingInput(
            companies: payload.context.companies,
            company: payload.context.company,
            dashboard: payload.dashboard,
            agents: payload.agents,
            issues: payload.issues,
            approvals: payload.approvals,
            runs: runs
        )).agentSessions
    }

    private func companyPath(_ companyID: String, resource: String) -> String {
        "api/companies/\(companyID)/\(resource)"
    }
}

private extension Result {
    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}
