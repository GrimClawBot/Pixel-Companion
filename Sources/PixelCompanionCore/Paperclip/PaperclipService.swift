import Foundation

private struct PaperclipFetchContext {
    let baseURL: URL
    let companies: [PaperclipCompany]
    let company: PaperclipCompany
}

private struct PaperclipFetchPayload {
    let context: PaperclipFetchContext
    let dashboard: PaperclipDashboardResponse
    let agents: [PaperclipAgentResponse]
    let issues: [PaperclipIssueResponse]
    let approvals: [PaperclipApprovalResponse]
}

final class URLSessionPaperclipService: PaperclipServiceProtocol {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
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
                    completion: completion,
                    sessionCompletion: sessionCompletion
                )
            }
        }
    }

    private func fetchApprovals(
        context: PaperclipFetchContext,
        dashboard: PaperclipDashboardResponse,
        agents: [PaperclipAgentResponse],
        issues: [PaperclipIssueResponse],
        completion: @escaping (Result<PaperclipRemoteState, Error>) -> Void,
        sessionCompletion: @escaping (Result<[AgentSessionSnapshot], Error>) -> Void
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
                let payload = PaperclipFetchPayload(
                    context: context,
                    dashboard: dashboard,
                    agents: agents,
                    issues: issues,
                    approvals: approvals
                )
                completion(.success(PaperclipMapper.map(PaperclipMappingInput(
                    companies: context.companies,
                    company: context.company,
                    dashboard: dashboard,
                    agents: agents,
                    issues: issues,
                    approvals: approvals,
                    runs: []
                ))))
                self.fetchHeartbeatRuns(payload: payload, completion: sessionCompletion)
            }
        }
    }

    private func companyPath(_ companyID: String, resource: String) -> String {
        "api/companies/\(companyID)/\(resource)"
    }

    private func request(
        baseURL: URL,
        path: String,
        queryItems: [URLQueryItem]
    ) -> Result<URLRequest, Error> {
        let pathURL = path.split(separator: "/").reduce(baseURL) { partial, component in
            partial.appendingPathComponent(String(component))
        }
        guard var components = URLComponents(url: pathURL, resolvingAgainstBaseURL: false) else {
            return .failure(PaperclipServiceError.invalidConfiguration)
        }
        if !queryItems.isEmpty { components.queryItems = queryItems }
        guard let url = components.url else {
            return .failure(PaperclipServiceError.invalidConfiguration)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 8
        request.cachePolicy = .reloadIgnoringLocalCacheData
        return .success(request)
    }

    private func get<Value: Decodable & Sendable>(
        baseURL: URL,
        path: String,
        queryItems: [URLQueryItem] = [],
        as type: Value.Type,
        completion: @escaping (Result<Value, Error>) -> Void
    ) {
        switch request(baseURL: baseURL, path: path, queryItems: queryItems) {
        case let .failure(error):
            completion(.failure(error))
        case let .success(request):
            session.dataTask(with: request) { data, response, error in
                completion(Self.decodeResponse(data: data, response: response, error: error, as: type))
            }.resume()
        }
    }

    private func getLossyArray<Value: Decodable & Sendable>(
        baseURL: URL,
        path: String,
        queryItems: [URLQueryItem] = [],
        as type: Value.Type,
        completion: @escaping (Result<[Value], Error>) -> Void
    ) {
        switch request(baseURL: baseURL, path: path, queryItems: queryItems) {
        case let .failure(error):
            completion(.failure(error))
        case let .success(request):
            session.dataTask(with: request) { data, response, error in
                completion(Self.decodeLossyArrayResponse(data: data, response: response, error: error, as: type))
            }.resume()
        }
    }

    private static func decodeResponse<Value: Decodable>(
        data: Data?,
        response: URLResponse?,
        error: Error?,
        as type: Value.Type
    ) -> Result<Value, Error> {
        guard let data = validatedData(data: data, response: response, error: error) else {
            return validationFailure(data: data, response: response, error: error)
        }
        do {
            return .success(try JSONDecoder().decode(type, from: data))
        } catch {
            return .failure(error)
        }
    }

    private static func decodeLossyArrayResponse<Value: Decodable>(
        data: Data?,
        response: URLResponse?,
        error: Error?,
        as type: Value.Type
    ) -> Result<[Value], Error> {
        guard let data = validatedData(data: data, response: response, error: error) else {
            return validationFailure(data: data, response: response, error: error)
        }
        do {
            guard let raw = try JSONSerialization.jsonObject(with: data) as? [Any] else {
                return .failure(PaperclipServiceError.invalidResponse)
            }
            let decoder = JSONDecoder()
            let values = raw.compactMap { item -> Value? in
                guard JSONSerialization.isValidJSONObject(item),
                      let itemData = try? JSONSerialization.data(withJSONObject: item)
                else { return nil }
                return try? decoder.decode(type, from: itemData)
            }
            return .success(values)
        } catch {
            return .failure(error)
        }
    }

    private static func validatedData(
        data: Data?,
        response: URLResponse?,
        error: Error?
    ) -> Data? {
        guard error == nil,
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let data
        else { return nil }
        return data
    }

    private static func validationFailure<Value>(
        data: Data?,
        response: URLResponse?,
        error: Error?
    ) -> Result<Value, Error> {
        if let error { return .failure(error) }
        guard let http = response as? HTTPURLResponse else {
            return .failure(PaperclipServiceError.invalidResponse)
        }
        guard (200..<300).contains(http.statusCode) else {
            return .failure(PaperclipServiceError.http(http.statusCode))
        }
        guard data != nil else {
            return .failure(PaperclipServiceError.invalidResponse)
        }
        return .failure(PaperclipServiceError.invalidResponse)
    }
}

private extension URLSessionPaperclipService {
    func fetchHeartbeatRuns(
        payload: PaperclipFetchPayload,
        completion: @escaping (Result<[AgentSessionSnapshot], Error>) -> Void
    ) {
        getLossyArray(
            baseURL: payload.context.baseURL,
            path: companyPath(payload.context.company.id, resource: "heartbeat-runs"),
            queryItems: [
                URLQueryItem(name: "limit", value: "40"),
                URLQueryItem(name: "summary", value: "1")
            ],
            as: PaperclipHeartbeatRunResponse.self
        ) { [weak self] recentResult in
            guard let self else { return }
            self.getLossyArray(
                baseURL: payload.context.baseURL,
                path: companyPath(payload.context.company.id, resource: "live-runs"),
                queryItems: [
                    URLQueryItem(name: "limit", value: "50"),
                    URLQueryItem(name: "minCount", value: "0")
                ],
                as: PaperclipHeartbeatRunResponse.self
            ) { liveResult in
                let recent = (try? recentResult.get()) ?? []
                let live = (try? liveResult.get()) ?? []
                guard !recent.isEmpty || !live.isEmpty || recentResult.isSuccess || liveResult.isSuccess else {
                    completion(.failure(PaperclipServiceError.invalidResponse))
                    return
                }
                let merged = (recent + live).reduce(into: [String: PaperclipHeartbeatRunResponse]()) {
                    $0[$1.id] = $1
                }
                let state = PaperclipMapper.map(PaperclipMappingInput(
                    companies: payload.context.companies,
                    company: payload.context.company,
                    dashboard: payload.dashboard,
                    agents: payload.agents,
                    issues: payload.issues,
                    approvals: payload.approvals,
                    runs: Array(merged.values)
                ))
                completion(.success(state.agentSessions))
            }
        }
    }
}

private extension Result {
    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}
