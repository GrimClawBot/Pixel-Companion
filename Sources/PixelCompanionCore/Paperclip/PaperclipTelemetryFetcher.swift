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
    private struct Key: Equatable {
        let baseURL: String
        let companyID: String
    }

    private struct Pending {
        let sequence: Int
        let key: Key
        let payload: PaperclipFetchPayload
        let completion: (Result<[AgentSessionSnapshot], Error>) -> Void
    }

    private let client: PaperclipHTTPClient
    private let lock = NSLock()
    private var activeKey: Key?
    private var activeBoundary: Int?
    private var nextSequence = 0
    private var pending: [Pending] = []

    init(client: PaperclipHTTPClient) {
        self.client = client
    }

    func fetch(
        payload: PaperclipFetchPayload,
        completion: @escaping (Result<[AgentSessionSnapshot], Error>) -> Void
    ) {
        let key = Self.key(for: payload.context)
        let shouldStart = lock.withLock {
            nextSequence += 1
            pending.append(Pending(
                sequence: nextSequence,
                key: key,
                payload: payload,
                completion: completion
            ))
            guard activeKey == nil else { return false }
            activeKey = key
            activeBoundary = nextSequence
            return true
        }
        guard shouldStart else { return }
        fetchRecentRuns(context: payload.context, key: key)
    }

    private func fetchRecentRuns(
        context: PaperclipFetchContext,
        key: Key
    ) {
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
            self.fetchLiveRuns(context: context, key: key, recentResult: recentResult)
        }
    }

    private func fetchLiveRuns(
        context: PaperclipFetchContext,
        key: Key,
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
            self?.finish(key: key, recentResult: recentResult, liveResult: liveResult)
        }
    }

    private func finish(
        key: Key,
        recentResult: Result<[PaperclipHeartbeatRunResponse], Error>,
        liveResult: Result<[PaperclipHeartbeatRunResponse], Error>
    ) {
        let waiters = lock.withLock {
            let boundary = activeBoundary ?? 0
            let current = pending.filter { $0.key == key && $0.sequence <= boundary }
            pending.removeAll { $0.key == key && $0.sequence <= boundary }
            if activeKey == key {
                activeKey = nil
                activeBoundary = nil
            }
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
        let next = lock.withLock { () -> Pending? in
            guard activeKey == nil, let first = pending.first else { return nil }
            activeKey = first.key
            activeBoundary = nextSequence
            return first
        }
        if let next {
            fetchRecentRuns(context: next.payload.context, key: next.key)
        }
    }

    private static func key(for context: PaperclipFetchContext) -> Key {
        Key(baseURL: context.baseURL.absoluteString, companyID: context.company.id)
    }

    private static func merge(
        recent: [PaperclipHeartbeatRunResponse],
        live: [PaperclipHeartbeatRunResponse],
        liveEndpointSucceeded: Bool
    ) -> [PaperclipHeartbeatRunResponse] {
        let liveIDs = Set(live.map(\.id))
        let safeRecent: [PaperclipHeartbeatRunResponse]
        if liveEndpointSucceeded {
            safeRecent = recent.map { run in
                if isActiveStatus(run.status), !liveIDs.contains(run.id) {
                    return downgradeUnconfirmedActiveRun(run)
                }
                return run
            }
        } else {
            safeRecent = recent.map(downgradeUnconfirmedActiveRun)
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

    private static func downgradeUnconfirmedActiveRun(
        _ run: PaperclipHeartbeatRunResponse
    ) -> PaperclipHeartbeatRunResponse {
        guard isActiveStatus(run.status) else { return run }
        return PaperclipHeartbeatRunResponse(
            id: run.id,
            agentId: run.agentId,
            status: "unknown",
            startedAt: run.startedAt,
            finishedAt: run.finishedAt,
            createdAt: run.createdAt,
            updatedAt: run.updatedAt,
            usageJson: run.usageJson,
            sessionIdBefore: run.sessionIdBefore,
            sessionIdAfter: run.sessionIdAfter,
            contextSnapshot: run.contextSnapshot
        )
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
