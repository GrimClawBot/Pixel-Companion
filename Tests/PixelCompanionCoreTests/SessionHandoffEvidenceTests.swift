import PixelCompanionCore
import XCTest

final class SessionHandoffEvidenceTests: XCTestCase {
    private func session(
        agentID: String = "agent-a",
        used: Int? = nil, window: Int? = nil,
        runID: String? = "run-1", sessionID: String? = "session-1"
    ) -> AgentSessionSnapshot {
        AgentSessionSnapshot(
            id: "row-a", agentID: agentID, agentName: "Research agent",
            agentStatus: "running", runID: runID, runState: .running,
            provider: "reported-provider", sessionID: sessionID,
            inputTokens: 90_000, outputTokens: 20_000,
            contextUsedTokens: used, contextWindowTokens: window
        )
    }

    private func task(_ id: String, assignee: String = "agent-a") -> TaskSnapshot {
        TaskSnapshot(
            id: id, identifier: "PX-" + id, title: "Verified task " + id,
            status: "in_progress", assigneeAgentID: assignee
        )
    }

    func testOnlyLiveSpecificAgentGetsHandoffEvidence() {
        let snapshot = session()
        let tasks = [task("1")]
        XCTAssertNil(SessionHandoffEvidence.prepare(
            session: snapshot, assignedTasks: tasks, isLive: false
        ))
        XCTAssertNil(SessionHandoffEvidence.prepare(
            session: session(agentID: ""), assignedTasks: tasks, isLive: true
        ))
        let result = SessionHandoffEvidence.prepare(
            session: snapshot, assignedTasks: tasks, isLive: true
        )
        XCTAssertEqual(result?.agentID, "agent-a")
        XCTAssertEqual(result?.sessionID, "session-1")
        XCTAssertEqual(result?.runID, "run-1")
        XCTAssertEqual(result?.assignedTasks.map(\.sourceID), ["1"])
    }

    func testNeverUsesAnotherAgentsAssignmentsOrUnassignedTitles() throws {
        let tasks = [
            task("correct"), task("other", assignee: "agent-b"),
            task("unassigned", assignee: ""), task("correct")
        ]
        let result = try XCTUnwrap(SessionHandoffEvidence.prepare(
            session: session(), assignedTasks: tasks, isLive: true
        ))
        XCTAssertEqual(result.assignedTasks.map(\.sourceID), ["correct"])
        XCTAssertFalse(result.evidenceIsBounded)
    }

    func testFiveUniqueVerifiedTasksMaximumAndBoundedNotice() throws {
        let tasks = (0..<7).map { task(String($0)) }
        let result = try XCTUnwrap(SessionHandoffEvidence.prepare(
            session: session(), assignedTasks: tasks, isLive: true
        ))
        XCTAssertEqual(result.assignedTasks.map(\.sourceID), [
            "0", "1", "2", "3", "4"
        ])
        XCTAssertTrue(result.evidenceIsBounded)
    }

    func testMissingIdsAndBlankTitlesNotInvented() throws {
        let tasks = [
            TaskSnapshot(id: "", title: "No source ID", status: "active",
                         assigneeAgentID: "agent-a"),
            TaskSnapshot(id: "blank", title: "   ", status: "active",
                         assigneeAgentID: "agent-a"),
            TaskSnapshot(id: "ok", identifier: " ", title: "Real task",
                         status: "running", assigneeAgentID: "agent-a")
        ]
        let result = try XCTUnwrap(SessionHandoffEvidence.prepare(
            session: session(), assignedTasks: tasks, isLive: true
        ))
        XCTAssertEqual(result.assignedTasks.map(\.sourceID), ["ok"])
        XCTAssertNil(result.assignedTasks.first?.identifier)
    }

    func testCumulativeTokensCannotBeUsedToGuessContextOccupancy() throws {
        let result = try XCTUnwrap(SessionHandoffEvidence.prepare(
            session: session(), assignedTasks: [], isLive: true
        ))
        XCTAssertNil(result.contextHealth.fraction)
        XCTAssertEqual(result.contextHealth.recommendation, .unavailable)
        XCTAssertEqual(result.contextHealth.confidence, .unknown)
    }

    func testContextOnlyReportsValidUsedAndWindowPair() throws {
        let fresh = try XCTUnwrap(SessionHandoffEvidence.prepare(
            session: session(used: 85, window: 100), assignedTasks: [], isLive: true
        ))
        XCTAssertEqual(fresh.contextHealth.confidence, .providerReported)
        XCTAssertEqual(fresh.contextHealth.recommendation, .freshSessionRecommended)
        let malformed = try XCTUnwrap(SessionHandoffEvidence.prepare(
            session: session(used: 110, window: 100), assignedTasks: [], isLive: true
        ))
        XCTAssertNil(malformed.contextHealth.fraction)
    }

    func testMissingRunAndSessionIdentifiersRemainUnavailable() throws {
        let result = try XCTUnwrap(SessionHandoffEvidence.prepare(
            session: session(runID: "  ", sessionID: nil),
            assignedTasks: [], isLive: true
        ))
        XCTAssertNil(result.runID)
        XCTAssertNil(result.sessionID)
    }

    func testHandoffChecklistDoesNotInventObjectivesOrApprovals() {
        XCTAssertEqual(SessionHandoffEvidence.missingForHandoff.count, 5)
        XCTAssertTrue(SessionHandoffEvidence.missingForHandoff.contains(
            "Decisions and rationale"
        ))
        XCTAssertTrue(SessionHandoffEvidence.missingForHandoff.contains(
            "Approved actions and permissions"
        ))
    }
}
