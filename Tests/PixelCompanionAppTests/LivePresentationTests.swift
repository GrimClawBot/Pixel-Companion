import Foundation
import PixelCompanionCore
@testable import PixelCompanion
import XCTest

final class LivePresentationTests: XCTestCase {
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
