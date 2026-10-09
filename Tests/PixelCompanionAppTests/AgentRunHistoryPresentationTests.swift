import PixelCompanionCore
@testable import PixelCompanion
import XCTest

final class AgentRunHistoryPresentationTests: XCTestCase {
    func testReportedTokenCountsAreAccurateAndNoEstimatesAreAdded() {
        let known = AgentRunSnapshot(
            id: "run-1", state: .completed, inputTokens: 1200,
            cachedInputTokens: 400, outputTokens: 38
        )
        XCTAssertEqual(
            AgentRunHistoryPresentation.tokenLabel(known),
            "1,200 in · 400 cached · 38 out"
        )
        let unknown = AgentRunSnapshot(id: "run-2", state: .unknown)
        XCTAssertEqual(
            AgentRunHistoryPresentation.tokenLabel(unknown),
            "Run tokens not reported"
        )
    }

    func testRunDrilldownOnlyResolvesUniqueLiveRunID() {
        let first = AgentRunSnapshot(id: "run-a", state: .completed, issueID: "issue-1")
        let second = AgentRunSnapshot(id: "run-b", state: .running)
        XCTAssertEqual(
            AgentRunInspection.resolve(runID: "run-a", runs: [first, second], isLive: true)?.id,
            "run-a"
        )
        XCTAssertNil(AgentRunInspection.resolve(
            runID: "run-a", runs: [first], isLive: false
        ))
        XCTAssertNil(AgentRunInspection.resolve(
            runID: "run-a", runs: [second], isLive: true
        ))
        XCTAssertNil(AgentRunInspection.resolve(
            runID: nil, runs: [first], isLive: true
        ))
        XCTAssertNil(AgentRunInspection.resolve(
            runID: "", runs: [first], isLive: true
        ))
        XCTAssertNil(AgentRunInspection.resolve(
            runID: "run-a", runs: [first, first], isLive: true
        ))
    }

    func testVerifiedHistoricalTaskUsesStructuredIssueIDNotTitleOrAssignee() {
        let run = AgentRunSnapshot(
            id: "run-1", state: .completed,
            issueID: "issue-01", taskTitle: "Similar task title"
        )
        let current = TaskSnapshot(
            id: "issue-01", identifier: "PX-01", title: "Actual verified task",
            status: "done", assigneeAgentID: "another-agent"
        )
        let lookalike = TaskSnapshot(
            id: "issue-02", title: "Similar task title", status: "running",
            assigneeAgentID: "this-agent"
        )
        XCTAssertEqual(
            AgentRunInspection.verifiedTask(
                for: run, tasks: [lookalike, current], isLive: true
            )?.id,
            "issue-01"
        )
        XCTAssertNil(AgentRunInspection.verifiedTask(
            for: run, tasks: [lookalike], isLive: true
        ))
        XCTAssertNil(AgentRunInspection.verifiedTask(
            for: run, tasks: [current], isLive: false
        ))
    }

    func testMissingOrAmbiguousStructuredTaskLinkFailsClosed() {
        let valid = AgentRunSnapshot(id: "run-1", state: .completed, issueID: "task-id")
        let unspecified = AgentRunSnapshot(
            id: "run-2", state: .completed, taskTitle: "Coincidentally similar title"
        )
        let sourceTask = TaskSnapshot(
            id: "task-id", title: "Coincidentally similar title", status: "done"
        )
        XCTAssertNil(AgentRunInspection.verifiedTask(
            for: unspecified, tasks: [sourceTask], isLive: true
        ))
        XCTAssertNil(AgentRunInspection.verifiedTask(
            for: valid, tasks: [sourceTask, sourceTask], isLive: true
        ))
        let blank = AgentRunSnapshot(id: "run-3", state: .completed, issueID: "")
        XCTAssertNil(AgentRunInspection.verifiedTask(
            for: blank, tasks: [sourceTask], isLive: true
        ))
    }

    func testUnknownRunIsNotPresentedAsActive() {
        XCTAssertEqual(AgentRunHistoryPresentation.stateLabel(.unknown), "Unconfirmed")
        XCTAssertEqual(AgentRunHistoryPresentation.stateLabel(.running), "Running")
        XCTAssertEqual(AgentRunHistoryPresentation.stateLabel(.queued), "Queued")
        XCTAssertEqual(AgentRunHistoryPresentation.stateLabel(.failed), "Failed")
        XCTAssertEqual(AgentRunHistoryPresentation.stateLabel(.completed), "Completed")
    }
}
