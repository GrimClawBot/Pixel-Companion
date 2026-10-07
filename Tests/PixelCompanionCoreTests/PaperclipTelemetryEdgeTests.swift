import Foundation
@testable import PixelCompanionCore
import XCTest

private final class EdgeStubURLProtocol: URLProtocol {
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

private final class EdgeDeferredService: PaperclipServiceProtocol {
    private var coreCompletion: ((Result<PaperclipRemoteState, Error>) -> Void)?
    private var sessionCompletion: ((Result<[AgentSessionSnapshot], Error>) -> Void)?

    func fetch(
        configuration: PaperclipConfiguration,
        completion: @escaping (Result<PaperclipRemoteState, Error>) -> Void,
        sessionCompletion: @escaping (Result<[AgentSessionSnapshot], Error>) -> Void
    ) {
        coreCompletion = completion
        self.sessionCompletion = sessionCompletion
    }

    func finishCore(_ result: Result<PaperclipRemoteState, Error>) {
        coreCompletion?(result)
        coreCompletion = nil
    }

    func finishSessions(_ result: Result<[AgentSessionSnapshot], Error>) {
        sessionCompletion?(result)
        sessionCompletion = nil
    }
}

final class PaperclipTelemetryEdgeTests: XCTestCase {
    override func tearDown() {
        EdgeStubURLProtocol.handler = nil
        super.tearDown()
    }

    func testNewerTelemetryPollWaitsForAFreshNetworkSnapshot() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [EdgeStubURLProtocol.self]
        let client = PaperclipHTTPClient(session: URLSession(configuration: configuration))
        let fetcher = PaperclipTelemetryFetcher(client: client)
        let payload = telemetryPayload()
        let countLock = NSLock()
        var heartbeatCount = 0
        var liveCount = 0

        EdgeStubURLProtocol.handler = { request in
            switch request.url?.path {
            case "/api/companies/company-1/heartbeat-runs":
                countLock.lock()
                heartbeatCount += 1
                countLock.unlock()
                Thread.sleep(forTimeInterval: 0.05)
                return (200, self.json([]))
            case "/api/companies/company-1/live-runs":
                countLock.lock()
                liveCount += 1
                countLock.unlock()
                return (200, self.json([]))
            default:
                return (404, Data())
            }
        }

        let first = expectation(description: "First telemetry result")
        let second = expectation(description: "Second telemetry result")
        fetcher.fetch(payload: payload) { _ in first.fulfill() }
        fetcher.fetch(payload: payload) { _ in second.fulfill() }

        wait(for: [first, second], timeout: 2)
        XCTAssertEqual(heartbeatCount, 2)
        XCTAssertEqual(liveCount, 2)
    }

    func testTelemetryFailureClearsPreviouslyPublishedSessions() {
        let service = EdgeDeferredService()
        let connector = PaperclipConnector(
            configuration: selectedConfiguration(),
            service: service
        )
        let live = AgentSessionSnapshot(
            id: "live",
            agentID: "agent-1",
            agentName: "Builder",
            agentStatus: "running",
            runState: .running
        )

        connector.refresh()
        service.finishCore(.success(coreState()))
        service.finishSessions(.success([live]))
        XCTAssertEqual(connector.agentSessions(limit: 8), [live])

        connector.refresh()
        service.finishCore(.success(coreState()))
        service.finishSessions(.failure(URLError(.timedOut)))
        XCTAssertTrue(connector.agentSessions(limit: 8).isEmpty)
    }

    func testLiveEndpointFailureRetainsRecentRunWithoutLiveClaim() {
        let service = makeService()
        EdgeStubURLProtocol.handler = { request in
            switch request.url?.path {
            case "/api/companies/company-1/heartbeat-runs":
                return (200, self.json([[
                    "id": "recent-running",
                    "agentId": "agent-1",
                    "status": "running",
                    "startedAt": "2026-10-07T18:00:00.000Z",
                    "createdAt": "2026-10-07T18:00:00.000Z",
                    "updatedAt": "2026-10-07T18:30:00.000Z"
                ]]))
            case "/api/companies/company-1/live-runs":
                return (503, Data("{}".utf8))
            default:
                return self.coreResponse(for: request.url?.path)
            }
        }

        let sessionExpectation = expectation(description: "Unconfirmed recent session")
        service.fetch(
            configuration: selectedConfiguration(),
            completion: { _ in },
            sessionCompletion: { result in
                guard case let .success(sessions) = result else {
                    XCTFail("Expected recent telemetry to survive live endpoint failure")
                    sessionExpectation.fulfill()
                    return
                }
                XCTAssertEqual(sessions.first?.runID, "recent-running")
                XCTAssertEqual(sessions.first?.runState, .unknown)
                XCTAssertFalse(sessions.first?.isActive ?? true)
                sessionExpectation.fulfill()
            }
        )
        wait(for: [sessionExpectation], timeout: 2)
    }

    func testHistoricalRunningRunIsNotLiveWhenLiveEndpointIsEmpty() {
        let service = makeService()
        EdgeStubURLProtocol.handler = { request in
            switch request.url?.path {
            case "/api/companies/company-1/heartbeat-runs":
                return (200, self.json([[
                    "id": "finished-between-requests",
                    "agentId": "agent-1",
                    "status": "running",
                    "startedAt": "2026-10-07T18:00:00.000Z",
                    "createdAt": "2026-10-07T18:00:00.000Z",
                    "updatedAt": "2026-10-07T18:30:00.000Z"
                ]]))
            case "/api/companies/company-1/live-runs":
                return (200, self.json([]))
            default:
                return self.coreResponse(for: request.url?.path)
            }
        }

        let sessionExpectation = expectation(description: "Confirmed session state")
        service.fetch(
            configuration: selectedConfiguration(),
            completion: { _ in },
            sessionCompletion: { result in
                guard case let .success(sessions) = result else {
                    XCTFail("Expected telemetry success")
                    sessionExpectation.fulfill()
                    return
                }
                XCTAssertEqual(sessions.first?.runID, "finished-between-requests")
                XCTAssertEqual(sessions.first?.runState, .unknown)
                XCTAssertFalse(sessions.first?.isActive ?? true)
                sessionExpectation.fulfill()
            }
        )
        wait(for: [sessionExpectation], timeout: 2)
    }

    private func selectedConfiguration() -> PaperclipConfiguration {
        PaperclipConfiguration(
            baseURLString: "https://paperclip.example",
            companyID: "company-1"
        )
    }

    private func coreState() -> PaperclipRemoteState {
        PaperclipRemoteState(
            companies: [PaperclipCompany(id: "company-1", name: "Example Co", status: "active")],
            companyID: "company-1",
            companyName: "Example Co",
            activity: [],
            approvals: [],
            usage: nil,
            agentSessions: []
        )
    }

    private func telemetryPayload() -> PaperclipFetchPayload {
        let company = PaperclipCompany(id: "company-1", name: "Example Co", status: "active")
        return PaperclipFetchPayload(
            context: PaperclipFetchContext(
                baseURL: URL(string: "https://paperclip.example")!,
                companies: [company],
                company: company
            ),
            dashboard: PaperclipDashboardResponse(
                costs: PaperclipDashboardResponse.Costs(
                    monthSpendCents: 0,
                    monthBudgetCents: 0
                )
            ),
            agents: [],
            issues: [],
            approvals: []
        )
    }

    private func makeService() -> URLSessionPaperclipService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [EdgeStubURLProtocol.self]
        return URLSessionPaperclipService(session: URLSession(configuration: configuration))
    }

    private func coreResponse(for path: String?) -> (Int, Data) {
        switch path {
        case "/api/health":
            return (200, json(["status": "ok"]))
        case "/api/companies":
            return (200, json([["id": "company-1", "name": "Example Co", "status": "active"]]))
        case "/api/companies/company-1/dashboard":
            return (200, json(["costs": ["monthSpendCents": 0, "monthBudgetCents": 0]]))
        case "/api/companies/company-1/agents":
            return (200, json([[
                "id": "agent-1",
                "name": "Builder",
                "status": "running",
                "updatedAt": "2026-10-07T18:00:00.000Z"
            ]]))
        case "/api/companies/company-1/issues":
            return (200, json([]))
        case "/api/companies/company-1/approvals":
            return (200, json([]))
        default:
            return (404, Data())
        }
    }

    private func json(_ object: Any) -> Data {
        (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
    }
}
