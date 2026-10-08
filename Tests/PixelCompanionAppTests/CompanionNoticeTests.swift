import Foundation
import PixelCompanionCore
@testable import PixelCompanion
import XCTest

final class CompanionNoticeTests: XCTestCase {
    func testFirstSnapshotSuppressesExistingApprovalsAndRuns() {
        var detector = CompanionNoticeDetector()
        let initial = snapshot(
            approvals: ["old"],
            sessions: [session("a", run: "r1", state: .completed)]
        )
        XCTAssertEqual(detector.observe(initial), [])
        XCTAssertEqual(detector.observe(initial), [])
    }

    func testNewApprovalsAreAggregatedAndNeverReplayed() {
        var detector = CompanionNoticeDetector()
        XCTAssertEqual(detector.observe(snapshot(approvals: ["old"])), [])
        XCTAssertEqual(
            detector.observe(snapshot(approvals: ["old", "new1", "new2"])),
            [.approvals(2)]
        )
        XCTAssertEqual(detector.observe(snapshot(approvals: ["old", "new1", "new2"])), [])
        XCTAssertEqual(detector.observe(snapshot()), [])
        XCTAssertEqual(detector.observe(snapshot(approvals: ["new2"])), [])
    }

    func testDuplicatePendingApprovalIDsCountOnce() {
        var detector = CompanionNoticeDetector()
        XCTAssertEqual(detector.observe(snapshot(approvals: ["existing"])), [])
        XCTAssertEqual(
            detector.observe(snapshot(approvals: ["existing", "new", "new", "new"])),
            [.approvals(1)]
        )
    }

    func testOnlyObservedRunTransitionNotifies() {
        var detector = CompanionNoticeDetector()
        let running = session("a", run: "run1", state: .running)
        XCTAssertEqual(detector.observe(snapshot(sessions: [running])), [])
        let completed = session("a", run: "run1", state: .completed)
        XCTAssertEqual(detector.observe(snapshot(sessions: [completed])), [.completedRuns(1)])
        XCTAssertEqual(detector.observe(snapshot(sessions: [completed])), [])

        // An entirely different already-failed run must never be treated as a transition.
        let failed = session("a", run: "run2", state: .failed)
        XCTAssertEqual(detector.observe(snapshot(sessions: [failed])), [])
    }

    func testQueuedToFailedAndMultipleCompletions() {
        var detector = CompanionNoticeDetector()
        let started = [
            session("a", run: "ra", state: .queued),
            session("b", run: "rb", state: .running),
            session("c", run: "rc", state: .running)
        ]
        XCTAssertEqual(detector.observe(snapshot(sessions: started)), [])
        let finished = [
            session("a", run: "ra", state: .failed),
            session("b", run: "rb", state: .completed),
            session("c", run: "rc", state: .completed)
        ]
        XCTAssertEqual(
            detector.observe(snapshot(sessions: finished)),
            [.completedRuns(2), .failedRuns(1)]
        )
    }

    func testBriefUnknownOrMissingRunStillNotifiesOnceWhenConfirmedEnded() {
        var detector = CompanionNoticeDetector()
        let running = session("a", run: "run1", state: .running)
        XCTAssertEqual(detector.observe(snapshot(sessions: [running])), [])
        XCTAssertEqual(detector.observe(snapshot(sessions: [
            session("a", run: "run1", state: .unknown)
        ])), [])
        XCTAssertEqual(detector.observe(snapshot()), [])
        let completed = session("a", run: "run1", state: .completed)
        XCTAssertEqual(detector.observe(snapshot(sessions: [completed])), [.completedRuns(1)])
        XCTAssertEqual(detector.observe(snapshot(sessions: [completed])), [])
    }

    func testRunFinishingOutsideEightVisibleAgentRowsStillNotifies() {
        var detector = CompanionNoticeDetector()
        let running = session("a", run: "run1", state: .running)
        let nineActive = (1...9).map {
            session("other-\($0)", run: "r\($0)", state: .running)
        }
        XCTAssertEqual(detector.observe(snapshot(sessions: nineActive + [running])), [])
        XCTAssertEqual(detector.observe(snapshot(sessions: nineActive)), [])
        let finished = session("a", run: "run1", state: .failed)
        XCTAssertEqual(
            detector.observe(snapshot(sessions: nineActive + [finished])),
            [.failedRuns(1)]
        )
    }

    func testObservedRunCompletionInHistoryAfterNextRunStartsNotifiesOnce() {
        var detector = CompanionNoticeDetector()
        let oldRunning = session("a", run: "run-a", state: .running)
        XCTAssertEqual(detector.observe(snapshot(sessions: [oldRunning])), [])

        let nextRunning = session(
            "a", run: "run-b", state: .running,
            recentRuns: [
                AgentRunSnapshot(id: "run-a", state: .completed),
                AgentRunSnapshot(id: "run-b", state: .running)
            ]
        )
        XCTAssertEqual(detector.observe(snapshot(sessions: [nextRunning])), [.completedRuns(1)])
        XCTAssertEqual(detector.observe(snapshot(sessions: [nextRunning])), [])
        let nextCompleted = session(
            "a", run: "run-b", state: .completed,
            recentRuns: [AgentRunSnapshot(id: "run-a", state: .completed)]
        )
        XCTAssertEqual(detector.observe(snapshot(sessions: [nextCompleted])), [.completedRuns(1)])
        XCTAssertEqual(detector.observe(snapshot(sessions: [nextCompleted])), [])
    }

    func testObservedFailureInHistoryWhenNextRunIsSelected() {
        var detector = CompanionNoticeDetector()
        XCTAssertEqual(detector.observe(snapshot(sessions: [
            session("a", run: "old-run", state: .queued)
        ])), [])

        let nextRunning = session(
            "a", run: "next-run", state: .running,
            recentRuns: [
                AgentRunSnapshot(id: "old-run", state: .failed),
                AgentRunSnapshot(id: "unseen-historical", state: .completed)
            ]
        )
        XCTAssertEqual(detector.observe(snapshot(sessions: [nextRunning])), [.failedRuns(1)])
        XCTAssertEqual(detector.observe(snapshot(sessions: [nextRunning])), [])
    }

    func testNeverObservedHistoricalRunsAreNotReplayedAsNotifications() {
        var detector = CompanionNoticeDetector()
        let current = session(
            "a", run: "new-run", state: .running,
            recentRuns: [
                AgentRunSnapshot(id: "unseen-done", state: .completed),
                AgentRunSnapshot(id: "unseen-failed", state: .failed)
            ]
        )
        XCTAssertEqual(detector.observe(snapshot(sessions: [current])), [])
        XCTAssertEqual(detector.observe(snapshot(sessions: [current])), [])
        XCTAssertEqual(detector.observe(snapshot(sessions: [
            session("a", run: "new-run", state: .completed, recentRuns: current.recentRuns)
        ])), [.completedRuns(1)])
    }

    func testUnknownAndUnconfirmedRunsNeverProduceCompletionNotice() {
        var detector = CompanionNoticeDetector()
        XCTAssertEqual(detector.observe(snapshot(sessions: [
            session("a", run: "ra", state: .unknown)
        ])), [])
        XCTAssertEqual(detector.observe(snapshot(sessions: [
            session("a", run: "ra", state: .completed)
        ])), [])
    }

    func testDisconnectAndConnectorChangeRebaselineWithoutReplay() {
        var detector = CompanionNoticeDetector()
        XCTAssertEqual(detector.observe(snapshot(approvals: ["old"])), [])
        XCTAssertEqual(detector.observe(snapshot(state: .error)), [])
        XCTAssertEqual(detector.observe(snapshot(approvals: ["old", "new"])), [])
        XCTAssertEqual(detector.observe(snapshot(approvals: ["old", "new", "third"])), [.approvals(1)])

        XCTAssertEqual(detector.observe(snapshot(approvals: ["x"], connectorName: "Other")), [])
        XCTAssertEqual(detector.observe(snapshot(approvals: ["x", "y"], connectorName: "Other")), [.approvals(1)])
        detector.reset()
        XCTAssertEqual(detector.observe(snapshot(approvals: ["x", "y", "z"])), [])
    }

    func testNoticeStringsContainNoSensitiveData() {
        let notices: [CompanionNotice] = [
            .approvals(3), .completedRuns(2), .failedRuns(1)
        ]
        for notice in notices {
            XCTAssertFalse(notice.title.isEmpty)
            XCTAssertFalse(notice.body.isEmpty)
            XCTAssertFalse(notice.title.contains("https://"))
            XCTAssertFalse(notice.body.contains("agent-id"))
        }
    }

    private func snapshot(
        approvals: [String] = [],
        sessions: [AgentSessionSnapshot] = [],
        state: ConnectionState = .connected,
        connectorName: String = "Paperclip"
    ) -> ConnectorSnapshot {
        ConnectorSnapshot(
            connectorName: connectorName,
            connectionState: state,
            pendingApprovals: approvals.map {
                ApprovalRequest(id: $0, title: "Sensitive task title", requestedAt: .distantPast)
            },
            agentSessions: sessions
        )
    }

    private func session(
        _ agent: String,
        run: String,
        state: AgentSessionSnapshot.RunState,
        recentRuns: [AgentRunSnapshot] = []
    ) -> AgentSessionSnapshot {
        AgentSessionSnapshot(
            id: agent,
            agentID: agent,
            agentName: "Private agent",
            agentStatus: state.rawValue,
            runID: run,
            runState: state,
            taskTitle: "Private details",
            recentRuns: recentRuns
        )
    }
}
