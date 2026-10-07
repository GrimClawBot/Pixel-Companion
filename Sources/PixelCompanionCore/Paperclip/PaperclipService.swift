import Foundation

final class URLSessionPaperclipService: PaperclipServiceProtocol {
    private struct Context {
        let baseURL: URL
        let companies: [PaperclipCompany]
        let company: PaperclipCompany
    }

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetch(
        configuration: PaperclipConfiguration,
        completion: @escaping (Result<PaperclipRemoteState, Error>) -> Void
    ) {
        guard let baseURL = configuration.baseURL else {
            completion(.failure(PaperclipServiceError.invalidConfiguration))
            return
        }

        get(baseURL: baseURL, path: "api/health", as: PaperclipHealthResponse.self) { [weak self] result in
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
                    completion: completion
                )
            }
        }
    }

    private func fetchCompanies(
        baseURL: URL,
        configuration: PaperclipConfiguration,
        completion: @escaping (Result<PaperclipRemoteState, Error>) -> Void
    ) {
        get(baseURL: baseURL, path: "api/companies", as: [PaperclipCompanyResponse].self) { [weak self] result in
            guard let self else { return }
            switch result {
            case let .failure(error):
                completion(.failure(error))
            case let .success(responses):
                self.resolveCompany(
                    baseURL: baseURL,
                    responses: responses,
                    configuration: configuration,
                    completion: completion
                )
            }
        }
    }

    private func resolveCompany(
        baseURL: URL,
        responses: [PaperclipCompanyResponse],
        configuration: PaperclipConfiguration,
        completion: @escaping (Result<PaperclipRemoteState, Error>) -> Void
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
            return
        }
        guard let company = companies.first(where: { $0.id == selectedID }) else {
            completion(.failure(PaperclipServiceError.companyNotFound))
            return
        }

        fetchDashboard(
            context: Context(baseURL: baseURL, companies: companies, company: company),
            completion: completion
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
        context: Context,
        completion: @escaping (Result<PaperclipRemoteState, Error>) -> Void
    ) {
        get(
            baseURL: context.baseURL,
            path: companyPath(context.company.id, resource: "dashboard"),
            as: PaperclipDashboardResponse.self
        ) { [weak self] result in
            guard let self else { return }
            switch result {
            case let .failure(error):
                completion(.failure(error))
            case let .success(dashboard):
                self.fetchAgents(context: context, dashboard: dashboard, completion: completion)
            }
        }
    }

    private func fetchAgents(
        context: Context,
        dashboard: PaperclipDashboardResponse,
        completion: @escaping (Result<PaperclipRemoteState, Error>) -> Void
    ) {
        get(
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
                    completion: completion
                )
            }
        }
    }

    private func fetchIssues(
        context: Context,
        dashboard: PaperclipDashboardResponse,
        agents: [PaperclipAgentResponse],
        completion: @escaping (Result<PaperclipRemoteState, Error>) -> Void
    ) {
        get(
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
                    context: context,
                    dashboard: dashboard,
                    agents: agents,
                    issues: issues,
                    completion: completion
                )
            }
        }
    }

    private func fetchApprovals(
        context: Context,
        dashboard: PaperclipDashboardResponse,
        agents: [PaperclipAgentResponse],
        issues: [PaperclipIssueResponse],
        completion: @escaping (Result<PaperclipRemoteState, Error>) -> Void
    ) {
        get(
            baseURL: context.baseURL,
            path: companyPath(context.company.id, resource: "approvals"),
            as: [PaperclipApprovalResponse].self
        ) { result in
            switch result {
            case let .failure(error):
                completion(.failure(error))
            case let .success(approvals):
                self.fetchHeartbeatRuns(
                    context: context,
                    dashboard: dashboard,
                    agents: agents,
                    issues: issues,
                    approvals: approvals,
                    completion: completion
                )
            }
        }
    }

    private func fetchHeartbeatRuns(
        context: Context,
        dashboard: PaperclipDashboardResponse,
        agents: [PaperclipAgentResponse],
        issues: [PaperclipIssueResponse],
        approvals: [PaperclipApprovalResponse],
        completion: @escaping (Result<PaperclipRemoteState, Error>) -> Void
    ) {
        get(
            baseURL: context.baseURL,
            path: companyPath(context.company.id, resource: "heartbeat-runs"),
            queryItems: [URLQueryItem(name: "limit", value: "40")],
            as: [PaperclipHeartbeatRunResponse].self
        ) { result in
            switch result {
            case let .failure(error):
                completion(.failure(error))
            case let .success(runs):
                completion(.success(PaperclipMapper.map(PaperclipMappingInput(
                    companies: context.companies,
                    company: context.company,
                    dashboard: dashboard,
                    agents: agents,
                    issues: issues,
                    approvals: approvals,
                    runs: runs
                ))))
            }
        }
    }

    private func companyPath(_ companyID: String, resource: String) -> String {
        "api/companies/\(companyID)/\(resource)"
    }

    private func get<Value: Decodable & Sendable>(
        baseURL: URL,
        path: String,
        queryItems: [URLQueryItem] = [],
        as type: Value.Type,
        completion: @escaping (Result<Value, Error>) -> Void
    ) {
        let pathURL = path.split(separator: "/").reduce(baseURL) { partial, component in
            partial.appendingPathComponent(String(component))
        }
        guard var components = URLComponents(url: pathURL, resolvingAgainstBaseURL: false) else {
            completion(.failure(PaperclipServiceError.invalidConfiguration))
            return
        }
        if !queryItems.isEmpty { components.queryItems = queryItems }
        guard let url = components.url else {
            completion(.failure(PaperclipServiceError.invalidConfiguration))
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 8
        request.cachePolicy = .reloadIgnoringLocalCacheData

        session.dataTask(with: request) { data, response, error in
            completion(Self.decodeResponse(data: data, response: response, error: error, as: type))
        }.resume()
    }

    private static func decodeResponse<Value: Decodable>(
        data: Data?,
        response: URLResponse?,
        error: Error?,
        as type: Value.Type
    ) -> Result<Value, Error> {
        if let error { return .failure(error) }
        guard let http = response as? HTTPURLResponse else {
            return .failure(PaperclipServiceError.invalidResponse)
        }
        guard (200..<300).contains(http.statusCode) else {
            return .failure(PaperclipServiceError.http(http.statusCode))
        }
        guard let data else {
            return .failure(PaperclipServiceError.invalidResponse)
        }
        do {
            return .success(try JSONDecoder().decode(type, from: data))
        } catch {
            return .failure(error)
        }
    }
}
