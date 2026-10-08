import Foundation
@testable import PixelCompanion
@testable import PixelCompanionCore
import XCTest

/// A fully local URLSession boundary. It never reaches a real Paperclip server.
private final class NotificationFlowURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var responseStage = 0

    static func selectStage(_ value: Int) {
        lock.lock()
        responseStage = value
        lock.unlock()
    }

    private static func stage() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return responseStage
    }

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let stage = Self.stage()
        let data = Self.response(for: url.path, at: stage)
        guard let response = HTTPURLResponse(
            url: url, statusCode: 200, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    private static func response(for path: String, at stage: Int) -> Data {
        let firstRun: [String: Any] = [
            "id": "run-a", "agentId": "agent-a",
            "status": stage == 0 ? "running" : "succeeded",
            "createdAt": "2026-10-07T18:00:00.000Z",
            "updatedAt": "2026-10-07T18:01:00.000Z"
        ]
        let secondRun: [String: Any] = [
            "id": "run-b", "agentId": "agent-a",
            "status": stage == 2 ? "running" : "failed",
            "createdAt": "2026-10-07T19:00:00.000Z",
            "updatedAt": "2026-10-07T19:01:00.000Z"
        ]
        let runs = stage < 2 ? [firstRun] : [firstRun, secondRun]
        let pending: [[String: Any]] = [
            ["id": "existing", "title": "Never print title", "status": "pending"]
        ]
        let approvals = stage == 0 ? pending : pending + [
            ["id": "new", "title": "Private approval content", "status": "pending"]
        ]
        let value: Any
        switch path {
        case "/api/health":
            value = ["status": "ok"]
        case "/api/companies":
            value = [["id": "qa", "name": "QA Fixture Co", "status": "active"]]
        case "/api/companies/qa/dashboard":
            value = ["costs": ["monthSpendCents": 0, "monthBudgetCents": 0]]
        case "/api/companies/qa/agents":
            value = [["id": "agent-a", "name": "Sensitive agent name", "status": "idle"]]
        case "/api/companies/qa/issues":
            value = []
        case "/api/companies/qa/approvals":
            value = approvals
        case "/api/companies/qa/heartbeat-runs":
            value = runs
        case "/api/companies/qa/live-runs":
            value = stage == 0 ? [firstRun] : (stage == 2 ? [secondRun] : [])
        default:
            value = [:]
        }
        return (try? JSONSerialization.data(withJSONObject: value)) ?? Data("{}".utf8)
    }
}

@MainActor
final class PaperclipNotificationFlowTests: XCTestCase {
    private final class RecordingCenter: CompanionNoticeCenter {
        var notices: [CompanionNotice] = []
        func authorization() async -> CompanionAuthorization { .authorized }
        func requestPermission() async -> Bool { true }
        func deliver(_ notice: CompanionNotice) { notices.append(notice) }
        func submitTest() async throws {}
    }

    func testRealHTTPResponsePipelineToAutomaticNotifications() async throws {
        NotificationFlowURLProtocol.selectStage(0)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [NotificationFlowURLProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }

        let connector = PaperclipConnector(
            configuration: PaperclipConfiguration(
                baseURLString: "https://example.invalid", companyID: "qa"
            ),
            service: URLSessionPaperclipService(session: session)
        )
        let center = RecordingCenter()
        let name = "PixelCompanionHTTPFlow." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let manager = CompanionNotificationManager(
            defaults: defaults, center: center, isBundled: true, isQABuild: false
        )
        manager.setEnabled(true)
        for _ in 0..<100 where manager.permission != .ready {
            await Task.yield()
        }
        XCTAssertEqual(manager.permission, .ready)

        connector.refresh()
        let baseline = try await awaitSnapshot(connector, run: "run-a", state: .running, approvals: 1)
        manager.observe(baseline, isPaperclip: true)
        XCTAssertTrue(center.notices.isEmpty, "Old approvals and running baselines must be quiet")

        NotificationFlowURLProtocol.selectStage(1)
        connector.refresh()
        let completed = try await awaitSnapshot(connector, run: "run-a", state: .completed, approvals: 2)
        manager.observe(completed, isPaperclip: true)
        manager.observe(completed, isPaperclip: true)
        XCTAssertEqual(center.notices, [.approvals(1), .completedRuns(1)])

        NotificationFlowURLProtocol.selectStage(2)
        connector.refresh()
        let running = try await awaitSnapshot(connector, run: "run-b", state: .running, approvals: 2)
        manager.observe(running, isPaperclip: true)
        XCTAssertEqual(center.notices.count, 2)

        NotificationFlowURLProtocol.selectStage(3)
        connector.refresh()
        let failed = try await awaitSnapshot(connector, run: "run-b", state: .failed, approvals: 2)
        manager.observe(failed, isPaperclip: true)
        manager.observe(failed, isPaperclip: true)
        XCTAssertEqual(center.notices, [.approvals(1), .completedRuns(1), .failedRuns(1)])
        for notice in center.notices {
            XCTAssertFalse(notice.title.contains("Sensitive"))
            XCTAssertFalse(notice.body.contains("Private"))
        }
    }

    private func awaitSnapshot(
        _ connector: PaperclipConnector,
        run: String,
        state: AgentSessionSnapshot.RunState,
        approvals: Int
    ) async throws -> ConnectorSnapshot {
        for _ in 0..<160 {
            let snapshot = ConnectorSnapshot(capturing: connector, sessionLimit: 128)
            if snapshot.connectionState == .connected,
               snapshot.pendingApprovals.count == approvals,
               snapshot.agentSessions.contains(where: { $0.runID == run && $0.runState == state }) {
                return snapshot
            }
            try await Task.sleep(for: .milliseconds(25))
        }
        XCTFail("Local Paperclip fixture did not produce expected run state")
        return ConnectorSnapshot(capturing: connector, sessionLimit: 128)
    }
}
