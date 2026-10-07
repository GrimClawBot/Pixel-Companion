import Foundation
import PixelCompanionCore
@testable import PixelCompanion
import XCTest

final class LivePresentationTests: XCTestCase {

    func testApprovalPresentationLimitsPreviewButNotDetail() {
        let approvals = (1...3).map { index in
            ApprovalRequest(
                id: "approval-\(index)",
                title: "Approval \(index)",
                requestedAt: Date(timeIntervalSince1970: Double(index))
            )
        }

        XCTAssertEqual(ApprovalPresentation.visible(approvals, limit: 2), Array(approvals.prefix(2)))
        XCTAssertEqual(ApprovalPresentation.visible(approvals, limit: nil), approvals)
    }

    func testApprovalAccessibilityIncludesWaitTimeAndCount() {
        let now = Date(timeIntervalSince1970: 10_000)
        let approval = ApprovalRequest(
            id: "approval-1",
            title: "Ship release",
            requestedAt: now.addingTimeInterval(-125)
        )

        XCTAssertEqual(ApprovalPresentation.countLabel(1), "1 pending approval")
        XCTAssertEqual(ApprovalPresentation.countLabel(3), "3 pending approvals")
        XCTAssertEqual(
            ApprovalPresentation.accessibilityLabel(approval, now: now),
            "Waiting for approval: Ship release. Requested 2 minutes ago."
        )
    }

    func testApprovalAccessibilityHandlesMissingTimestamp() {
        let approval = ApprovalRequest(
            id: "approval-1",
            title: "Ship release",
            requestedAt: .distantPast
        )

        XCTAssertEqual(
            ApprovalPresentation.accessibilityLabel(approval, now: Date(timeIntervalSince1970: 10_000)),
            "Waiting for approval: Ship release"
        )
    }

    func testHistoryRemovesCurrentActivityByID() {
        let now = ActivityEvent(
            id: "current",
            kind: .running,
            title: "Current",
            timestamp: Date(timeIntervalSince1970: 20)
        )
        let older = ActivityEvent(
            id: "older",
            kind: .completed,
            title: "Older",
            timestamp: Date(timeIntervalSince1970: 10)
        )

        XCTAssertEqual(
            ActivityPresentation.history([now, older], currentActivity: now),
            [older]
        )
    }

    func testHistoryRemovesOnlyHighlightedDuplicateOccurrence() {
        let current = ActivityEvent(
            id: "duplicate",
            kind: .running,
            title: "Current",
            timestamp: Date(timeIntervalSince1970: 20)
        )
        let duplicate = ActivityEvent(
            id: "duplicate",
            kind: .running,
            title: "Another agent event",
            timestamp: Date(timeIntervalSince1970: 19)
        )

        XCTAssertEqual(
            ActivityPresentation.history([current, duplicate], currentActivity: current),
            [duplicate]
        )
    }

    func testHistoryKeepsAllEventsWhenThereIsNoCurrentActivity() {
        let event = ActivityEvent(
            id: "one",
            kind: .note,
            title: "One",
            timestamp: Date(timeIntervalSince1970: 1)
        )

        XCTAssertEqual(ActivityPresentation.history([event], currentActivity: nil), [event])
    }

    func testUsagePresentationFormatsCentsAsUSD() {
        XCTAssertEqual(
            UsagePresentation.amount(
                UsageSnapshot(used: 1234, limit: 5000, unit: "cents", periodLabel: "This month")
            ),
            "$12.34 / $50.00"
        )
    }

    func testUsagePresentationPreservesGenericUnits() {
        XCTAssertEqual(
            UsagePresentation.amount(
                UsageSnapshot(used: 42, limit: 100, unit: "tokens", periodLabel: "Session")
            ),
            "42 / 100 tokens"
        )
    }
}
