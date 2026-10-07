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
    private let client: PaperclipHTTPClient

    init(client: PaperclipHTTPClient) {
        self.client = client
    }

    func fetch(
        payload: PaperclipFetchPayload,
        completion: @escaping (Result<[AgentSessionSnapshot], Error>) -> Void
    ) {
        client.getLossyArray(
            baseURL: payload.context.baseURL,
            path: companyPath(payload.context.company.id, resource: "heartbeat-runs"),
            queryItems: [
                URLQueryItem(name: "limit", value: "40"),
                URLQueryItem(name: "summary", value: "1")
            ],
            as: PaperclipHeartbeatRunResponse.self
        ) { [weak self] recentResult in
            guard let self else { return }
            self.fetchLiveRuns(
                payload: payload,
                recentResult: recentResult,
                completion: completion
            )
        }
    }

    private func fetchLiveRuns(
        payload: PaperclipFetchPayload,
        recentResult: Result<[PaperclipHeartbeatRunResponse], Error>,
        completion: @escaping (Result<[AgentSessionSnapshot], Error>) -> Void
    ) {
        client.getLossyArray(
            baseURL: payload.context.baseURL,
            path: companyPath(payload.context.company.id, resource: "live-runs"),
            queryItems: [
                URLQueryItem(name: "limit", value: "50"),
                URLQueryItem(name: "minCount", value: "0")
            ],
            as: PaperclipHeartbeatRunResponse.self
        ) { liveResult in
            switch (recentResult, liveResult) {
            case let (.failure(recentError), .failure):
                completion(.failure(recentError))
            default:
                let recent = (try? recentResult.get()) ?? []
                let live = (try? liveResult.get()) ?? []
                let merged = Self.merge(recent: recent, live: live)
                completion(.success(Self.sessions(payload: payload, runs: merged)))
            }
        }
    }

    private static func merge(
        recent: [PaperclipHeartbeatRunResponse],
        live: [PaperclipHeartbeatRunResponse]
    ) -> [PaperclipHeartbeatRunResponse] {
        let merged = (recent + live).reduce(into: [String: PaperclipHeartbeatRunResponse]()) {
            $0[$1.id] = $1
        }
        return Array(merged.values)
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
