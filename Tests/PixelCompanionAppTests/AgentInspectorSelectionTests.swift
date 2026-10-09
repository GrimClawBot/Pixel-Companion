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

    func testAssignedTaskDrilldownAcceptsOnlyUniqueCurrentLiveAssignment() {
        let matching = TaskSnapshot(
            id: "task-1", identifier: "PX-1", title: "Verified objective",
            status: "in_progress", assigneeAgentID: "agent-a"
        )
        let otherAgent = TaskSnapshot(
            id: "task-2", title: "Another task",
            status: "in_progress", assigneeAgentID: "agent-b"
        )
        XCTAssertEqual(
            AgentAssignedTaskSelection.resolve(
                taskID: "task-1", agentID: "agent-a",
                tasks: [matching, otherAgent], isLive: true
            )?.title,
            "Verified objective"
        )
        XCTAssertNil(AgentAssignedTaskSelection.resolve(
            taskID: "task-1", agentID: "agent-b",
            tasks: [matching, otherAgent], isLive: true
        ))
        XCTAssertNil(AgentAssignedTaskSelection.resolve(
            taskID: "task-2", agentID: "agent-a",
            tasks: [matching, otherAgent], isLive: true
        ))
        XCTAssertNil(AgentAssignedTaskSelection.resolve(
            taskID: "task-1", agentID: "agent-a",
            tasks: [matching, otherAgent], isLive: false
        ))
    }

    func testTaskReassignmentOrSourceRemovalImmediatelyRevokesSelection() {
        let assigned = TaskSnapshot(
            id: "task-1", title: "Task", status: "active", assigneeAgentID: "agent-a"
        )
        let reassigned = TaskSnapshot(
            id: "task-1", title: "Task", status: "active", assigneeAgentID: "agent-b"
        )
        XCTAssertNotNil(AgentAssignedTaskSelection.resolve(
            taskID: "task-1", agentID: "agent-a", tasks: [assigned], isLive: true
        ))
        XCTAssertNil(AgentAssignedTaskSelection.resolve(
            taskID: "task-1", agentID: "agent-a", tasks: [reassigned], isLive: true
        ))
        XCTAssertNil(AgentAssignedTaskSelection.resolve(
            taskID: "task-1", agentID: "agent-a", tasks: [], isLive: true
        ))
        XCTAssertNil(AgentAssignedTaskSelection.resolve(
            taskID: "task-1", agentID: "agent-a",
            tasks: [assigned, assigned], isLive: true
        ))
        XCTAssertNil(AgentAssignedTaskSelection.resolve(
            taskID: "task-1", agentID: "agent-a",
            tasks: [assigned, reassigned], isLive: true
        ))
    }

    func testMissingOrBlankTaskAndAgentIDsCannotOpenDetails() {
        let blank = TaskSnapshot(
            id: "", title: "No backend ID", status: "todo", assigneeAgentID: "a"
        )
        XCTAssertNil(AgentAssignedTaskSelection.resolve(
            taskID: "", agentID: "a", tasks: [blank], isLive: true
        ))
        XCTAssertNil(AgentAssignedTaskSelection.resolve(
            taskID: nil, agentID: "a", tasks: [blank], isLive: true
        ))
        XCTAssertNil(AgentAssignedTaskSelection.resolve(
            taskID: "", agentID: "", tasks: [blank], isLive: true
        ))
        XCTAssertNil(AgentAssignedTaskSelection.resolve(
            taskID: "id", agentID: "", tasks: [blank], isLive: true
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
