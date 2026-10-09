import Combine
import Foundation

/// Public repository names only. Both API endpoints are fixed at api.github.com.
struct PublicGitHubRepository: Equatable {
    let owner: String
    let name: String

    init?(_ raw: String) {
        let components = raw.trimmingCharacters(in: .whitespacesAndNewlines).split(
            separator: "/", omittingEmptySubsequences: false
        )
        guard components.count == 2 else { return nil }
        let owner = String(components[0])
        let name = String(components[1])
        guard Self.valid(owner), Self.valid(name), owner.count <= 39,
              name.count <= 100, !owner.hasPrefix("-"), !owner.hasSuffix("-"),
              !name.hasPrefix("."), !name.hasSuffix(".") else { return nil }
        self.owner = owner
        self.name = name
    }

    var displayName: String { owner + "/" + name }

    /// User-triggered browser links are constructed exclusively from the
    /// validated repository slug and positive numeric GitHub IDs. Never trust
    /// html_url or an arbitrary URL returned in the API payload.
    func publicRunPage(id: Int) -> URL? {
        guard id > 0 else { return nil }
        return URL(string: "https://github.com/\(owner)/\(name)/actions/runs/\(id)")
    }

    func publicPullPage(number: Int) -> URL? {
        guard number > 0 else { return nil }
        return URL(string: "https://github.com/\(owner)/\(name)/pull/\(number)")
    }

    func publicRepositoryPage() -> URL {
        URL(string: "https://github.com/\(owner)/\(name)")!
    }

    func endpoint(_ resource: String) -> URL {
        // owner and name are restricted to unreserved ASCII characters.
        URL(string: "https://api.github.com/repos/\(owner)/\(name)/\(resource)")!
    }

    private static func valid(_ component: String) -> Bool {
        !component.isEmpty && component.utf8.allSatisfy { byte in
            (65...90).contains(byte) || (97...122).contains(byte) ||
                (48...57).contains(byte) || byte == 45 || byte == 46 || byte == 95
        } && component != "." && component != ".."
    }
}

struct GitHubPublicRun: Decodable, Identifiable {
    let id: Int
    let name: String?
    let status: String
    let conclusion: String?
    let headBranch: String?

    enum CodingKeys: String, CodingKey {
        case id, name, status, conclusion
        case headBranch = "head_branch"
    }
}

struct GitHubPublicPull: Decodable, Identifiable {
    let number: Int
    let title: String
    var id: Int { number }
}

struct GitHubPublicRunsResponse: Decodable {
    let workflowRuns: [GitHubPublicRun]

    enum CodingKeys: String, CodingKey {
        case workflowRuns = "workflow_runs"
    }
}

struct GitHubPublicState {
    enum Phase {
        case off
        case loading
        case ready
        case unavailable
    }

    let repository: String
    let phase: Phase
    let runs: [GitHubPublicRun]
    let openPulls: [GitHubPublicPull]
    let fetchedAt: Date?
    let errorMessage: String?

    static let off = GitHubPublicState(
        repository: "", phase: .off, runs: [], openPulls: [],
        fetchedAt: nil, errorMessage: nil
    )
}

/// A completely separate, read-only public CI side source.
/// No auth cookies, credentials, arbitrary URLs, or mutation endpoints.
@MainActor
final class PublicGitHubMonitor: ObservableObject {
    @Published private(set) var state: GitHubPublicState = .off

    private let session: URLSession
    private var currentRepository: PublicGitHubRepository?
    private var lastAttempt: Date?
    private var timer: Timer?
    private var generation = 0
    private var fetching = false

    static let refreshInterval: TimeInterval = 180

    init(session: URLSession = URLSession(configuration: .ephemeral)) {
        self.session = session
    }

    func configure(_ value: String) {
        generation += 1
        lastAttempt = nil
        fetching = false
        timer?.invalidate()
        timer = nil

        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            currentRepository = nil
            state = .off
            return
        }
        guard let repository = PublicGitHubRepository(value) else {
            currentRepository = nil
            state = GitHubPublicState(
                repository: value, phase: .unavailable,
                runs: [], openPulls: [], fetchedAt: nil,
                errorMessage: "Enter a public repository as owner/repo."
            )
            return
        }
        currentRepository = repository
        state = GitHubPublicState(
            repository: repository.displayName, phase: .loading,
            runs: [], openPulls: [], fetchedAt: nil, errorMessage: nil
        )
        refresh()
        let timer = Timer(timeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func refresh() {
        guard let repository = currentRepository, !fetching else { return }
        if let lastAttempt,
           Date().timeIntervalSince(lastAttempt) < Self.refreshInterval { return }
        lastAttempt = Date()
        fetching = true
        // Clear prior verified results while checking, never show old green CI as live.
        state = GitHubPublicState(
            repository: repository.displayName, phase: .loading,
            runs: [], openPulls: [], fetchedAt: nil, errorMessage: nil
        )
        generation += 1
        let token = generation

        Task { [weak self] in
            guard let self else { return }
            let result = await self.load(repository)
            guard token == self.generation, self.currentRepository == repository else { return }
            self.fetching = false
            switch result {
            case let .success(payload):
                self.state = GitHubPublicState(
                    repository: repository.displayName, phase: .ready,
                    runs: payload.0, openPulls: payload.1,
                    fetchedAt: Date(), errorMessage: nil
                )
            case let .failure(error):
                // Never leave a failed or stale response on screen as live green CI.
                self.state = GitHubPublicState(
                    repository: repository.displayName, phase: .unavailable,
                    runs: [], openPulls: [], fetchedAt: nil,
                    errorMessage: error.localizedDescription
                )
            }
        }
    }

    private func load(
        _ repo: PublicGitHubRepository
    ) async -> Result<([GitHubPublicRun], [GitHubPublicPull]), Error> {
        do {
            let runs: GitHubPublicRunsResponse = try await get(
                repo.endpoint("actions/runs?per_page=3")
            )
            let pulls: [GitHubPublicPull] = try await get(
                repo.endpoint("pulls?state=open&per_page=3")
            )
            return .success((Array(runs.workflowRuns.prefix(3)), Array(pulls.prefix(3))))
        } catch {
            return .failure(error)
        }
    }

    private func get<T: Decodable>(_ url: URL) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 8
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse,
              http.url?.host == "api.github.com" else {
            throw GitHubPublicError.unavailable
        }
        if http.statusCode == 429 ||
            (http.statusCode == 403 && http.value(forHTTPHeaderField: "X-RateLimit-Remaining") == "0") {
            throw GitHubPublicError.rateLimited
        }
        guard (200..<300).contains(http.statusCode) else {
            throw GitHubPublicError.unavailable
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

enum GitHubPublicError: LocalizedError {
    case rateLimited
    case unavailable

    var errorDescription: String? {
        switch self {
        case .rateLimited:
            return "GitHub rate limit reached. Public status is unavailable."
        case .unavailable:
            return "Public repository status unavailable (private, missing or offline)."
        }
    }
}
