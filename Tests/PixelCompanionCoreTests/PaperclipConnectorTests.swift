import Foundation
@testable import PixelCompanionCore
import XCTest

private final class StubURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, Data))?

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (status, data) = try handler(request)
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: status,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )
            client?.urlProtocol(self, didReceive: try XCTUnwrap(response), cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private final class DeferredPaperclipService: PaperclipServiceProtocol {
    private(set) var fetchCount = 0
    private var completion: ((Result<PaperclipRemoteState, Error>) -> Void)?
    private var sessionCompletion: ((Result<[AgentSessionSnapshot], Error>) -> Void)?

    func fetch(
        configuration: PaperclipConfiguration,
        completion: @escaping (Result<PaperclipRemoteState, Error>) -> Void,
        sessionCompletion: @escaping (Result<[AgentSessionSnapshot], Error>) -> Void
    ) {
        fetchCount += 1
        self.completion = completion
        self.sessionCompletion = sessionCompletion
    }

    func finishCore(_ result: Result<PaperclipRemoteState, Error>) {
        let completion = completion
        self.completion = nil
        completion?(result)
    }

    func finishSessions(_ result: Result<[AgentSessionSnapshot], Error>) {
        let sessionCompletion = sessionCompletion
        self.sessionCompletion = nil
        sessionCompletion?(result)
    }
}

final class PaperclipConnectorTests: XCTestCase {
    override func tearDown() {
        StubURLProtocol.handler = nil
        super.tearDown()
    }

    func testConfigurationValidationRejectsCredentialsAndNonHTTPURLs() {
        XCTAssertNil(PaperclipConfiguration().validationError)
        XCTAssertNotNil(PaperclipConfiguration(baseURLString: "paperclip.local").validationError)
        XCTAssertNotNil(PaperclipConfiguration(baseURLString: "ftp://paperclip.local").validationError)
        XCTAssertNotNil(PaperclipConfiguration(baseURLString: "https://user:pass@paperclip.local").validationError)
        XCTAssertNotNil(PaperclipConfiguration(baseURLString: "https://paperclip.local?token=nope").validationError)

        let configuration = PaperclipConfiguration(
            baseURLString: "  http://127.0.0.1:3100/  ",
            companyID: " company-1 "
        )
        XCTAssertEqual(configuration.baseURL?.absoluteString, "http://127.0.0.1:3100")
        XCTAssertEqual(configuration.companyID, "company-1")
    }

    func testRefreshCoalescesAndPublishesCachedState() {
        let service = DeferredPaperclipService()
        let connector = PaperclipConnector(
            configuration: PaperclipConfiguration(baseURLString: "https://paperclip.example", companyID: "company-1"),
            service: service
        )

        connector.refresh()
        connector.refresh()
        XCTAssertEqual(service.fetchCount, 1)
        XCTAssertEqual(connector.connectionState, .connecting)

        let activity = ActivityEvent(
            id: "event-1",
            kind: .running,
            title: "Implement connector",
            timestamp: Date(timeIntervalSince1970: 100)
        )
        let approval = ApprovalRequest(
            id: "approval-1",
            title: "Review release",
            requestedAt: Date(timeIntervalSince1970: 90)
        )
        service.finishCore(.success(PaperclipRemoteState(
            companies: [PaperclipCompany(id: "company-1", name: "Example Co", status: "active")],
            companyID: "company-1",
            companyName: "Example Co",
            activity: [activity],
            approvals: [approval],
            usage: UsageSnapshot(used: 25, limit: 100, unit: "cents", periodLabel: "This month"),
            agentSessions: []
        )))

        XCTAssertEqual(connector.connectionState, .connected)
        XCTAssertEqual(connector.displayName, "Paperclip · Example Co")
        XCTAssertEqual(connector.currentActivity, activity)
        XCTAssertEqual(connector.pendingApprovals(), [approval])
        XCTAssertEqual(connector.availableCompanies.map(\.name), ["Example Co"])

        connector.refresh()
        XCTAssertEqual(service.fetchCount, 2)
    }


    func testCoreRefreshReleasesPollingBeforeSessionEnrichment() {
        let service = DeferredPaperclipService()
        let connector = PaperclipConnector(
            configuration: PaperclipConfiguration(
                baseURLString: "https://paperclip.example",
                companyID: "company-1"
            ),
            service: service
        )

        connector.refresh()
        service.finishCore(.success(PaperclipRemoteState(
            companies: [PaperclipCompany(id: "company-1", name: "Example Co", status: "active")],
            companyID: "company-1",
            companyName: "Example Co",
            activity: [],
            approvals: [],
            usage: nil,
            agentSessions: []
        )))

        XCTAssertEqual(connector.connectionState, .connected)
        connector.refresh()
        XCTAssertEqual(service.fetchCount, 2, "Core completion must release the next poll before telemetry finishes")
    }

    func testLiveRunsRestoreActiveSessionOutsideRecentWindow() {
        let service = makeService()
        StubURLProtocol.handler = { request in
            switch request.url?.path {
            case "/api/companies/company-1/heartbeat-runs":
                return (200, self.json([[
                    "id": "recent-completed",
                    "agentId": "agent-1",
                    "status": "completed",
                    "createdAt": "2026-10-07T19:00:00.000Z",
                    "updatedAt": "2026-10-07T19:01:00.000Z"
                ]]))
            case "/api/companies/company-1/live-runs":
                return (200, self.json([[
                    "id": "older-live",
                    "agentId": "agent-1",
                    "status": "running",
                    "startedAt": "2026-10-07T18:00:00.000Z",
                    "createdAt": "2026-10-07T18:00:00.000Z",
                    "updatedAt": "2026-10-07T18:30:00.000Z",
                    "contextSnapshot": ["issueId": "issue-1"]
                ]]))
            default:
                return self.dashboardResponse(for: request.url?.path)
            }
        }

        let sessionExpectation = expectation(description: "Live session enrichment")
        service.fetch(
            configuration: selectedConfiguration(),
            completion: { _ in },
            sessionCompletion: { result in
                guard case let .success(sessions) = result else {
                    XCTFail("Expected live session enrichment")
                    sessionExpectation.fulfill()
                    return
                }
                XCTAssertEqual(sessions.first?.runID, "older-live")
                XCTAssertEqual(sessions.first?.runState, .running)
                sessionExpectation.fulfill()
            }
        )
        wait(for: [sessionExpectation], timeout: 2)
    }

    func testMalformedHeartbeatRunDoesNotDiscardValidRuns() {
        let service = makeService()
        StubURLProtocol.handler = { request in
            switch request.url?.path {
            case "/api/companies/company-1/heartbeat-runs":
                return (200, self.json([
                    [
                        "id": "bad-run",
                        "agentId": "agent-1",
                        "status": "completed",
                        "usageJson": ["inputTokens": "not-an-int"]
                    ],
                    [
                        "id": "good-run",
                        "agentId": "agent-1",
                        "status": "completed",
                        "createdAt": "2026-10-07T19:00:00.000Z",
                        "updatedAt": "2026-10-07T19:01:00.000Z"
                    ]
                ]))
            case "/api/companies/company-1/live-runs":
                return (200, self.json([]))
            default:
                return self.dashboardResponse(for: request.url?.path)
            }
        }

        let sessionExpectation = expectation(description: "Lossy session enrichment")
        service.fetch(
            configuration: selectedConfiguration(),
            completion: { _ in },
            sessionCompletion: { result in
                guard case let .success(sessions) = result else {
                    XCTFail("Expected lossy telemetry decoding to keep valid runs")
                    sessionExpectation.fulfill()
                    return
                }
                XCTAssertEqual(sessions.first?.runID, "good-run")
                sessionExpectation.fulfill()
            }
        )
        wait(for: [sessionExpectation], timeout: 2)
    }

    func testURLServiceMapsCoreAndSessionTelemetrySeparately() {
        let service = makeService()
        installDashboardFixture()

        let coreExpectation = expectation(description: "Paperclip core fetch")
        let sessionExpectation = expectation(description: "Paperclip session enrichment")
        service.fetch(
            configuration: selectedConfiguration(),
            completion: { result in
                guard case let .success(state) = result else {
                    XCTFail("Expected successful core mapping: \(result)")
                    coreExpectation.fulfill()
                    return
                }
                XCTAssertEqual(state.companyName, "Example Co")
                XCTAssertEqual(state.companies.count, 1)
                XCTAssertEqual(state.activity.first?.title, "Build native connector")
                XCTAssertEqual(state.activity.first?.detail, "EX-1 · in progress · Builder")
                XCTAssertTrue(state.activity.contains { $0.title == "Builder · running" })
                XCTAssertEqual(state.approvals.map(\.title), ["Ship build"])
                XCTAssertEqual(state.usage?.used, 125)
                XCTAssertEqual(state.usage?.limit, 1000)
                XCTAssertTrue(state.agentSessions.isEmpty)
                coreExpectation.fulfill()
            },
            sessionCompletion: { result in
                guard case let .success(sessions) = result else {
                    XCTFail("Expected successful session enrichment: \(result)")
                    sessionExpectation.fulfill()
                    return
                }
                XCTAssertEqual(sessions.count, 2)
                XCTAssertEqual(sessions.first?.agentName, "Builder")
                XCTAssertEqual(sessions.first?.runState, .running)
                XCTAssertEqual(sessions.first?.model, "gpt-5.6-sol")
                XCTAssertEqual(sessions.first?.provider, "openai")
                XCTAssertEqual(sessions.first?.taskTitle, "EX-1 · Build native connector")
                sessionExpectation.fulfill()
            }
        )
        wait(for: [coreExpectation, sessionExpectation], timeout: 2)
    }

    func testRunTelemetryFailureDoesNotBreakBaseConnectorData() {
        let service = makeService()
        StubURLProtocol.handler = { request in
            if request.url?.path.hasSuffix("/heartbeat-runs") == true
                || request.url?.path.hasSuffix("/live-runs") == true {
                return (403, Data("{}".utf8))
            }
            return self.dashboardResponse(for: request.url?.path)
        }

        let coreExpectation = expectation(description: "Paperclip core fetch")
        let sessionExpectation = expectation(description: "Paperclip telemetry failure")
        service.fetch(
            configuration: selectedConfiguration(),
            completion: { result in
                guard case let .success(state) = result else {
                    XCTFail("Expected base connector data to survive telemetry failure: \(result)")
                    coreExpectation.fulfill()
                    return
                }
                XCTAssertEqual(state.companyName, "Example Co")
                XCTAssertEqual(state.activity.first?.title, "Build native connector")
                XCTAssertTrue(state.agentSessions.isEmpty)
                coreExpectation.fulfill()
            },
            sessionCompletion: { result in
                guard case .failure = result else {
                    XCTFail("Expected optional telemetry failure")
                    sessionExpectation.fulfill()
                    return
                }
                sessionExpectation.fulfill()
            }
        )
        wait(for: [coreExpectation, sessionExpectation], timeout: 2)
    }

    func testURLServiceReportsHTTPFailure() {
        let service = makeService()
        StubURLProtocol.handler = { _ in (503, Data("{}".utf8)) }

        let expectation = expectation(description: "Paperclip failure")
        service.fetch(
            configuration: PaperclipConfiguration(baseURLString: "https://paperclip.example"),
            completion: { result in
                guard case let .failure(error) = result else {
                    XCTFail("Expected failure")
                    expectation.fulfill()
                    return
                }
                XCTAssertEqual(error.localizedDescription, "Paperclip returned HTTP 503.")
                expectation.fulfill()
            },
            sessionCompletion: { _ in }
        )
        wait(for: [expectation], timeout: 2)
    }

    func testMultipleCompaniesCanBeDiscoveredBeforeSelection() {
        let service = makeService()
        StubURLProtocol.handler = { request in
            switch request.url?.path {
            case "/api/health":
                return (200, self.json(["status": "ok"]))
            case "/api/companies":
                return (200, self.json([
                    ["id": "a", "name": "Alpha", "status": "active"],
                    ["id": "b", "name": "Beta", "status": "active"]
                ]))
            default:
                XCTFail("Company-specific endpoints must not be called before selection")
                return (500, Data())
            }
        }

        let expectation = expectation(description: "Company discovery")
        service.fetch(
            configuration: PaperclipConfiguration(baseURLString: "https://paperclip.example"),
            completion: { result in
                guard case let .success(state) = result else {
                    XCTFail("Expected discovery success")
                    expectation.fulfill()
                    return
                }
                XCTAssertNil(state.companyID)
                XCTAssertEqual(state.companies.map(\.name), ["Alpha", "Beta"])
                XCTAssertTrue(state.activity.isEmpty)
                expectation.fulfill()
            },
            sessionCompletion: { _ in }
        )
        wait(for: [expectation], timeout: 2)
    }

}

private extension PaperclipConnectorTests {
    private func installDashboardFixture() {
        StubURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            if request.url?.path == "/api/companies/company-1/heartbeat-runs" {
                let components = URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)
                XCTAssertEqual(components?.queryItems?.first(where: { $0.name == "limit" })?.value, "40")
            }
            return self.dashboardResponse(for: request.url?.path)
        }
    }

    private func dashboardResponse(for path: String?) -> (Int, Data) {
        switch path {
        case "/api/health":
            return (200, json(["status": "ok"]))
        case "/api/companies":
            return (200, companiesJSON())
        case "/api/companies/company-1/dashboard":
            return (200, json(["costs": ["monthSpendCents": 125, "monthBudgetCents": 1000]]))
        case "/api/companies/company-1/agents":
            return (200, agentsJSON())
        case "/api/companies/company-1/issues":
            return (200, issuesJSON())
        case "/api/companies/company-1/approvals":
            return (200, approvalsJSON())
        case "/api/companies/company-1/heartbeat-runs":
            return (200, heartbeatRunsJSON())
        case "/api/companies/company-1/live-runs":
            return (200, heartbeatRunsJSON())
        default:
            XCTFail("Unexpected path: \(path ?? "nil")")
            return (404, Data())
        }
    }

    private func companiesJSON() -> Data {
        json([["id": "company-1", "name": "Example Co", "status": "active"]])
    }

    private func agentsJSON() -> Data {
        json([
            [
                "id": "agent-1",
                "name": "Builder",
                "role": "engineer",
                "title": "Engineer",
                "status": "running",
                "adapterType": "codex_local",
                "adapterConfig": ["model": "gpt-5.6-sol"],
                "runtimeConfig": ["aiConnection": ["provider": "openai"]],
                "updatedAt": "2026-10-07T18:00:00.000Z"
            ],
            [
                "id": "agent-2",
                "name": "QA",
                "role": "qa",
                "title": "QA Engineer",
                "status": "idle",
                "adapterType": "claude_local",
                "adapterConfig": ["model": "claude-sonnet-5-5"],
                "runtimeConfig": ["aiConnection": ["provider": "anthropic"]],
                "updatedAt": "2026-10-07T17:00:00.000Z"
            ]
        ])
    }

    private func issuesJSON() -> Data {
        json([[
            "id": "issue-1",
            "identifier": "EX-1",
            "title": "Build native connector",
            "status": "in_progress",
            "assigneeAgentId": "agent-1",
            "lastActivityAt": "2026-10-07T18:10:00.000Z",
            "updatedAt": "2026-10-07T18:10:00.000Z",
            "createdAt": "2026-10-07T17:30:00.000Z",
            "description": "Ignored by the connector."
        ]])
    }

    private func approvalsJSON() -> Data {
        json([[
            "id": "approval-1",
            "title": "Ship build",
            "status": "pending",
            "requestedAt": "2026-10-07T18:05:00.000Z"
        ]])
    }

    private func heartbeatRunsJSON() -> Data {
        json([[
            "id": "run-1",
            "agentId": "agent-1",
            "status": "running",
            "startedAt": "2026-10-07T18:11:00.000Z",
            "createdAt": "2026-10-07T18:11:00.000Z",
            "updatedAt": "2026-10-07T18:12:00.000Z",
            "usageJson": [
                "model": "gpt-5.6-sol",
                "provider": "openai",
                "inputTokens": 1200,
                "cachedInputTokens": 800,
                "outputTokens": 250,
                "persistedSessionId": "session-1"
            ],
            "contextSnapshot": ["issueId": "issue-1"]
        ]])
    }

    private func selectedConfiguration() -> PaperclipConfiguration {
        PaperclipConfiguration(
            baseURLString: "https://paperclip.example",
            companyID: "company-1"
        )
    }

    private func makeService() -> URLSessionPaperclipService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSessionPaperclipService(session: URLSession(configuration: configuration))
    }

    private func json(_ object: Any) -> Data {
        (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
    }
}
