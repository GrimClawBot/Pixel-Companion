import Foundation
@testable import PixelCompanionCore
import XCTest

final class PaperclipMappingTests: XCTestCase {
    func testDuplicateAgentIDsDoNotCrashMapper() {
        let state = PaperclipMapper.map(makeDuplicateAgentInput())

        XCTAssertEqual(state.activity.first?.detail, "EX-1 · in progress · Current Name")
        XCTAssertEqual(state.agentSessions.count, 1)
        XCTAssertEqual(state.agentSessions.first?.agentName, "Current Name")
    }

    func testAgentSessionsPreferActiveRunAndMapSafeTelemetry() throws {
        let state = PaperclipMapper.map(makeSessionMappingInput())
        let session = try XCTUnwrap(state.agentSessions.first)

        XCTAssertEqual(session.runID, "active-run")
        XCTAssertEqual(session.runState, .running)
        XCTAssertEqual(session.taskTitle, "EX-1 · Build session UI")
        XCTAssertEqual(session.model, "gpt-5.6-sol")
        XCTAssertEqual(session.provider, "openai")
        XCTAssertEqual(session.sessionID, "session-1")
        XCTAssertEqual(session.inputTokens, 1200)
        XCTAssertEqual(session.cachedInputTokens, 800)
        XCTAssertEqual(session.outputTokens, 250)
        XCTAssertTrue(session.isActive)
    }

    func testAgentWithoutRunIsNeverInventedAsLive() {
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
                    name: "Builder",
                    role: "engineer",
                    title: "Engineer",
                    status: "running",
                    adapterType: "codex_local",
                    adapterConfig: .init(model: "gpt-5.6-sol"),
                    runtimeConfig: .init(aiConnection: .init(provider: "openai")),
                    lastHeartbeatAt: nil,
                    updatedAt: "2026-10-07T18:00:00.000Z"
                )
            ],
            issues: [],
            approvals: [],
            runs: []
        )

        let session = PaperclipMapper.map(input).agentSessions.first

        XCTAssertEqual(session?.runState, .unknown)
        XCTAssertFalse(session?.isActive ?? true)
        XCTAssertEqual(session?.model, "gpt-5.6-sol")
        XCTAssertEqual(session?.provider, "openai")
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
            usage: nil,
            agentSessions: []
        )))

        XCTAssertEqual(connector.currentActivity, newestFailure)
    }
}

private func makeDuplicateAgentInput() -> PaperclipMappingInput {
    let company = PaperclipCompany(id: "company-1", name: "Example Co", status: "active")
    return PaperclipMappingInput(
        companies: [company],
        company: company,
        dashboard: PaperclipDashboardResponse(
            costs: PaperclipDashboardResponse.Costs(monthSpendCents: 0, monthBudgetCents: 0)
        ),
        agents: [
            PaperclipAgentResponse(
                id: "agent-1",
                name: "Old Name",
                role: nil,
                title: nil,
                status: "idle",
                adapterType: nil,
                adapterConfig: nil,
                runtimeConfig: nil,
                lastHeartbeatAt: nil,
                updatedAt: "2026-10-07T17:00:00.000Z"
            ),
            PaperclipAgentResponse(
                id: "agent-1",
                name: "Current Name",
                role: nil,
                title: nil,
                status: "idle",
                adapterType: nil,
                adapterConfig: nil,
                runtimeConfig: nil,
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
        approvals: [],
        runs: []
    )
}

private func makeSessionMappingInput() -> PaperclipMappingInput {
    let company = PaperclipCompany(id: "company-1", name: "Example Co", status: "active")
    return PaperclipMappingInput(
        companies: [company],
        company: company,
        dashboard: PaperclipDashboardResponse(
            costs: PaperclipDashboardResponse.Costs(monthSpendCents: 0, monthBudgetCents: 0)
        ),
        agents: [makeSessionAgent()],
        issues: [makeSessionIssue()],
        approvals: [],
        runs: makeSessionRuns()
    )
}

private func makeSessionAgent() -> PaperclipAgentResponse {
    PaperclipAgentResponse(
        id: "agent-1",
        name: "Builder",
        role: "engineer",
        title: "Senior Engineer",
        status: "idle",
        adapterType: "codex_local",
        adapterConfig: .init(model: "fallback-model"),
        runtimeConfig: .init(aiConnection: .init(provider: "fallback-provider")),
        lastHeartbeatAt: "2026-10-07T18:00:00.000Z",
        updatedAt: "2026-10-07T18:00:00.000Z"
    )
}

private func makeSessionIssue() -> PaperclipIssueResponse {
    PaperclipIssueResponse(
        id: "issue-1",
        identifier: "EX-1",
        title: "Build session UI",
        status: "in_progress",
        assigneeAgentId: "agent-1",
        lastActivityAt: nil,
        updatedAt: nil,
        createdAt: nil
    )
}

private func makeSessionRuns() -> [PaperclipHeartbeatRunResponse] {
    [
        PaperclipHeartbeatRunResponse(
            id: "recent-failed",
            agentId: "agent-1",
            status: "failed",
            startedAt: "2026-10-07T18:20:00.000Z",
            finishedAt: "2026-10-07T18:21:00.000Z",
            createdAt: "2026-10-07T18:20:00.000Z",
            updatedAt: "2026-10-07T18:21:00.000Z",
            usageJson: nil,
            sessionIdBefore: nil,
            sessionIdAfter: nil,
            contextSnapshot: .init(issueId: "issue-1", taskId: "issue-1")
        ),
        PaperclipHeartbeatRunResponse(
            id: "active-run",
            agentId: "agent-1",
            status: "running",
            startedAt: "2026-10-07T18:10:00.000Z",
            finishedAt: nil,
            createdAt: "2026-10-07T18:10:00.000Z",
            updatedAt: "2026-10-07T18:19:00.000Z",
            usageJson: .init(
                model: "gpt-5.6-sol",
                provider: "openai",
                inputTokens: 1200,
                cachedInputTokens: 800,
                outputTokens: 250,
                persistedSessionId: "session-1"
            ),
            sessionIdBefore: nil,
            sessionIdAfter: "session-1",
            contextSnapshot: .init(issueId: "issue-1", taskId: "issue-1")
        )
    ]
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
