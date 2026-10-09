import Foundation
import PixelCompanionCore
@testable import PixelCompanion
import XCTest

final class CompanyTaskRunTraceTests: XCTestCase {
    private let task = TaskSnapshot(
        id: "issue-9", identifier: "PX-9", title: "Ship evidence",
        status: "in_progress", assigneeAgentID: "current"
    )

    private func agent(
        _ id: String, runs: [AgentRunSnapshot] = []
    ) -> AgentSessionSnapshot {
        AgentSessionSnapshot(
            id: "session-" + id, agentID: id, agentName: "Agent " + id,
            agentStatus: "idle", runState: .idle, recentRuns: runs
        )
    }

    private func run(
        _ id: String, issueID: String?, title: String? = nil,
        updated: Date? = nil
    ) -> AgentRunSnapshot {
        AgentRunSnapshot(
            id: id, state: .completed, issueID: issueID,
            taskTitle: title, updatedAt: updated
        )
    }

    func testOnlyExactStructuredIssueIdLinksRunNotTitleOrCurrentAssignment() {
        let sessions = [
            agent("current", runs: [
                run("looks-like-task", issueID: "other", title: "PX-9 · Ship evidence"),
                run("unlinked", issueID: nil, title: "PX-9 · Ship evidence")
            ]),
            agent("historical", runs: [
                run("verified", issueID: "issue-9", title: "Old task name")
            ])
        ]
        let linked = CompanyTaskRunTrace.linkedRuns(task: task, sessions: sessions, isLive: true)
        XCTAssertEqual(linked.map(\.run.id), ["verified"])
        XCTAssertEqual(linked.first?.agentID, "historical")
        XCTAssertEqual(linked.first?.agentName, "Agent historical")
        XCTAssertEqual(CompanyTaskRunTrace.currentAssignee(
            task: task, sessions: sessions, isLive: true
        )?.agentID, "current")
    }

    func testStaleOrAbsentEvidenceDoesNotShowCurrentAssignmentOrRunLinks() {
        let sessions = [agent("current", runs: [run("known", issueID: "issue-9")])]
        XCTAssertTrue(CompanyTaskRunTrace.linkedRuns(
            task: task, sessions: sessions, isLive: false
        ).isEmpty)
        XCTAssertNil(CompanyTaskRunTrace.currentAssignee(
            task: task, sessions: sessions, isLive: false
        ))
        XCTAssertTrue(CompanyTaskRunTrace.linkedRuns(
            task: task, sessions: [], isLive: true
        ).isEmpty)
        let unknown = TaskSnapshot(id: "", title: "No ID", status: "todo")
        XCTAssertTrue(CompanyTaskRunTrace.linkedRuns(
            task: unknown, sessions: sessions, isLive: true
        ).isEmpty)
    }

    func testRecentLinksSortedByActualReportedTimestampsWithNoSyntheticDates() {
        let earlier = Date(timeIntervalSince1970: 100)
        let later = Date(timeIntervalSince1970: 200)
        let sessions = [
            agent("a", runs: [
                run("old", issueID: "issue-9", updated: earlier),
                run("no-date", issueID: "issue-9"),
                run("new", issueID: "issue-9", updated: later)
            ]),
            agent("b", runs: [run("other-task", issueID: "issue-10", updated: later)])
        ]
        XCTAssertEqual(
            CompanyTaskRunTrace.linkedRuns(task: task, sessions: sessions, isLive: true)
                .map(\.run.id),
            ["new", "old", "no-date"]
        )
    }

    func testDuplicateRunWithinAgentIsOnlyShownOnce() {
        let sessions = [agent("current", runs: [
            run("duplicate", issueID: "issue-9"),
            run("duplicate", issueID: "issue-9")
        ])]
        XCTAssertEqual(CompanyTaskRunTrace.linkedRuns(
            task: task, sessions: sessions, isLive: true
        ).map(\.run.id), ["duplicate"])
    }

    func testNoAssigneeReportedDoesNotPreventHistoricallyLinkedRun() {
        let noAssignee = TaskSnapshot(id: "issue-9", title: "Task", status: "done")
        let sessions = [agent("historical", runs: [run("old", issueID: "issue-9")])]
        XCTAssertNil(CompanyTaskRunTrace.currentAssignee(
            task: noAssignee, sessions: sessions, isLive: true
        ))
        XCTAssertEqual(
            CompanyTaskRunTrace.linkedRuns(
                task: noAssignee, sessions: sessions, isLive: true
            ).map(\.run.id), ["old"]
        )
    }
}
