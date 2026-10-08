import PixelCompanionCore
@testable import PixelCompanion
import XCTest

final class LiveOperationsPulseTests: XCTestCase {
    private func agent(
        _ id: String, _ state: AgentSessionSnapshot.RunState
    ) -> AgentSessionSnapshot {
        AgentSessionSnapshot(
            id: "summary-\(id)", agentID: id, agentName: id,
            agentStatus: state.rawValue, runState: state
        )
    }

    func testRunCategoriesAreBasedOnlyOnConfirmedLatestState() {
        let sessions: [AgentSessionSnapshot] = [
            agent("run", .running), agent("queue", .queued), agent("fail", .failed),
            agent("done", .completed), agent("idle", .idle),
            agent("cancel", .cancelled), agent("unknown", .unknown)
        ]
        let value = OperationsPulse(sessions: sessions, pendingApprovalCount: 4, isLive: true)
        XCTAssertEqual(value.count(.running), 1)
        XCTAssertEqual(value.count(.queued), 1)
        XCTAssertEqual(value.count(.failed), 1)
        XCTAssertTrue(value.hasReportedWork)
        XCTAssertEqual(value.companyWideApprovals, 4)
        XCTAssertEqual(value.preview(.running).map(\.agentID), ["run"])
        XCTAssertEqual(value.preview(.queued).map(\.agentID), ["queue"])
        XCTAssertEqual(value.preview(.failed).map(\.agentID), ["fail"])
    }

    func testBoundedRowsRetainConnectorOrderingAndRealAgentIds() {
        let agents = [
            agent("first", .running),
            agent("idle", .idle),
            agent("second", .running),
            agent("third", .running)
        ]
        let pulse = OperationsPulse(sessions: agents, pendingApprovalCount: 0, isLive: true)
        XCTAssertEqual(pulse.count(.running), 3)
        XCTAssertEqual(pulse.preview(.running).map(\.agentID), ["first", "second"])
        XCTAssertEqual(pulse.companyWideApprovals, 0)
    }

    func testUnavailableStateHidesAgentAndApprovalCountsEvenIfCached() {
        let cached = [
            agent("run", .running), agent("queue", .queued), agent("fail", .failed)
        ]
        let pulse = OperationsPulse(sessions: cached, pendingApprovalCount: 5, isLive: false)
        for category in OperationsPulseCategory.allCases {
            XCTAssertNil(pulse.count(category))
            XCTAssertTrue(pulse.preview(category).isEmpty)
        }
        XCTAssertNil(pulse.companyWideApprovals)
        XCTAssertFalse(pulse.hasReportedWork)
    }

    func testApprovalsNeverImplyAgentIsFailedOrRunning() {
        let pulse = OperationsPulse(
            sessions: [agent("known", .unknown), agent("done", .completed)],
            pendingApprovalCount: 3, isLive: true
        )
        XCTAssertEqual(pulse.companyWideApprovals, 3)
        XCTAssertEqual(pulse.count(.running), 0)
        XCTAssertEqual(pulse.count(.queued), 0)
        XCTAssertEqual(pulse.count(.failed), 0)
        XCTAssertFalse(pulse.hasReportedWork)
    }

    func testZeroAndNegativeApprovalsDoNotProduceActionableCount() {
        let empty = OperationsPulse(sessions: [], pendingApprovalCount: 0, isLive: true)
        XCTAssertEqual(empty.companyWideApprovals, 0)
        XCTAssertFalse(empty.hasReportedWork)
        let malformed = OperationsPulse(
            sessions: [], pendingApprovalCount: -6, isLive: true
        )
        XCTAssertEqual(malformed.companyWideApprovals, 0)
    }
}
