import Foundation
@testable import PixelCompanionCore
import XCTest

final class PaperclipMappingTests: XCTestCase {
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
        let service = DeferredPaperclipMappingService()
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
}

private final class DeferredPaperclipMappingService: PaperclipServiceProtocol {
    private var completion: ((Result<PaperclipRemoteState, Error>) -> Void)?

    func fetch(
        configuration: PaperclipConfiguration,
        completion: @escaping (Result<PaperclipRemoteState, Error>) -> Void
    ) {
        self.completion = completion
    }

    func finish(_ result: Result<PaperclipRemoteState, Error>) {
        completion?(result)
        completion = nil
    }
}
