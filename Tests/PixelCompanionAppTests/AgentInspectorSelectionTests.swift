import Foundation
import PixelCompanionCore
@testable import PixelCompanion
import XCTest

final class AgentInspectorSelectionTests: XCTestCase {
    private func session(
        id: String,
        agentID: String,
        status: AgentSessionSnapshot.RunState = .idle,
        task: String? = nil
    ) -> AgentSessionSnapshot {
        AgentSessionSnapshot(
            id: id, agentID: agentID, agentName: agentID,
            agentStatus: status.rawValue, runState: status,
            taskTitle: task
        )
    }

    func testNoSelectionAndMissingAgentShowListRatherThanInventingDetails() {
        let sessions = [session(id: "row-1", agentID: "a")]
        XCTAssertNil(AgentInspectorSelection.resolve(
            agentID: nil, sessions: sessions, isLive: true
        ))
        XCTAssertNil(AgentInspectorSelection.resolve(
            agentID: "missing", sessions: sessions, isLive: true
        ))
        XCTAssertNil(AgentInspectorSelection.resolve(
            agentID: "", sessions: sessions, isLive: true
        ))
    }

    func testAgentIdentityNotRowIdentityAndAlwaysUsesCurrentData() {
        let initial = [session(id: "run-1", agentID: "a", status: .idle)]
        XCTAssertEqual(AgentInspectorSelection.resolve(
            agentID: "a", sessions: initial, isLive: true
        )?.runState, .idle)
        let refreshed = [
            session(id: "run-2", agentID: "a", status: .running, task: "Current task")
        ]
        let resolved = AgentInspectorSelection.resolve(
            agentID: "a", sessions: refreshed, isLive: true
        )
        XCTAssertEqual(resolved?.id, "run-2")
        XCTAssertEqual(resolved?.taskTitle, "Current task")
    }

    func testDisconnectedOrStaleStateCannotExposeCachedInspector() {
        let cached = [session(id: "run-1", agentID: "a", status: .running)]
        XCTAssertNil(AgentInspectorSelection.resolve(
            agentID: "a", sessions: cached, isLive: false
        ))
        XCTAssertNil(AgentInspectorSelection.resolve(
            agentID: "a", sessions: [], isLive: true
        ))
    }

    func testSelectsOnlyRequestedAgent() {
        let sessions = [
            session(id: "1", agentID: "a"),
            session(id: "2", agentID: "b")
        ]
        XCTAssertEqual(AgentInspectorSelection.resolve(
            agentID: "b", sessions: sessions, isLive: true
        )?.agentID, "b")
    }
}
