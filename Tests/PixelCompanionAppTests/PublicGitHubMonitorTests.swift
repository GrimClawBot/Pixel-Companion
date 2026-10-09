import Combine
import Foundation
@testable import PixelCompanion
import XCTest

final class PublicGitHubMonitorTests: XCTestCase {
    func testRepositorySlugValidationRejectsUnsafeInputAndCredentials() {
        for value in [
            "", "owner", "/repo", "owner/", "owner/repo/extra",
            "owner/../repo", "https://github.com/owner/repo",
            "owner/repo?token=abc", "owner/repo#fragment",
            "owner repo/name", "-owner/repo", "owner/.hidden",
            "owner:secret/repo", "owner/répo"
        ] {
            XCTAssertNil(PublicGitHubRepository(value), value)
        }
        let repo = PublicGitHubRepository("  OpenAI/example-repo  ")
        XCTAssertEqual(repo?.displayName, "OpenAI/example-repo")
        XCTAssertEqual(repo?.endpoint("actions/runs?per_page=3").host, "api.github.com")
        XCTAssertEqual(repo?.endpoint("pulls?state=open&per_page=3").scheme, "https")
    }

    func testPublicAPIParsersUseActualNamesAndConclusionNotEstimates() throws {
        let runs = Data("""
        {"workflow_runs":[{"id":12,"name":"Unit tests","status":"completed",
         "conclusion":"failure","head_branch":"main"},
         {"id":13,"status":"in_progress","conclusion":null,"head_branch":"feature"}]}
        """.utf8)
        let decoded = try JSONDecoder().decode(GitHubPublicRunsResponse.self, from: runs)
        XCTAssertEqual(decoded.workflowRuns.count, 2)
        XCTAssertEqual(GitHubPublicPresentation.workflowLabel(decoded.workflowRuns[0]), "Unit tests")
        XCTAssertEqual(GitHubPublicPresentation.status(decoded.workflowRuns[0]), "Failure")
        XCTAssertEqual(GitHubPublicPresentation.symbol(decoded.workflowRuns[0]), "xmark.circle")
        XCTAssertEqual(GitHubPublicPresentation.status(decoded.workflowRuns[1]), "In Progress")
        XCTAssertEqual(GitHubPublicPresentation.workflowLabel(decoded.workflowRuns[1]), "Unnamed workflow")
        let prs = try JSONDecoder().decode(
            [GitHubPublicPull].self,
            from: Data(#"[{"number":24,"title":"Safer auth"}]"#.utf8)
        )
        XCTAssertEqual(prs.map(\.number), [24])
    }

    func testBrowserLinksUseOnlyValidatedPublicRepoAndPositiveIdentifiers() throws {
        let repo = try XCTUnwrap(PublicGitHubRepository("  octocat/Hello-World "))
        XCTAssertEqual(
            repo.publicRepositoryPage().absoluteString,
            "https://github.com/octocat/Hello-World"
        )
        XCTAssertEqual(
            repo.publicRunPage(id: 987)?.absoluteString,
            "https://github.com/octocat/Hello-World/actions/runs/987"
        )
        XCTAssertEqual(
            repo.publicPullPage(number: 24)?.absoluteString,
            "https://github.com/octocat/Hello-World/pull/24"
        )
        for bad in [-100, -1, 0] {
            XCTAssertNil(repo.publicRunPage(id: bad))
            XCTAssertNil(repo.publicPullPage(number: bad))
        }
        XCTAssertNil(PublicGitHubRepository("evil.example/../redirect"))
        XCTAssertNil(PublicGitHubRepository("octocat/Hello-World?token=x"))
    }

    func testSourceBranchIsDisplayOnlyAndCannotChangeDestination() throws {
        let runs = try JSONDecoder().decode(
            GitHubPublicRunsResponse.self,
            from: Data((
                #"{"workflow_runs":["# +
                #"{"id":52,"name":"CI","status":"completed","# +
                #""conclusion":"success","head_branch":"feature/new-branch"},"# +
                #"{"id":53,"name":"Build","status":"in_progress","# +
                #""conclusion":null,"head_branch":null},"# +
                #"{"id":54,"name":"Other","status":"completed","# +
                #""conclusion":"failure","head_branch":"  \n branch\tlabel  "}]}"#
            ).utf8)
        )
        XCTAssertEqual(
            GitHubPublicPresentation.branchLabel(runs.workflowRuns[0]),
            "feature/new-branch"
        )
        XCTAssertNil(GitHubPublicPresentation.branchLabel(runs.workflowRuns[1]))
        XCTAssertEqual(
            GitHubPublicPresentation.branchLabel(runs.workflowRuns[2]),
            "branch label"
        )
        let repo = try XCTUnwrap(PublicGitHubRepository("test-org/public-repo"))
        XCTAssertEqual(
            repo.publicRunPage(id: runs.workflowRuns[0].id)?.absoluteString,
            "https://github.com/test-org/public-repo/actions/runs/52"
        )
    }

    func testExternalBranchBidiControlsCannotReorderDisplay() throws {
        let run = try JSONDecoder().decode(
            GitHubPublicRunsResponse.self,
            from: Data((
                #"{"workflow_runs":[{"id":5,"status":"completed","conclusion":"success","# +
                #""head_branch":"safe\u202Ecod\u202C\u2066e\u2069"}]}"#
            ).utf8)
        ).workflowRuns[0]
        XCTAssertEqual(GitHubPublicPresentation.branchLabel(run), "safecode")
        XCTAssertEqual(
            GitHubPublicPresentation.runAccessibilityLabel(run),
            "Open public GitHub workflow Unnamed workflow, Status Success, Branch safecode"
        )
        XCTAssertNil(GitHubPublicPresentation.branchLabel(
            try JSONDecoder().decode(
                GitHubPublicRunsResponse.self,
                from: Data(#"{"workflow_runs":[{"id":1,"status":"completed","head_branch":"\u202E"}]}"#.utf8)
            ).workflowRuns[0]
        ))
    }

    func testAccessibleRunAndPRLinksRetainStatusBranchAndTitle() throws {
        let run = try JSONDecoder().decode(
            GitHubPublicRunsResponse.self,
            from: Data(
                (
                    #"{"workflow_runs":[{"id":52,"name":"Build","status":"completed","# +
                    #""conclusion":"failure","head_branch":"release"}]}"#
                ).utf8
            )
        ).workflowRuns[0]
        XCTAssertEqual(
            GitHubPublicPresentation.runAccessibilityLabel(run),
            "Open public GitHub workflow Build, Status Failure, Branch release"
        )
        let pull = GitHubPublicPull(number: 42, title: "Fix authentication")
        XCTAssertEqual(
            GitHubPublicPresentation.pullAccessibilityLabel(pull),
            "Open public GitHub PR #42, Fix authentication"
        )
    }

    func testAPISuppliedArbitraryHTMLURLIsNeverUsedAsBrowserDestination() throws {
        let run = try JSONDecoder().decode(
            GitHubPublicRunsResponse.self,
            from: Data((
                #"{"workflow_runs":[{"id":9,"name":"Run","status":"completed","conclusion":"success","# +
                #""head_branch":"main","html_url":"https://malicious.example/auth"}]}"#
            ).utf8)
        )
        let repo = try XCTUnwrap(PublicGitHubRepository("public-owner/public-repo"))
        XCTAssertEqual(
            repo.publicRunPage(id: run.workflowRuns[0].id)?.host,
            "github.com"
        )
        XCTAssertEqual(
            repo.publicRunPage(id: run.workflowRuns[0].id)?.path,
            "/public-owner/public-repo/actions/runs/9"
        )
    }

    @MainActor
    func testRateLimitAndUnavailableErrorsAreExplicit() {
        XCTAssertTrue((GitHubPublicError.rateLimited.errorDescription ?? "").contains("rate limit"))
        XCTAssertTrue((GitHubPublicError.unavailable.errorDescription ?? "").contains("unavailable"))
        let interval = PublicGitHubMonitor.refreshInterval
        XCTAssertEqual(interval, 180)
    }

    @MainActor
    func testRealMonitorUsesOnlyTwoPublicHTTPSGETsWithoutCredentials() async {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubGitHubProtocol.self]
        let session = URLSession(configuration: config)
        StubGitHubProtocol.reset()
        let monitor = PublicGitHubMonitor(session: session)
        let loaded = expectation(description: "public GitHub data arrived")
        var subscription: AnyCancellable? = monitor.$state.sink { state in
            if state.phase == .ready { loaded.fulfill() }
        }
        monitor.configure("octocat/Hello-World")
        await fulfillment(of: [loaded], timeout: 5)
        let paths = StubGitHubProtocol.paths
        XCTAssertEqual(paths.count, 2)
        XCTAssertTrue(paths.contains("/repos/octocat/Hello-World/actions/runs"))
        XCTAssertTrue(paths.contains("/repos/octocat/Hello-World/pulls"))
        XCTAssertEqual(monitor.state.runs.count, 1)
        XCTAssertEqual(monitor.state.openPulls.count, 1)
        XCTAssertNotNil(monitor.state.fetchedAt)
        XCTAssertEqual(StubGitHubProtocol.invalidRequests, 0)
        // Leave no scheduled polling or unbounded repeated public requests.
        monitor.configure("")
        subscription?.cancel()
        subscription = nil
    }

    @MainActor
    func testBadRepoIsRejectedWithoutAnyNetworkTraffic() {
        StubGitHubProtocol.reset()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubGitHubProtocol.self]
        let monitor = PublicGitHubMonitor(session: URLSession(configuration: config))
        monitor.configure("https://evil.example/redirect")
        XCTAssertEqual(monitor.state.phase, .unavailable)
        XCTAssertEqual(StubGitHubProtocol.paths.count, 0)
    }
}

private final class StubGitHubProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var requestedPaths: [String] = []
    private static var rejected = 0

    static var paths: [String] {
        lock.lock()
        defer { lock.unlock() }
        return requestedPaths
    }

    static var invalidRequests: Int {
        lock.lock()
        defer { lock.unlock() }
        return rejected
    }

    static func reset() {
        lock.lock()
        requestedPaths = []
        rejected = 0
        lock.unlock()
    }

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        Self.lock.lock()
        Self.requestedPaths.append(url.path)
        if url.scheme != "https" || url.host != "api.github.com" ||
            request.httpMethod != "GET" ||
            request.value(forHTTPHeaderField: "Authorization") != nil {
            Self.rejected += 1
        }
        Self.lock.unlock()
        let body: String
        if url.path.hasSuffix("/actions/runs") {
            body = #"{"workflow_runs":[{"id":4,"name":"CI","status":"completed","conclusion":"success"}]}"#
        } else {
            body = #"[{"number":8,"title":"Documentation"}]"#
        }
        let response = HTTPURLResponse(
            url: url, statusCode: 200, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
