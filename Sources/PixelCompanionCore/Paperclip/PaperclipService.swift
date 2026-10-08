import Foundation

final class URLSessionPaperclipService: PaperclipServiceProtocol {
    private let client: PaperclipHTTPClient
    private let telemetry: PaperclipTelemetryFetcher

    init(session: URLSession = PaperclipNetworkPolicy.makeSession()) {
        let client = PaperclipHTTPClient(session: session)
        self.client = client
        telemetry = PaperclipTelemetryFetcher(client: client)
    }

    func fetch(
        configuration: PaperclipConfiguration,
        completion: @escaping (Result<PaperclipRemoteState, Error>) -> Void,
        sessionCompletion: @escaping (Result<[AgentSessionSnapshot], Error>) -> Void
    ) {
        guard let baseURL = configuration.baseURL else {
            completion(.failure(PaperclipServiceError.invalidConfiguration))
            sessionCompletion(.success([]))
            return
        }

        client.get(baseURL: baseURL, path: "api/health", as: PaperclipHealthResponse.self) { [weak self] result in
            guard let self else { return }
            switch result {
            case let .failure(error):
                completion(.failure(error))
            case let .success(health):
                guard health.status.lowercased() == "ok" else {
                    completion(.failure(PaperclipServiceError.invalidResponse))
                    return
                }
                self.fetchCompanies(
                    baseURL: baseURL,
                    configuration: configuration,
                    completion: completion,
                    sessionCompletion: sessionCompletion
                )
            }
        }
    }

    private func fetchCompanies(
        baseURL: URL,
        configuration: PaperclipConfiguration,
        completion: @escaping (Result<PaperclipRemoteState, Error>) -> Void,
        sessionCompletion: @escaping (Result<[AgentSessionSnapshot], Error>) -> Void
    ) {
        client.get(baseURL: baseURL, path: "api/companies", as: [PaperclipCompanyResponse].self) { [weak self] result in
            guard let self else { return }
            switch result {
            case let .failure(error):
                completion(.failure(error))
            case let .success(responses):
                self.resolveCompany(
                    baseURL: baseURL,
                    responses: responses,
                    configuration: configuration,
                    completion: completion,
                    sessionCompletion: sessionCompletion
                )
            }
        }
    }

    private func resolveCompany(
        baseURL: URL,
        responses: [PaperclipCompanyResponse],
        configuration: PaperclipConfiguration,
        completion: @escaping (Result<PaperclipRemoteState, Error>) -> Void,
        sessionCompletion: @escaping (Result<[AgentSessionSnapshot], Error>) -> Void
    ) {
        let companies = responses.map {
            PaperclipCompany(id: $0.id, name: $0.name, status: $0.status)
        }
        let active = companies.filter { $0.status.lowercased() == "active" }
        let selectedID = configuration.companyID.isEmpty
            ? (active.count == 1 ? active[0].id : nil)
            : configuration.companyID

        guard let selectedID else {
            completion(.success(discoveryState(companies)))
            sessionCompletion(.success([]))
            return
        }
        guard let company = companies.first(where: { $0.id == selectedID }) else {
            completion(.failure(PaperclipServiceError.companyNotFound))
            sessionCompletion(.success([]))
            return
        }

        fetchDashboard(
            context: PaperclipFetchContext(baseURL: baseURL, companies: companies, company: company),
            completion: completion,
            sessionCompletion: sessionCompletion
        )
    }

    private func discoveryState(_ companies: [PaperclipCompany]) -> PaperclipRemoteState {
        PaperclipRemoteState(
            companies: companies,
            companyID: nil,
            companyName: nil,
            activity: [],
            approvals: [],
            usage: nil,
            agentSessions: []
        )
    }

    private func fetchDashboard(
        context: PaperclipFetchContext,
        completion: @escaping (Result<PaperclipRemoteState, Error>) -> Void,
        sessionCompletion: @escaping (Result<[AgentSessionSnapshot], Error>) -> Void
    ) {
        client.get(
            baseURL: context.baseURL,
            path: companyPath(context.company.id, resource: "dashboard"),
            as: PaperclipDashboardResponse.self
        ) { [weak self] result in
            guard let self else { return }
            switch result {
            case let .failure(error):
                completion(.failure(error))
            case let .success(dashboard):
                self.fetchAgents(
                    context: context,
                    dashboard: dashboard,
                    completion: completion,
                    sessionCompletion: sessionCompletion
                )
            }
        }
    }

    private func fetchAgents(
        context: PaperclipFetchContext,
        dashboard: PaperclipDashboardResponse,
        completion: @escaping (Result<PaperclipRemoteState, Error>) -> Void,
        sessionCompletion: @escaping (Result<[AgentSessionSnapshot], Error>) -> Void
    ) {
        client.get(
            baseURL: context.baseURL,
            path: companyPath(context.company.id, resource: "agents"),
            as: [PaperclipAgentResponse].self
        ) { [weak self] result in
            guard let self else { return }
            switch result {
            case let .failure(error):
                completion(.failure(error))
            case let .success(agents):
                self.fetchIssues(
                    context: context,
                    dashboard: dashboard,
                    agents: agents,
                    completion: completion,
                    sessionCompletion: sessionCompletion
                )
            }
        }
    }

    private func fetchIssues(
        context: PaperclipFetchContext,
        dashboard: PaperclipDashboardResponse,
        agents: [PaperclipAgentResponse],
        completion: @escaping (Result<PaperclipRemoteState, Error>) -> Void,
        sessionCompletion: @escaping (Result<[AgentSessionSnapshot], Error>) -> Void
    ) {
        client.get(
            baseURL: context.baseURL,
            path: companyPath(context.company.id, resource: "issues"),
            as: [PaperclipIssueResponse].self
        ) { [weak self] result in
            guard let self else { return }
            switch result {
            case let .failure(error):
                completion(.failure(error))
            case let .success(issues):
                self.fetchApprovals(
                    payload: PaperclipIssuePayload(
                        context: context,
                        dashboard: dashboard,
                        agents: agents,
                        issues: issues
                    ),
                    completion: completion,
                    sessionCompletion: sessionCompletion
                )
            }
        }
    }

    private func fetchApprovals(
        payload: PaperclipIssuePayload,
        completion: @escaping (Result<PaperclipRemoteState, Error>) -> Void,
        sessionCompletion: @escaping (Result<[AgentSessionSnapshot], Error>) -> Void
    ) {
        client.get(
            baseURL: payload.context.baseURL,
            path: companyPath(payload.context.company.id, resource: "approvals"),
            as: [PaperclipApprovalResponse].self
        ) { result in
            switch result {
            case let .failure(error):
                completion(.failure(error))
            case let .success(approvals):
                let fullPayload = PaperclipFetchPayload(
                    context: payload.context,
                    dashboard: payload.dashboard,
                    agents: payload.agents,
                    issues: payload.issues,
                    approvals: approvals
                )
                completion(.success(Self.coreState(fullPayload)))
                self.telemetry.fetch(payload: fullPayload, completion: sessionCompletion)
            }
        }
    }

    private static func coreState(_ payload: PaperclipFetchPayload) -> PaperclipRemoteState {
        let mapped = PaperclipMapper.map(PaperclipMappingInput(
            companies: payload.context.companies,
            company: payload.context.company,
            dashboard: payload.dashboard,
            agents: payload.agents,
            issues: payload.issues,
            approvals: payload.approvals,
            runs: []
        ))
        return PaperclipRemoteState(
            companies: mapped.companies,
            companyID: mapped.companyID,
            companyName: mapped.companyName,
            activity: mapped.activity,
            approvals: mapped.approvals,
            usage: mapped.usage,
            agentSessions: [],
            tasks: mapped.tasks
        )
    }

    private func companyPath(_ companyID: String, resource: String) -> String {
        // An empty path is rejected by PaperclipHTTPClient.request.
        // Never interpolate untrusted IDs before validating their segments.
        PaperclipNetworkPolicy.companyPath(companyID, resource: resource) ?? ""
    }
}
