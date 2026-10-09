import PixelCompanionCore
@testable import PixelCompanion
import XCTest

final class AgentReportingHierarchyTests: XCTestCase {
    private func agent(_ id: String, manager: String? = nil, role: String? = nil) -> AgentSessionSnapshot {
        AgentSessionSnapshot(
            id: "row-" + id, agentID: id, agentName: "Agent " + id,
            agentRole: role, managerAgentID: manager,
            agentStatus: "idle", runState: .idle
        )
    }

    func testTreeIsBuiltOnlyFromVerifiedReportsToIDs() {
        let sessions = [
            agent("worker", manager: "lead", role: "engineering"),
            agent("ceo", role: "ceo"),
            agent("lead", manager: "ceo", role: "engineering"),
            agent("direct", manager: "ceo", role: "design")
        ]
        let rows = AgentReportingHierarchy.rows(sessions)
        XCTAssertEqual(rows.map(\.session.agentID), ["ceo", "lead", "worker", "direct"])
        XCTAssertEqual(rows.map(\.depth), [0, 1, 2, 1])
        XCTAssertEqual(rows.map(\.managerName), [
            nil, "Agent ceo", "Agent lead", "Agent ceo"
        ])
        XCTAssertNil(rows.first?.note)
        XCTAssertEqual(AgentReportingHierarchy.manager(
            for: sessions[0], in: sessions
        )?.agentID, "lead")
    }

    func testMatchingRoleDoesNotCreateReportingRelationship() {
        let sessions = [
            agent("lead", role: "engineering"),
            agent("worker", role: "engineering")
        ]
        let rows = AgentReportingHierarchy.rows(sessions)
        XCTAssertEqual(rows.map(\.depth), [0, 0])
        XCTAssertTrue(rows.allSatisfy { $0.managerName == nil })
        XCTAssertNil(AgentReportingHierarchy.manager(for: sessions[1], in: sessions))
    }

    func testAbsentManagerShowsUnverifiedRootRatherThanInventedCEO() {
        let sessions = [agent("worker", manager: "not-in-feed")]
        let rows = AgentReportingHierarchy.rows(sessions)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].depth, 0)
        XCTAssertEqual(rows[0].note, "Manager not in this view")
        XCTAssertNil(rows[0].managerName)
        XCTAssertNil(AgentReportingHierarchy.manager(for: sessions[0], in: sessions))
    }

    func testFilteredViewDoesNotBorrowHiddenManagerData() {
        let all = [
            agent("ceo"), agent("lead", manager: "ceo"),
            agent("worker", manager: "lead")
        ]
        let filtered = [all[2]]
        let rows = AgentReportingHierarchy.rows(filtered)
        XCTAssertEqual(rows.map(\.depth), [0])
        XCTAssertEqual(rows[0].note, "Manager not in this view")
        XCTAssertNil(AgentReportingHierarchy.manager(for: filtered[0], in: filtered))
    }

    func testSelfReferenceAndCyclesRemainVisibleButUnverified() {
        let sessions = [
            agent("self", manager: "self"),
            agent("a", manager: "b"),
            agent("b", manager: "a"),
            agent("child", manager: "a")
        ]
        let rows = AgentReportingHierarchy.rows(sessions)
        XCTAssertEqual(Set(rows.map(\.session.agentID)), Set(["self", "a", "b", "child"]))
        XCTAssertTrue(rows.allSatisfy { $0.depth == 0 })
        XCTAssertTrue(rows.allSatisfy { $0.note == "Reporting cycle not verified" })
        XCTAssertNil(AgentReportingHierarchy.manager(for: sessions[3], in: sessions))
    }

    func testBrokenGrandparentCannotBePassedOffAsValidTree() {
        let sessions = [
            agent("leaf", manager: "lead"),
            agent("lead", manager: "unknown")
        ]
        let rows = AgentReportingHierarchy.rows(sessions)
        XCTAssertEqual(rows.map(\.depth), [0, 0])
        XCTAssertTrue(rows.allSatisfy { $0.note != nil })
        XCTAssertNil(AgentReportingHierarchy.manager(for: sessions[0], in: sessions))
    }

    func testWhitespaceMissingIDsAndDuplicatesNeverCrashOrInventHierarchy() {
        let sessions = [
            agent("root", manager: "  "),
            agent("child", manager: " root "),
            agent("child", manager: "phantom"),
            agent(""), agent("orphan", manager: " ")
        ]
        let rows = AgentReportingHierarchy.rows(sessions)
        XCTAssertEqual(rows.map(\.session.agentID), ["root", "child", "orphan"])
        XCTAssertEqual(rows.map(\.depth), [0, 1, 0])
        XCTAssertEqual(rows[1].managerName, "Agent root")
        XCTAssertNil(rows[2].note)
    }

    func testVerifiedDirectReportCountsDoNotIncludeGrandchildrenOrMissingParents() {
        let rows = AgentReportingHierarchy.rows([
            agent("leaf", manager: "lead"),
            agent("ceo"), agent("lead", manager: "ceo"),
            agent("direct", manager: "ceo"),
            agent("orphan", manager: "filtered-out")
        ])
        XCTAssertEqual(rows.map(\.session.agentID), [
            "ceo", "lead", "leaf", "direct", "orphan"
        ])
        XCTAssertEqual(rows.map(\.directReportCount), [2, 1, 0, 0, 0])
        XCTAssertEqual(rows.last?.note, "Manager not in this view")
    }

    func testCollapsingManagerHidesOnlyVerifiedDescendantsAndKeepsOtherRoots() {
        let rows = AgentReportingHierarchy.rows([
            agent("leaf", manager: "lead"),
            agent("ceo"), agent("lead", manager: "ceo"),
            agent("direct", manager: "ceo"),
            agent("orphan", manager: "absent")
        ])
        XCTAssertEqual(AgentReportingHierarchy.visibleRows(
            rows, collapsedManagerIDs: []
        ).map(\.id), ["ceo", "lead", "leaf", "direct", "orphan"])
        XCTAssertEqual(AgentReportingHierarchy.visibleRows(
            rows, collapsedManagerIDs: ["ceo"]
        ).map(\.id), ["ceo", "orphan"])
        XCTAssertEqual(AgentReportingHierarchy.visibleRows(
            rows, collapsedManagerIDs: ["lead"]
        ).map(\.id), ["ceo", "lead", "direct", "orphan"])
    }

    func testNestedCollapseRemainsLocalWhenParentReopens() {
        let rows = AgentReportingHierarchy.rows([
            agent("ceo"), agent("lead", manager: "ceo"),
            agent("worker", manager: "lead")
        ])
        let fullyCollapsed = AgentReportingHierarchy.visibleRows(
            rows, collapsedManagerIDs: ["ceo", "lead"]
        )
        XCTAssertEqual(fullyCollapsed.map(\.id), ["ceo"])
        let parentReopened = AgentReportingHierarchy.visibleRows(
            rows, collapsedManagerIDs: ["lead"]
        )
        XCTAssertEqual(parentReopened.map(\.id), ["ceo", "lead"])
        XCTAssertEqual(AgentReportingHierarchy.visibleRows(
            rows, collapsedManagerIDs: []
        ).map(\.id), ["ceo", "lead", "worker"])
    }

    func testDisclosureCannotHideInvalidOrUnverifiedReportingLinks() {
        let rows = AgentReportingHierarchy.rows([
            agent("a", manager: "b"), agent("b", manager: "a"),
            agent("missing-parent", manager: "ghost"),
            agent("role-only", role: "CEO")
        ])
        XCTAssertTrue(rows.allSatisfy { $0.directReportCount == 0 })
        XCTAssertEqual(AgentReportingHierarchy.visibleRows(
            rows, collapsedManagerIDs: Set(rows.map(\.id))
        ).map(\.id), rows.map(\.id))
    }

    func testEmptyDisclosureDoesNotProducePhantomRows() {
        XCTAssertTrue(AgentReportingHierarchy.visibleRows(
            [], collapsedManagerIDs: ["nonexistent"]
        ).isEmpty)
    }

    func testNoAgentsReturnsEmptyRows() {
        XCTAssertTrue(AgentReportingHierarchy.rows([]).isEmpty)
    }
}
