import Foundation
import PixelCompanionCore
@testable import PixelCompanion
import XCTest

final class LivePresentationTests: XCTestCase {

    func testApprovalPresentationLimitsPreviewButNotDetail() {
        let approvals = (1...3).map { index in
            ApprovalRequest(
                id: "approval-\(index)",
                title: "Approval \(index)",
                requestedAt: Date(timeIntervalSince1970: Double(index))
            )
        }

        XCTAssertEqual(ApprovalPresentation.visible(approvals, limit: 2), Array(approvals.prefix(2)))
        XCTAssertTrue(ApprovalPresentation.visible(approvals, limit: 0).isEmpty)
        XCTAssertEqual(ApprovalPresentation.visible(approvals, limit: nil), approvals)
    }

    func testSnapshotPrimaryPrefersActiveSessionWithoutStackingActivity() {
        let activity = ActivityEvent(
            id: "activity",
            kind: .running,
            title: "Current activity",
            timestamp: Date(timeIntervalSince1970: 10)
        )
        let active = makeAgentSession(
            id: "active",
            name: "Builder",
            state: .running,
            agentStatus: "running"
        )
        let recent = makeAgentSession(
            id: "recent",
            name: "Recent",
            state: .completed,
            agentStatus: "idle"
        )

        XCTAssertEqual(
            AgentSessionPresentation.snapshotPrimary(activity: activity, sessions: [recent, active]),
            .session(active)
        )
        XCTAssertEqual(
            AgentSessionPresentation.snapshotPrimary(activity: activity, sessions: [recent]),
            .activity(activity)
        )
        XCTAssertEqual(
            AgentSessionPresentation.snapshotPrimary(activity: nil, sessions: [recent]),
            .session(recent)
        )
    }

    func testAgentSessionPresentationPrefersActiveSession() {
        let recent = makeAgentSession(
            id: "recent",
            name: "Recent",
            state: .completed,
            agentStatus: "idle"
        )
        let active = makeAgentSession(
            id: "active",
            name: "Builder",
            state: .running,
            agentStatus: "running"
        )

        XCTAssertEqual(AgentSessionPresentation.primary([recent, active]), active)
        XCTAssertEqual(AgentSessionPresentation.sectionTitle([recent, active]), "Agent sessions")
        XCTAssertEqual(AgentSessionPresentation.stateLabel(active), "Live")
    }

    func testAgentSessionPresentationFormatsRuntimeAndTokens() {
        let session = AgentSessionSnapshot(
            id: "agent-1",
            agentID: "agent-1",
            agentName: "Builder",
            agentStatus: "idle",
            runState: .completed,
            model: "gpt-5.6-sol",
            provider: "openai",
            sessionID: "01a1159b-b36a-7fa1-a102-aa1988d6dfc7",
            inputTokens: 1_250,
            cachedInputTokens: 2_500_000,
            outputTokens: 250
        )

        XCTAssertEqual(AgentSessionPresentation.runtimeLabel(session), "openai · gpt-5.6-sol")
        XCTAssertEqual(AgentSessionPresentation.identityLabel(session), "Session 01a1159b…")
        XCTAssertEqual(AgentSessionPresentation.tokenLabel(session), "1.2K in · 2.5M cached · 250 out")
        XCTAssertEqual(AgentSessionPresentation.sectionTitle([session]), "Recent agent sessions")
    }

    func testAgentSessionUnknownStateUsesAgentStatusWithoutInventingLiveState() {
        let session = makeAgentSession(
            id: "unknown",
            name: "Builder",
            state: .unknown,
            agentStatus: "waiting_for_task"
        )

        XCTAssertEqual(AgentSessionPresentation.stateLabel(session), "Waiting For Task")
        XCTAssertFalse(session.isActive)
    }

    func testAgentSessionPresentationClampsNegativeTokenCounts() {
        let session = AgentSessionSnapshot(
            id: "negative",
            agentID: "negative",
            agentName: "Agent",
            agentStatus: "idle",
            runState: .completed,
            inputTokens: -1,
            cachedInputTokens: -2,
            outputTokens: -3
        )

        XCTAssertEqual(AgentSessionPresentation.tokenLabel(session), "0 in · 0 cached · 0 out")
    }

    func testApprovalCountAndTimestampPolicies() {
        let recent = ApprovalRequest(
            id: "approval-1",
            title: "Ship release",
            requestedAt: Date(timeIntervalSince1970: 10_000)
        )
        let unknown = ApprovalRequest(
            id: "approval-2",
            title: "Unknown time",
            requestedAt: .distantPast
        )

        XCTAssertEqual(ApprovalPresentation.countLabel(1), "1 pending approval")
        XCTAssertEqual(ApprovalPresentation.countLabel(3), "3 pending approvals")
        XCTAssertEqual(
            ApprovalPresentation.accessibilityContext(recent),
            "Waiting for approval: Ship release"
        )
        XCTAssertEqual(
            ApprovalPresentation.accessibilityContext(unknown),
            "Waiting for approval: Unknown time"
        )
        XCTAssertTrue(ApprovalPresentation.showsTimestamp(recent))
        XCTAssertFalse(ApprovalPresentation.showsTimestamp(unknown))
    }

    func testHistoryRemovesCurrentActivityByID() {
        let now = ActivityEvent(
            id: "current",
            kind: .running,
            title: "Current",
            timestamp: Date(timeIntervalSince1970: 20)
        )
        let older = ActivityEvent(
            id: "older",
            kind: .completed,
            title: "Older",
            timestamp: Date(timeIntervalSince1970: 10)
        )

        XCTAssertEqual(
            ActivityPresentation.history([now, older], currentActivity: now),
            [older]
        )
    }

    func testHistoryRemovesOnlyHighlightedDuplicateOccurrence() {
        let current = ActivityEvent(
            id: "duplicate",
            kind: .running,
            title: "Current",
            timestamp: Date(timeIntervalSince1970: 20)
        )
        let duplicate = ActivityEvent(
            id: "duplicate",
            kind: .running,
            title: "Another agent event",
            timestamp: Date(timeIntervalSince1970: 19)
        )

        XCTAssertEqual(
            ActivityPresentation.history([current, duplicate], currentActivity: current),
            [duplicate]
        )
    }

    func testHistoryKeepsAllEventsWhenThereIsNoCurrentActivity() {
        let event = ActivityEvent(
            id: "one",
            kind: .note,
            title: "One",
            timestamp: Date(timeIntervalSince1970: 1)
        )

        XCTAssertEqual(ActivityPresentation.history([event], currentActivity: nil), [event])
    }

    func testUsagePresentationFormatsCentsAsUSD() {
        XCTAssertEqual(
            UsagePresentation.amount(
                UsageSnapshot(used: 1234, limit: 5000, unit: "cents", periodLabel: "This month")
            ),
            "$12.34 / $50.00"
        )
    }

    func testUsagePresentationPreservesGenericUnits() {
        XCTAssertEqual(
            UsagePresentation.amount(
                UsageSnapshot(used: 42, limit: 100, unit: "tokens", periodLabel: "Session")
            ),
            "42 / 100 tokens"
        )
    }
}

private func makeAgentSession(
    id: String,
    name: String,
    state: AgentSessionSnapshot.RunState,
    agentStatus: String
) -> AgentSessionSnapshot {
    AgentSessionSnapshot(
        id: id,
        agentID: id,
        agentName: name,
        agentStatus: agentStatus,
        runState: state
    )
}
