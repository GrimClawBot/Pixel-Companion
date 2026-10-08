import Foundation

/// Read-only Paperclip connector. Network requests update a synchronized cache off the UI path.
public final class PaperclipConnector:
    Connector,
    AuthProvider,
    ActivitySource,
    ApprovalProvider,
    UsageProvider,
    AgentSessionSource,
    TaskSource {
    public let id: ConnectorID = .paperclip
    public let configuration: PaperclipConfiguration

    private struct Cache {
        var connectionState: ConnectionState
        var lastError: String?
        var lastSuccessfulRefreshAt: Date?
        var lastSuccessfulSessionRefreshAt: Date?
        var companyName: String?
        var companyID: String?
        var companies: [PaperclipCompany] = []
        var activity: [ActivityEvent] = []
        var approvals: [ApprovalRequest] = []
        var usage: UsageSnapshot?
        var agentSessions: [AgentSessionSnapshot] = []
        var tasks: [TaskSnapshot] = []
        var inFlight = false
    }

    private let lock = NSLock()
    private let service: any PaperclipServiceProtocol
    private var cache: Cache
    private var refreshGeneration = 0
    private var publishedCoreGeneration = 0
    private var publishedSessionGeneration = 0
    /// Successful core publications whose slower session fetches may complete later.
    private var pendingSessions: [Int: (companyID: String?, coreTime: Date)] = [:]

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
    /// Client-side time of the most recent successful core refresh; not server activity time.
    public var lastSuccessfulRefreshAt: Date? { locked { cache.lastSuccessfulRefreshAt } }
    /// Separate session evidence; a healthy core poll never refreshes stale agent telemetry.
    public var lastSuccessfulSessionRefreshAt: Date? {
        locked { cache.lastSuccessfulSessionRefreshAt }
    }
    public var auth: (any AuthProvider)? { self }
    public var activity: (any ActivitySource)? { self }
    public var approvals: (any ApprovalProvider)? { self }
    public var usage: (any UsageProvider)? { self }
    public var sessions: (any AgentSessionSource)? { self }
    public var tasks: (any TaskSource)? { self }
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

    public func tasks(limit: Int) -> [TaskSnapshot] {
        locked { Array(cache.tasks.prefix(max(limit, 0))) }
    }

    /// Capture all presentation fields and both refresh timestamps under ONE lock.
    /// Multiple ConnectorSnapshot(capturing:) and timestamp accessor calls can
    /// otherwise pair older agent rows with the timestamp of newer telemetry.
    public func capturePresentation(
        sessionLimit: Int = Int.max
    ) -> PaperclipPresentationCapture {
        locked {
            let snapshot = ConnectorSnapshot(
                connectorName: cache.companyName.map { "Paperclip · \($0)" } ?? "Paperclip",
                connectionState: cache.connectionState,
                lastError: cache.connectionState == .error ? cache.lastError : nil,
                currentActivity: cache.activity.first,
                recentActivity: Array(cache.activity.prefix(8)),
                pendingApprovals: cache.approvals,
                usage: cache.usage,
                agentSessions: Array(cache.agentSessions.prefix(max(sessionLimit, 0))),
                tasks: Array(cache.tasks.prefix(64))
            )
            return PaperclipPresentationCapture(
                snapshot: snapshot,
                coreAt: cache.lastSuccessfulRefreshAt,
                sessionsAt: cache.lastSuccessfulSessionRefreshAt
            )
        }
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
                let companyChanged = value.companyID != state.companyID
                applyCore(state, to: &value)
                if companyChanged {
                    value.lastSuccessfulSessionRefreshAt = nil
                    publishedSessionGeneration = 0
                    pendingSessions.removeAll()
                }
                publishedCoreGeneration = generation
                if let coreTime = value.lastSuccessfulRefreshAt {
                    pendingSessions[generation] = (state.companyID, coreTime)
                }
                // A bounded number of unresolved older queries may still return.
                pendingSessions = pendingSessions.filter { generation - $0.key < 32 }
            case let .failure(error):
                value.connectionState = .error
                value.lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                value.agentSessions = []
                value.lastSuccessfulSessionRefreshAt = nil
                value.tasks = []
                publishedCoreGeneration = 0
                publishedSessionGeneration = 0
                pendingSessions.removeAll()
            }
        }
    }

    private func finishSessionRefresh(
        _ result: Result<[AgentSessionSnapshot], Error>,
        generation: Int
    ) {
        update { value in
            // Core refresh may advance independently while session fetch runs.
            // Accept the newest completed session evidence for this SAME company,
            // without allowing an older response to replace a newer session result.
            guard let pending = pendingSessions.removeValue(forKey: generation),
                  value.connectionState == .connected,
                  pending.companyID == value.companyID,
                  generation > publishedSessionGeneration else { return }
            publishedSessionGeneration = generation
            switch result {
            case let .success(sessions):
                value.agentSessions = sessions
                // Date of the associated core fetch, not the later callback time:
                // a slow response cannot make old telemetry appear newly fresh.
                value.lastSuccessfulSessionRefreshAt = pending.coreTime
            case .failure:
                value.agentSessions = []
                value.lastSuccessfulSessionRefreshAt = nil
            }
        }
    }

    private func applyCore(_ state: PaperclipRemoteState, to value: inout Cache) {
        let companyChanged = value.companyID != state.companyID
        value.connectionState = .connected
        value.lastError = nil
        value.lastSuccessfulRefreshAt = Date()
        value.companyName = state.companyName
        value.companyID = state.companyID
        value.companies = state.companies
        value.activity = state.activity
        value.approvals = state.approvals
        value.tasks = state.tasks
        value.usage = state.usage
        if companyChanged || value.agentSessions.isEmpty {
            value.agentSessions = state.agentSessions
        }
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
