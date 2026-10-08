import Foundation
@testable import PixelCompanionCore
import XCTest

final class PaperclipTasksMappingTests: XCTestCase {
    private func task(
        _ id: String,
        assignedTo: String? = nil,
        time: String? = nil
    ) -> String {
        let agent = assignedTo.map { ",\"assigneeAgentId\":\"\($0)\"" } ?? ""
        let updated = time.map { ",\"updatedAt\":\"\($0)\"" } ?? ""
        return """
        {"id":"\(id)","identifier":"PX-\(id)","title":"Work \(id)",
         "status":"in_progress"\(agent)\(updated)}
        """
    }

    private func snapshots(_ issues: [String]) throws -> [TaskSnapshot] {
        let decoder = JSONDecoder()
        let values = try issues.map {
            try decoder.decode(PaperclipIssueResponse.self, from: Data($0.utf8))
        }
        let company = PaperclipCompany(id: "org", name: "QA", status: "active")
        let input = PaperclipMappingInput(
            companies: [company], company: company,
            dashboard: .init(costs: .init(monthSpendCents: 0, monthBudgetCents: 0)),
            agents: [], issues: values, approvals: [], runs: []
        )
        return PaperclipMapper.map(input).tasks
    }

    func testIssuesStayStructuredAndExactlyAttributedToRealAgentIDs() throws {
        let values = try snapshots([
            task("1", assignedTo: "agent-a"),
            task("2", assignedTo: "agent-b"),
            task("3")
        ])
        XCTAssertEqual(values.count, 3)
        XCTAssertEqual(values.first(where: { $0.id == "1" })?.assigneeAgentID, "agent-a")
        XCTAssertEqual(values.first(where: { $0.id == "2" })?.assigneeAgentID, "agent-b")
        XCTAssertNil(values.first(where: { $0.id == "3" })?.assigneeAgentID)
        XCTAssertEqual(values.first(where: { $0.id == "1" })?.identifier, "PX-1")
    }

    func testMostRecentlyUpdatedFirstThenStableIdOrder() throws {
        let tasks = try snapshots([
            task("older", time: "2026-10-01T01:00:00Z"),
            task("b", time: "2026-10-07T01:00:00Z"),
            task("a", time: "2026-10-07T01:00:00Z"),
            task("unknown")
        ])
        XCTAssertEqual(tasks.map(\.id), ["a", "b", "older", "unknown"])
        XCTAssertNil(tasks.last?.updatedAt)
    }

    func testEmptyIssuesProducesEmptyTasks() throws {
        XCTAssertTrue(try snapshots([]).isEmpty)
    }
}
