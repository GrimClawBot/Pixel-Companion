import Foundation
@testable import PixelCompanionCore
import XCTest

private final class GenerationDeferredService: PaperclipServiceProtocol {
    private(set) var fetchCount = 0
    private var coreCompletions: [Int: (Result<PaperclipRemoteState, Error>) -> Void] = [:]
    private var sessionCompletions: [Int: (Result<[AgentSessionSnapshot], Error>) -> Void] = [:]

    func fetch(
        configuration: PaperclipConfiguration,
        completion: @escaping (Result<PaperclipRemoteState, Error>) -> Void,
        sessionCompletion: @escaping (Result<[AgentSessionSnapshot], Error>) -> Void
    ) {
        fetchCount += 1
        coreCompletions[fetchCount] = completion
        sessionCompletions[fetchCount] = sessionCompletion
    }

    func finishCore(
        _ result: Result<PaperclipRemoteState, Error>,
        fetch: Int = 1
    ) {
        coreCompletions.removeValue(forKey: fetch)?(result)
    }

    func finishSessions(
        _ result: Result<[AgentSessionSnapshot], Error>,
        fetch: Int
    ) {
        sessionCompletions.removeValue(forKey: fetch)?(result)
    }
}

final class PaperclipTelemetryGenerationTests: XCTestCase {
    func testCoreRefreshReleasesPollingBeforeSessionEnrichment() {
        let service = GenerationDeferredService()
        let connector = PaperclipConnector(
            configuration: selectedConfiguration(),
            service: service
        )

        connector.refresh()
        service.finishCore(.success(coreState()))

        XCTAssertEqual(connector.connectionState, .connected)
        connector.refresh()
        XCTAssertEqual(service.fetchCount, 2)
    }

    func testTelemetryRemainsUsableUntilNewerCorePublishesThenOldResultIsRejected() {
        let service = GenerationDeferredService()
        let connector = PaperclipConnector(
            configuration: selectedConfiguration(),
            service: service
        )
        let core = coreState()
        let first = session(id: "first")
        let stale = session(id: "stale")
        let current = session(id: "current")

        connector.refresh()
        service.finishCore(.success(core), fetch: 1)

        connector.refresh()
        service.finishSessions(.success([first]), fetch: 1)
        XCTAssertEqual(connector.agentSessions(limit: 8), [first])

        service.finishCore(.success(core), fetch: 2)
        service.finishSessions(.success([stale]), fetch: 1)
        XCTAssertEqual(connector.agentSessions(limit: 8), [first])

        service.finishSessions(.success([current]), fetch: 2)
        XCTAssertEqual(connector.agentSessions(limit: 8), [current])
    }

    func testOlderTelemetryCannotReturnAfterNewerCoreFailure() {
        let service = GenerationDeferredService()
        let connector = PaperclipConnector(
            configuration: selectedConfiguration(),
            service: service
        )
        let core = coreState()
        let stale = session(id: "stale")

        connector.refresh()
        service.finishCore(.success(core), fetch: 1)

        connector.refresh()
        service.finishCore(.failure(URLError(.timedOut)), fetch: 2)
        XCTAssertTrue(connector.agentSessions(limit: 8).isEmpty)
        XCTAssertEqual(connector.connectionState, .error)

        service.finishSessions(.success([stale]), fetch: 1)
        XCTAssertTrue(connector.agentSessions(limit: 8).isEmpty)
        XCTAssertEqual(connector.connectionState, .error)
    }

    func testSlowSessionsRemainEligibleAfterNewerCorePublishesForSameCompany() {
        let service = GenerationDeferredService()
        let connector = PaperclipConnector(
            configuration: selectedConfiguration(), service: service
        )
        let slow = session(id: "slow-but-valid")
        let latest = session(id: "newer")

        connector.refresh()
        service.finishCore(.success(coreState()), fetch: 1)
        let firstCoreTime = connector.lastSuccessfulRefreshAt
        XCTAssertNotNil(firstCoreTime)
        XCTAssertNil(connector.lastSuccessfulSessionRefreshAt)

        connector.refresh()
        service.finishCore(.success(coreState()), fetch: 2)
        XCTAssertNil(connector.lastSuccessfulSessionRefreshAt)

        // Older core generation does not make the response untrustworthy
        // if this company has not yet published more recent session evidence.
        service.finishSessions(.success([slow]), fetch: 1)
        XCTAssertEqual(connector.agentSessions(limit: 10), [slow])
        XCTAssertEqual(connector.lastSuccessfulSessionRefreshAt, firstCoreTime)

        service.finishSessions(.success([latest]), fetch: 2)
        XCTAssertEqual(connector.agentSessions(limit: 10), [latest])
        XCTAssertEqual(
            connector.lastSuccessfulSessionRefreshAt,
            connector.lastSuccessfulRefreshAt
        )
    }

    func testOlderDelayedSessionCannotOverrideNewerCompletedSession() {
        let service = GenerationDeferredService()
        let connector = PaperclipConnector(
            configuration: selectedConfiguration(), service: service
        )
        connector.refresh()
        service.finishCore(.success(coreState()), fetch: 1)
        connector.refresh()
        service.finishCore(.success(coreState()), fetch: 2)
        let current = session(id: "current")
        service.finishSessions(.success([current]), fetch: 2)
        let latestTime = connector.lastSuccessfulSessionRefreshAt
        service.finishSessions(.success([session(id: "old")]), fetch: 1)
        XCTAssertEqual(connector.agentSessions(limit: 8), [current])
        XCTAssertEqual(connector.lastSuccessfulSessionRefreshAt, latestTime)
    }

    func testSlowPreviousCompanyCannotBecomeNewCompanyTelemetry() {
        let service = GenerationDeferredService()
        let connector = PaperclipConnector(
            configuration: selectedConfiguration(), service: service
        )
        connector.refresh()
        service.finishCore(.success(coreState()), fetch: 1)
        connector.refresh()
        service.finishCore(.success(coreState(companyID: "company-2")), fetch: 2)
        XCTAssertNil(connector.lastSuccessfulSessionRefreshAt)
        service.finishSessions(.success([session(id: "wrong-company")]), fetch: 1)
        XCTAssertTrue(connector.agentSessions(limit: 8).isEmpty)
        XCTAssertNil(connector.lastSuccessfulSessionRefreshAt)
        let current = session(id: "company-2-worker")
        service.finishSessions(.success([current]), fetch: 2)
        XCTAssertEqual(connector.agentSessions(limit: 8), [current])
        XCTAssertNotNil(connector.lastSuccessfulSessionRefreshAt)
    }

    func testCoreHealthNeverRefreshesSuccessfulAgentSessionTimestamp() {
        let service = GenerationDeferredService()
        let connector = PaperclipConnector(
            configuration: selectedConfiguration(), service: service
        )
        connector.refresh()
        service.finishCore(.success(coreState()), fetch: 1)
        service.finishSessions(.success([session(id: "worker")]), fetch: 1)
        let first = connector.lastSuccessfulSessionRefreshAt
        XCTAssertNotNil(first)
        connector.refresh()
        service.finishCore(.success(coreState()), fetch: 2)
        XCTAssertEqual(connector.lastSuccessfulSessionRefreshAt, first)
        service.finishSessions(.failure(URLError(.timedOut)), fetch: 2)
        XCTAssertNil(connector.lastSuccessfulSessionRefreshAt)
        XCTAssertTrue(connector.agentSessions(limit: 8).isEmpty)
        XCTAssertEqual(connector.connectionState, .connected)
    }

    func testAtomicPresentationCaptureKeepsSessionRowsAndEvidenceTogether() {
        let service = GenerationDeferredService()
        let connector = PaperclipConnector(
            configuration: selectedConfiguration(), service: service
        )
        connector.refresh()
        service.finishCore(.success(coreState()), fetch: 1)
        let before = connector.capturePresentation()
        XCTAssertEqual(before.snapshot.connectionState, .connected)
        XCTAssertNil(before.sessionsAt)
        XCTAssertTrue(before.snapshot.agentSessions.isEmpty)

        service.finishSessions(.success([session(id: "first")]), fetch: 1)
        let first = connector.capturePresentation()
        XCTAssertEqual(first.snapshot.agentSessions.map(\.agentID), ["first"])
        XCTAssertEqual(first.sessionsAt, first.coreAt)

        connector.refresh()
        service.finishCore(.success(coreState()), fetch: 2)
        let prior = connector.capturePresentation()
        XCTAssertEqual(prior.snapshot.agentSessions.map(\.agentID), ["first"])
        XCTAssertEqual(prior.sessionsAt, first.sessionsAt)

        service.finishSessions(.success([session(id: "second")]), fetch: 2)
        let second = connector.capturePresentation()
        XCTAssertEqual(second.snapshot.agentSessions.map(\.agentID), ["second"])
        XCTAssertEqual(second.sessionsAt, second.coreAt)
    }

    func testFullDirectoryCanCapturePastOldEightAnd128Limits() {
        let service = GenerationDeferredService()
        let connector = PaperclipConnector(
            configuration: selectedConfiguration(), service: service
        )
        let agents = (0..<181).map { session(id: "agent-\($0)") }
        connector.refresh()
        service.finishCore(.success(coreState()), fetch: 1)
        service.finishSessions(.success(agents), fetch: 1)
        XCTAssertEqual(
            ConnectorSnapshot(capturing: connector, sessionLimit: Int.max)
                .agentSessions.count,
            181
        )
        XCTAssertEqual(connector.agentSessions(limit: Int.max).last?.agentID, "agent-180")
        XCTAssertEqual(
            ConnectorSnapshot(capturing: connector).agentSessions.count, 8,
            "Small previews must explicitly remain separate from the full UI directory"
        )
    }

    private func selectedConfiguration() -> PaperclipConfiguration {
        PaperclipConfiguration(
            baseURLString: "https://paperclip.example",
            companyID: "company-1"
        )
    }

    private func coreState(companyID: String = "company-1") -> PaperclipRemoteState {
        PaperclipRemoteState(
            companies: [PaperclipCompany(id: companyID, name: "Example Co", status: "active")],
            companyID: companyID,
            companyName: "Example Co",
            activity: [],
            approvals: [],
            usage: nil,
            agentSessions: []
        )
    }

    private func session(id: String) -> AgentSessionSnapshot {
        AgentSessionSnapshot(
            id: id,
            agentID: id,
            agentName: id.capitalized,
            agentStatus: "running",
            runState: .running
        )
    }
}
