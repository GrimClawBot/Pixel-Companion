import Foundation

/// Read-only Paperclip connector. Network requests update a synchronized cache off the UI path.
public final class PaperclipConnector:
    Connector,
    AuthProvider,
    ActivitySource,
    ApprovalProvider,
    UsageProvider,
    AgentSessionSource {
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
        var agentSessions: [AgentSessionSnapshot] = []
        var inFlight = false
    }

    private let lock = NSLock()
    private let service: any PaperclipServiceProtocol
    private var cache: Cache
    private var refreshGeneration = 0
    private var publishedCoreGeneration = 0

    /// Called on the main queue after cached state changes.
    public var onChange: (() -> Void)?

    public init(configuration: PaperclipConfiguration) {
        self.configuration = configuration
        service = URLSessionPaperclipService()
        cache = Self.initialCache(configuration)
    }

    init(configuration: PaperclipConfiguration, service: any PaperclipServiceProtocol) {
        self.configuration = configuration
        self.service = service
        cache = Self.initialCache(configuration)
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
    public var sessions: (any AgentSessionSource)? { self }
    public var authStatus: AuthStatus { .notRequired }

    public var currentActivity: ActivityEvent? {
        locked { cache.activity.first }
    }

    public var availableCompanies: [PaperclipCompany] {
        locked { cache.companies }
    }

    public var resolvedCompanyID: String? {
        locked { cache.companyID }
    }

    public func recentActivity(limit: Int) -> [ActivityEvent] {
        locked { Array(cache.activity.prefix(max(limit, 0))) }
    }

    public func pendingApprovals() -> [ApprovalRequest] {
        locked { cache.approvals }
    }

    public func currentUsage() -> UsageSnapshot? {
        locked { cache.usage }
    }

    public func agentSessions(limit: Int) -> [AgentSessionSnapshot] {
        locked { Array(cache.agentSessions.prefix(max(limit, 0))) }
    }

    public func refresh() {
        guard let generation = beginRefresh() else { return }
        service.fetch(
            configuration: configuration,
            completion: { [weak self] result in
                self?.finishRefresh(result, generation: generation)
            },
            sessionCompletion: { [weak self] result in
                self?.finishSessionRefresh(result, generation: generation)
            }
        )
    }

    private func beginRefresh() -> Int? {
        if configuration.baseURLString.isEmpty {
            update { value in
                value.connectionState = .disconnected
                value.lastError = nil
            }
            return nil
        }
        if let validationError = configuration.validationError {
            update { value in
                value.connectionState = .error
                value.lastError = validationError
            }
            return nil
        }
        return locked {
            guard !cache.inFlight else { return nil }
            cache.inFlight = true
            refreshGeneration += 1
            let generation = refreshGeneration
            if cache.activity.isEmpty, cache.companies.isEmpty {
                cache.connectionState = .connecting
            }
            return generation
        }
    }

    private func finishRefresh(
        _ result: Result<PaperclipRemoteState, Error>,
        generation: Int
    ) {
        update { value in
            guard generation == refreshGeneration else { return }
            value.inFlight = false
            switch result {
            case let .success(state):
                applyCore(state, to: &value)
                publishedCoreGeneration = generation
            case let .failure(error):
                value.connectionState = .error
                value.lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private func finishSessionRefresh(
        _ result: Result<[AgentSessionSnapshot], Error>,
        generation: Int
    ) {
        update { value in
            guard generation == publishedCoreGeneration else { return }
            if case let .success(sessions) = result {
                value.agentSessions = sessions
            }
        }
    }

    private func applyCore(_ state: PaperclipRemoteState, to value: inout Cache) {
        value.connectionState = .connected
        value.lastError = nil
        value.companyName = state.companyName
        value.companyID = state.companyID
        value.companies = state.companies
        value.activity = state.activity
        value.approvals = state.approvals
        value.usage = state.usage
    }

    private static func initialCache(_ configuration: PaperclipConfiguration) -> Cache {
        let state: ConnectionState = configuration.baseURLString.isEmpty ? .disconnected : .connecting
        return Cache(connectionState: state, lastError: configuration.validationError)
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
