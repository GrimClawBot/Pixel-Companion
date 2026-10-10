import PixelCompanionCore
@testable import PixelCompanion
import XCTest

final class AgentRoleGroupingTests: XCTestCase {
    private func agent(_ name: String, role: String?) -> AgentSessionSnapshot {
        AgentSessionSnapshot(
            id: "snapshot-" + name, agentID: name, agentName: name,
            agentRole: role, agentStatus: "idle", runState: .idle
        )
    }

    func testGroupsUseOnlyReportedRolesAndKeepInputOrderWithinRoles() {
        let values = [
            agent("emma", role: "Researcher"),
            agent("atlas", role: "ceo"),
            agent("ethan", role: "researcher"),
            agent("unknown", role: nil),
            agent("no-role", role: "  "),
            agent("coder", role: "Engineer")
        ]
        let grouped = AgentRoleGrouping.groups(values)
        XCTAssertEqual(grouped.map(\.label), [
            "Ceo", "Engineer", "Researcher", "Role not reported"
        ])
        XCTAssertEqual(grouped[2].sessions.map(\.agentID), ["emma", "ethan"])
        XCTAssertEqual(grouped[3].sessions.map(\.agentID), ["unknown", "no-role"])
        XCTAssertEqual(grouped.flatMap { $0.sessions }.count, values.count)
    }

    func testEmptyAndAllUnknownAreNotInventedIntoDepartments() {
        XCTAssertTrue(AgentRoleGrouping.groups([]).isEmpty)
        let groups = AgentRoleGrouping.groups([
            agent("a", role: nil), agent("b", role: "")
        ])
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].label, "Role not reported")
        XCTAssertEqual(groups[0].sessions.map(\.agentID), ["a", "b"])
    }

    func testReportedRoleIsDataNotAnInferredHierarchy() {
        let groups = AgentRoleGrouping.groups([
            agent("same", role: "Engineering"),
            agent("different", role: "engineer")
        ])
        XCTAssertEqual(groups.map(\.label), ["Engineer", "Engineering"])
        XCTAssertEqual(groups[0].sessions.map(\.agentID), ["different"])
        XCTAssertEqual(groups[1].sessions.map(\.agentID), ["same"])
    }
}
