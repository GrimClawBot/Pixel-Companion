import Foundation

/// Non-secret connection metadata for a Paperclip server.
public struct PaperclipConfiguration: Equatable, Sendable {
    public var baseURLString: String
    public var companyID: String

    public init(baseURLString: String = "", companyID: String = "") {
        self.baseURLString = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        self.companyID = companyID.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var baseURL: URL? {
        guard !baseURLString.isEmpty, var components = URLComponents(string: baseURLString) else { return nil }
        guard let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme) else { return nil }
        guard components.host?.isEmpty == false else { return nil }
        guard components.user == nil, components.password == nil, components.query == nil, components.fragment == nil else {
            return nil
        }
        components.path = components.path.replacingOccurrences(of: "/+$", with: "", options: .regularExpression)
        guard let url = components.url else { return nil }
        return url
    }

    public var validationError: String? {
        if baseURLString.isEmpty { return nil }
        return baseURL == nil ? "Enter a valid http:// or https:// Paperclip base URL without credentials, query, or fragment." : nil
    }
}

public struct PaperclipCompany: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let status: String

    public init(id: String, name: String, status: String) {
        self.id = id
        self.name = name
        self.status = status
    }
}

struct PaperclipRemoteState {
    let companies: [PaperclipCompany]
    let companyID: String?
    let companyName: String?
    let activity: [ActivityEvent]
    let approvals: [ApprovalRequest]
    let usage: UsageSnapshot?
}

enum PaperclipServiceError: LocalizedError {
    case invalidConfiguration
    case http(Int)
    case invalidResponse
    case companyNotFound

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration: return "Paperclip connection settings are invalid."
        case let .http(status): return "Paperclip returned HTTP \(status)."
        case .invalidResponse: return "Paperclip returned an unreadable response."
        case .companyNotFound: return "The selected Paperclip company was not found."
        }
    }
}

protocol PaperclipServiceProtocol: AnyObject {
    func fetch(
        configuration: PaperclipConfiguration,
        completion: @escaping (Result<PaperclipRemoteState, Error>) -> Void
    )
}

final class URLSessionPaperclipService: PaperclipServiceProtocol {
    private let session: URLSession
    private let decoder = JSONDecoder()

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

        get(baseURL: baseURL, path: "api/health", as: HealthResponse.self) { [weak self] healthResult in
            guard let self else { return }
            switch healthResult {
            case let .failure(error):
                completion(.failure(error))
            case let .success(health):
                guard health.status.lowercased() == "ok" else {
                    completion(.failure(PaperclipServiceError.invalidResponse))
                    return
                }
                self.get(baseURL: baseURL, path: "api/companies", as: [CompanyResponse].self) { companyResult in
                    switch companyResult {
                    case let .failure(error):
                        completion(.failure(error))
                    case let .success(companyResponses):
                        let companies = companyResponses.map {
                            PaperclipCompany(id: $0.id, name: $0.name, status: $0.status)
                        }
                        let activeCompanies = companies.filter { $0.status.lowercased() == "active" }
                        let selectedID: String?
                        if configuration.companyID.isEmpty {
                            selectedID = activeCompanies.count == 1 ? activeCompanies[0].id : nil
                        } else {
                            selectedID = configuration.companyID
                        }

                        guard let selectedID else {
                            completion(.success(PaperclipRemoteState(
                                companies: companies,
                                companyID: nil,
                                companyName: nil,
                                activity: [],
                                approvals: [],
                                usage: nil
                            )))
                            return
                        }
                        guard let selectedCompany = companies.first(where: { $0.id == selectedID }) else {
                            completion(.failure(PaperclipServiceError.companyNotFound))
                            return
                        }
                        self.fetchCompanyState(
                            baseURL: baseURL,
                            company: selectedCompany,
                            companies: companies,
                            completion: completion
                        )
                    }
                }
            }
        }
    }

    private func fetchCompanyState(
        baseURL: URL,
        company: PaperclipCompany,
        companies: [PaperclipCompany],
        completion: @escaping (Result<PaperclipRemoteState, Error>) -> Void
    ) {
        let prefix = "api/companies/\(company.id)"
        get(baseURL: baseURL, path: "\(prefix)/dashboard", as: DashboardResponse.self) { [weak self] dashboardResult in
            guard let self else { return }
            switch dashboardResult {
            case let .failure(error):
                completion(.failure(error))
            case let .success(dashboard):
                self.get(baseURL: baseURL, path: "\(prefix)/agents", as: [AgentResponse].self) { agentResult in
                    switch agentResult {
                    case let .failure(error):
                        completion(.failure(error))
                    case let .success(agents):
                        self.get(baseURL: baseURL, path: "\(prefix)/issues", as: [IssueResponse].self) { issueResult in
                            switch issueResult {
                            case let .failure(error):
                                completion(.failure(error))
                            case let .success(issues):
                                self.get(
                                    baseURL: baseURL,
                                    path: "\(prefix)/approvals",
                                    as: [ApprovalResponse].self
                                ) { approvalResult in
                                    switch approvalResult {
                                    case let .failure(error):
                                        completion(.failure(error))
                                    case let .success(approvals):
                                        completion(.success(self.map(
                                            companies: companies,
                                            company: company,
                                            dashboard: dashboard,
                                            agents: agents,
                                            issues: issues,
                                            approvals: approvals
                                        )))
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func get<Value: Decodable>(
        baseURL: URL,
        path: String,
        as type: Value.Type,
        completion: @escaping (Result<Value, Error>) -> Void
    ) {
        let url = path.split(separator: "/").reduce(baseURL) { partial, component in
            partial.appendingPathComponent(String(component))
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 8
        request.cachePolicy = .reloadIgnoringLocalCacheData

        session.dataTask(with: request) { [decoder] data, response, error in
            if let error {
                completion(.failure(error))
                return
            }
            guard let http = response as? HTTPURLResponse else {
                completion(.failure(PaperclipServiceError.invalidResponse))
                return
            }
            guard (200..<300).contains(http.statusCode) else {
                completion(.failure(PaperclipServiceError.http(http.statusCode)))
                return
            }
            guard let data else {
                completion(.failure(PaperclipServiceError.invalidResponse))
                return
            }
            do {
                completion(.success(try decoder.decode(type, from: data)))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    private func map(
        companies: [PaperclipCompany],
        company: PaperclipCompany,
        dashboard: DashboardResponse,
        agents: [AgentResponse],
        issues: [IssueResponse],
        approvals: [ApprovalResponse]
    ) -> PaperclipRemoteState {
        let agentNames = Dictionary(uniqueKeysWithValues: agents.map { ($0.id, $0.name) })
        var events = issues.map { issue -> ActivityEvent in
            let status = issue.status.lowercased()
            let kind: ActivityEvent.Kind
            if ["done", "completed", "closed"].contains(status) {
                kind = .completed
            } else if ["failed", "error", "cancelled"].contains(status) {
                kind = .failed
            } else if ["in_progress", "running", "started"].contains(status) {
                kind = .running
            } else {
                kind = .note
            }
            let timestamp = Self.date(issue.lastActivityAt)
                ?? Self.date(issue.updatedAt)
                ?? Self.date(issue.createdAt)
                ?? .distantPast
            let identity = issue.identifier ?? issue.id
            var details = [identity, issue.status.replacingOccurrences(of: "_", with: " ")]
            if let agentID = issue.assigneeAgentId, let name = agentNames[agentID] {
                details.append(name)
            }
            return ActivityEvent(
                id: "paperclip-issue-\(issue.id)",
                kind: kind,
                title: issue.title,
                detail: details.joined(separator: " · "),
                timestamp: timestamp
            )
        }

        for agent in agents where agent.status.lowercased() != "idle" {
            let status = agent.status.lowercased()
            let kind: ActivityEvent.Kind = ["error", "failed"].contains(status) ? .failed : .running
            events.append(ActivityEvent(
                id: "paperclip-agent-\(agent.id)",
                kind: kind,
                title: "\(agent.name) · \(agent.status)",
                detail: agent.title,
                timestamp: Self.date(agent.updatedAt) ?? Self.date(agent.lastHeartbeatAt) ?? .distantPast
            ))
        }
        events.sort { $0.timestamp > $1.timestamp }

        let mappedApprovals = approvals
            .filter { ($0.status ?? "pending").lowercased() == "pending" }
            .map { approval in
                ApprovalRequest(
                    id: "paperclip-approval-\(approval.id)",
                    title: approval.title ?? approval.type ?? "Approval required",
                    requestedAt: Self.date(approval.requestedAt)
                        ?? Self.date(approval.createdAt)
                        ?? .distantPast
                )
            }
            .sorted { $0.requestedAt > $1.requestedAt }

        let usage: UsageSnapshot?
        if dashboard.costs.monthSpendCents > 0 || dashboard.costs.monthBudgetCents > 0 {
            usage = UsageSnapshot(
                used: dashboard.costs.monthSpendCents,
                limit: dashboard.costs.monthBudgetCents > 0 ? dashboard.costs.monthBudgetCents : nil,
                unit: "cents",
                periodLabel: "This month"
            )
        } else {
            usage = nil
        }

        return PaperclipRemoteState(
            companies: companies,
            companyID: company.id,
            companyName: company.name,
            activity: events,
            approvals: mappedApprovals,
            usage: usage
        )
    }

    private static func date(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: raw) { return date }
        return ISO8601DateFormatter().date(from: raw)
    }
}

private struct HealthResponse: Decodable {
    let status: String
}

private struct CompanyResponse: Decodable {
    let id: String
    let name: String
    let status: String
}

private struct DashboardResponse: Decodable {
    struct Costs: Decodable {
        let monthSpendCents: Int
        let monthBudgetCents: Int
    }

    let costs: Costs
}

private struct AgentResponse: Decodable {
    let id: String
    let name: String
    let title: String?
    let status: String
    let lastHeartbeatAt: String?
    let updatedAt: String?
}

private struct IssueResponse: Decodable {
    let id: String
    let identifier: String?
    let title: String
    let status: String
    let assigneeAgentId: String?
    let lastActivityAt: String?
    let updatedAt: String?
    let createdAt: String?
}

private struct ApprovalResponse: Decodable {
    let id: String
    let title: String?
    let type: String?
    let status: String?
    let requestedAt: String?
    let createdAt: String?
}

/// Read-only Paperclip connector. Network requests happen off the UI path and update a synchronized cache.
public final class PaperclipConnector: Connector, AuthProvider, ActivitySource, ApprovalProvider, UsageProvider {
    public let id: ConnectorID = .paperclip
    public let configuration: PaperclipConfiguration

    private struct Cache {
        var connectionState: ConnectionState
        var lastError: String?
        var companyName: String?
        var companyID: String?
        var companies: [PaperclipCompany] = []
        var activity: [ActivityEvent] = []
        var approvals: [ApprovalRequest] = []
        var usage: UsageSnapshot?
        var inFlight = false
    }

    private let lock = NSLock()
    private let service: any PaperclipServiceProtocol
    private var cache: Cache

    /// Called on the main queue after cached state changes.
    public var onChange: (() -> Void)?

    public init(configuration: PaperclipConfiguration) {
        self.configuration = configuration
        self.service = URLSessionPaperclipService()
        self.cache = Cache(
            connectionState: configuration.baseURLString.isEmpty ? .disconnected : .connecting,
            lastError: configuration.validationError
        )
    }

    init(configuration: PaperclipConfiguration, service: any PaperclipServiceProtocol) {
        self.configuration = configuration
        self.service = service
        self.cache = Cache(
            connectionState: configuration.baseURLString.isEmpty ? .disconnected : .connecting,
            lastError: configuration.validationError
        )
    }

    public var displayName: String {
        locked { cache.companyName.map { "Paperclip · \($0)" } ?? "Paperclip" }
    }

    public var connectionState: ConnectionState { locked { cache.connectionState } }
    public var lastError: String? { locked { cache.lastError } }
    public var auth: (any AuthProvider)? { self }
    public var activity: (any ActivitySource)? { self }
    public var approvals: (any ApprovalProvider)? { self }
    public var usage: (any UsageProvider)? { self }
    public var authStatus: AuthStatus { .notRequired }
    public var currentActivity: ActivityEvent? {
        locked { cache.activity.first(where: { $0.kind == .running }) ?? cache.activity.first }
    }

    public var availableCompanies: [PaperclipCompany] { locked { cache.companies } }
    public var resolvedCompanyID: String? { locked { cache.companyID } }

    public func recentActivity(limit: Int) -> [ActivityEvent] {
        locked { Array(cache.activity.prefix(max(limit, 0))) }
    }

    public func pendingApprovals() -> [ApprovalRequest] {
        locked { cache.approvals }
    }

    public func currentUsage() -> UsageSnapshot? {
        locked { cache.usage }
    }

    public func refresh() {
        if configuration.baseURLString.isEmpty {
            update { cache in
                cache.connectionState = .disconnected
                cache.lastError = nil
            }
            return
        }
        if let validationError = configuration.validationError {
            update { cache in
                cache.connectionState = .error
                cache.lastError = validationError
            }
            return
        }

        let shouldStart = locked { () -> Bool in
            guard !cache.inFlight else { return false }
            cache.inFlight = true
            if cache.activity.isEmpty, cache.companies.isEmpty {
                cache.connectionState = .connecting
            }
            return true
        }
        guard shouldStart else { return }

        service.fetch(configuration: configuration) { [weak self] result in
            guard let self else { return }
            self.update { cache in
                cache.inFlight = false
                switch result {
                case let .success(state):
                    cache.connectionState = .connected
                    cache.lastError = nil
                    cache.companyName = state.companyName
                    cache.companyID = state.companyID
                    cache.companies = state.companies
                    cache.activity = state.activity
                    cache.approvals = state.approvals
                    cache.usage = state.usage
                case let .failure(error):
                    cache.connectionState = .error
                    cache.lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                }
            }
        }
    }

    private func locked<Value>(_ body: () -> Value) -> Value {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    private func update(_ mutation: (inout Cache) -> Void) {
        lock.lock()
        mutation(&cache)
        let callback = onChange
        lock.unlock()
        guard let callback else { return }
        DispatchQueue.main.async(execute: callback)
    }
}
