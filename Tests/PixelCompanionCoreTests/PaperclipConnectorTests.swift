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

    func fetch(
        configuration: PaperclipConfiguration,
        completion: @escaping (Result<PaperclipRemoteState, Error>) -> Void
    ) {
        fetchCount += 1
        self.completion = completion
    }

    func finish(_ result: Result<PaperclipRemoteState, Error>) {
        let completion = completion
        self.completion = nil
        completion?(result)
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
        service.finish(.success(PaperclipRemoteState(
            companies: [PaperclipCompany(id: "company-1", name: "Example Co", status: "active")],
            companyID: "company-1",
            companyName: "Example Co",
            activity: [activity],
            approvals: [approval],
            usage: UsageSnapshot(used: 25, limit: 100, unit: "cents", periodLabel: "This month")
        )))

        XCTAssertEqual(connector.connectionState, .connected)
        XCTAssertEqual(connector.displayName, "Paperclip · Example Co")
        XCTAssertEqual(connector.currentActivity, activity)
        XCTAssertEqual(connector.pendingApprovals(), [approval])
        XCTAssertEqual(connector.availableCompanies.map(\.name), ["Example Co"])

        connector.refresh()
        XCTAssertEqual(service.fetchCount, 2)
    }


    func testDuplicateAgentIDsDoNotCrashMapper() {
        let company = PaperclipCompany(id: "company-1", name: "Example Co", status: "active")
        let input = PaperclipMappingInput(
            companies: [company],
            company: company,
            dashboard: PaperclipDashboardResponse(
                costs: PaperclipDashboardResponse.Costs(monthSpendCents: 0, monthBudgetCents: 0)
            ),
            agents: [
                PaperclipAgentResponse(
                    id: "agent-1",
                    name: "Old Name",
                    title: nil,
                    status: "idle",
                    lastHeartbeatAt: nil,
                    updatedAt: "2026-10-07T17:00:00.000Z"
                ),
                PaperclipAgentResponse(
                    id: "agent-1",
                    name: "Current Name",
                    title: nil,
                    status: "idle",
                    lastHeartbeatAt: nil,
                    updatedAt: "2026-10-07T18:00:00.000Z"
                )
            ],
            issues: [
                PaperclipIssueResponse(
                    id: "issue-1",
                    identifier: "EX-1",
                    title: "Duplicate-safe mapping",
                    status: "in_progress",
                    assigneeAgentId: "agent-1",
                    lastActivityAt: "2026-10-07T19:00:00.000Z",
                    updatedAt: nil,
                    createdAt: nil
                )
            ],
            approvals: []
        )

        let state = PaperclipMapper.map(input)

        XCTAssertEqual(state.activity.first?.detail, "EX-1 · in progress · Current Name")
    }

    func testCurrentActivityUsesNewestEventEvenWhenOlderEventIsRunning() {
        let service = DeferredPaperclipService()
        let connector = PaperclipConnector(
            configuration: PaperclipConfiguration(baseURLString: "https://paperclip.example", companyID: "company-1"),
            service: service
        )
        let newestFailure = ActivityEvent(
            id: "newest",
            kind: .failed,
            title: "Latest failure",
            timestamp: Date(timeIntervalSince1970: 200)
        )
        let olderRunning = ActivityEvent(
            id: "older",
            kind: .running,
            title: "Older running",
            timestamp: Date(timeIntervalSince1970: 100)
        )

        connector.refresh()
        service.finish(.success(PaperclipRemoteState(
            companies: [],
            companyID: "company-1",
            companyName: "Example Co",
            activity: [newestFailure, olderRunning],
            approvals: [],
            usage: nil
        )))

        XCTAssertEqual(connector.currentActivity, newestFailure)
    }

    func testURLServiceMapsOnlyReadOnlyDashboardData() {
        let service = makeService()
        installDashboardFixture()

        let expectation = expectation(description: "Paperclip fetch")
        service.fetch(configuration: selectedConfiguration()) { result in
            guard case let .success(state) = result else {
                XCTFail("Expected successful mapping: \(result)")
                expectation.fulfill()
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
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2)
    }

    func testURLServiceReportsHTTPFailure() {
        let service = makeService()
        StubURLProtocol.handler = { _ in (503, Data("{}".utf8)) }

        let expectation = expectation(description: "Paperclip failure")
        service.fetch(configuration: PaperclipConfiguration(baseURLString: "https://paperclip.example")) { result in
            guard case let .failure(error) = result else {
                XCTFail("Expected failure")
                expectation.fulfill()
                return
            }
            XCTAssertEqual(error.localizedDescription, "Paperclip returned HTTP 503.")
            expectation.fulfill()
        }
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
        service.fetch(configuration: PaperclipConfiguration(baseURLString: "https://paperclip.example")) { result in
            guard case let .success(state) = result else {
                XCTFail("Expected discovery success")
                expectation.fulfill()
                return
            }
            XCTAssertNil(state.companyID)
            XCTAssertEqual(state.companies.map(\.name), ["Alpha", "Beta"])
            XCTAssertTrue(state.activity.isEmpty)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2)
    }

    private func installDashboardFixture() {
        StubURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
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
                "title": "Engineer",
                "status": "running",
                "updatedAt": "2026-10-07T18:00:00.000Z"
            ],
            [
                "id": "agent-2",
                "name": "QA",
                "title": "QA Engineer",
                "status": "idle",
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
