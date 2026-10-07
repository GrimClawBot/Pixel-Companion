import Foundation
@testable import PixelCompanionCore
import XCTest

private final class TelemetryStubURLProtocol: URLProtocol {
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

private final class TelemetryDeferredService: PaperclipServiceProtocol {
    private(set) var fetchCount = 0
    private var coreCompletion: ((Result<PaperclipRemoteState, Error>) -> Void)?

    func fetch(
        configuration: PaperclipConfiguration,
        completion: @escaping (Result<PaperclipRemoteState, Error>) -> Void,
        sessionCompletion: @escaping (Result<[AgentSessionSnapshot], Error>) -> Void
    ) {
        fetchCount += 1
        coreCompletion = completion
    }

    func finishCore(_ result: Result<PaperclipRemoteState, Error>) {
        let completion = coreCompletion
        coreCompletion = nil
        completion?(result)
    }
}

final class PaperclipTelemetryTests: XCTestCase {
    override func tearDown() {
        TelemetryStubURLProtocol.handler = nil
        super.tearDown()
    }

    func testCoreRefreshReleasesPollingBeforeSessionEnrichment() {
        let service = TelemetryDeferredService()
        let connector = PaperclipConnector(
            configuration: selectedConfiguration(),
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
        XCTAssertEqual(service.fetchCount, 2)
    }

    func testLiveRunsRestoreActiveSessionOutsideRecentWindow() {
        let service = makeService()
        TelemetryStubURLProtocol.handler = { request in
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
                return self.coreResponse(for: request.url?.path)
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
        TelemetryStubURLProtocol.handler = { request in
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
                return self.coreResponse(for: request.url?.path)
            }
        }

        let sessionExpectation = expectation(description: "Lossy session enrichment")
        service.fetch(
            configuration: selectedConfiguration(),
            completion: { _ in },
            sessionCompletion: { result in
                guard case let .success(sessions) = result else {
                    XCTFail("Expected valid runs to survive one malformed record")
                    sessionExpectation.fulfill()
                    return
                }
                XCTAssertEqual(sessions.first?.runID, "good-run")
                sessionExpectation.fulfill()
            }
        )
        wait(for: [sessionExpectation], timeout: 2)
    }

    func testTelemetryFailureDoesNotBlockCoreSuccess() {
        let service = makeService()
        TelemetryStubURLProtocol.handler = { request in
            if request.url?.path.hasSuffix("/heartbeat-runs") == true
                || request.url?.path.hasSuffix("/live-runs") == true {
                return (403, Data("{}".utf8))
            }
            return self.coreResponse(for: request.url?.path)
        }

        let coreExpectation = expectation(description: "Core state")
        let telemetryExpectation = expectation(description: "Telemetry failure")
        service.fetch(
            configuration: selectedConfiguration(),
            completion: { result in
                guard case let .success(state) = result else {
                    XCTFail("Expected core success")
                    coreExpectation.fulfill()
                    return
                }
                XCTAssertEqual(state.companyName, "Example Co")
                XCTAssertTrue(state.agentSessions.isEmpty)
                coreExpectation.fulfill()
            },
            sessionCompletion: { result in
                guard case .failure = result else {
                    XCTFail("Expected optional telemetry failure")
                    telemetryExpectation.fulfill()
                    return
                }
                telemetryExpectation.fulfill()
            }
        )
        wait(for: [coreExpectation, telemetryExpectation], timeout: 2)
    }

    private func selectedConfiguration() -> PaperclipConfiguration {
        PaperclipConfiguration(
            baseURLString: "https://paperclip.example",
            companyID: "company-1"
        )
    }

    private func makeService() -> URLSessionPaperclipService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TelemetryStubURLProtocol.self]
        return URLSessionPaperclipService(session: URLSession(configuration: configuration))
    }

    private func coreResponse(for path: String?) -> (Int, Data) {
        switch path {
        case "/api/health":
            return (200, json(["status": "ok"]))
        case "/api/companies":
            return (200, json([["id": "company-1", "name": "Example Co", "status": "active"]]))
        case "/api/companies/company-1/dashboard":
            return (200, json(["costs": ["monthSpendCents": 125, "monthBudgetCents": 1000]]))
        case "/api/companies/company-1/agents":
            return (200, json([[
                "id": "agent-1",
                "name": "Builder",
                "status": "running",
                "adapterConfig": ["model": "gpt-5.6-sol"],
                "runtimeConfig": ["aiConnection": ["provider": "openai"]],
                "updatedAt": "2026-10-07T18:00:00.000Z"
            ]]))
        case "/api/companies/company-1/issues":
            return (200, json([[
                "id": "issue-1",
                "identifier": "EX-1",
                "title": "Build native connector",
                "status": "in_progress",
                "assigneeAgentId": "agent-1"
            ]]))
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
