import PixelCompanionCore
@testable import PixelCompanion
import XCTest

final class CompanyTaskPresentationTests: XCTestCase {
    private let tasks = [
        TaskSnapshot(id: "1", identifier: "PX-1", title: "Émma analysis",
                     status: "in_progress", assigneeAgentID: "emma"),
        TaskSnapshot(id: "2", title: "Separate research", status: "done",
                     assigneeAgentID: "atlas"),
        TaskSnapshot(id: "3", title: "Unassigned design", status: "todo")
    ]

    func testSearchMatchesNameIdStatusButNeverInfersAssignee() {
        XCTAssertEqual(
            CompanyTaskPresentation.filtered(tasks, query: "emma").map(\.id), ["1"]
        )
        XCTAssertEqual(
            CompanyTaskPresentation.filtered(tasks, query: "PX-1").map(\.id), ["1"]
        )
        XCTAssertEqual(
            CompanyTaskPresentation.filtered(tasks, query: "DONE").map(\.id), ["2"]
        )
        XCTAssertEqual(
            CompanyTaskPresentation.filtered(tasks, query: "  ").map(\.id), ["1", "2", "3"]
        )
        XCTAssertTrue(
            CompanyTaskPresentation.filtered(tasks, query: "not present").isEmpty
        )
    }

    func testStructuredAssigneeFilteringIsIsolatedAndNeverLiveWhenStale() {
        XCTAssertEqual(
            CompanyTaskPresentation.assigned(tasks, to: "emma", isLive: true).map(\.id),
            ["1"]
        )
        XCTAssertEqual(
            CompanyTaskPresentation.assigned(tasks, to: "atlas", isLive: true).map(\.id),
            ["2"]
        )
        XCTAssertTrue(
            CompanyTaskPresentation.assigned(tasks, to: "", isLive: true).isEmpty
        )
        XCTAssertTrue(
            CompanyTaskPresentation.assigned(tasks, to: "emma", isLive: false).isEmpty
        )
        XCTAssertTrue(
            CompanyTaskPresentation.assigned(tasks, to: "design", isLive: true).isEmpty
        )
    }

    func testExplicitStatusAndIdentityAreReadable() {
        XCTAssertEqual(CompanyTaskPresentation.status(tasks[0]), "In Progress")
        XCTAssertEqual(CompanyTaskPresentation.title(tasks[0]), "PX-1 · Émma analysis")
        XCTAssertEqual(CompanyTaskPresentation.title(tasks[2]), "Unassigned design")
    }
}
