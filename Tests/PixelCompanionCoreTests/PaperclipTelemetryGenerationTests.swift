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
