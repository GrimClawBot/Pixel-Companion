import Foundation
@testable import PixelCompanion
import XCTest

@MainActor
final class LocalAgentEventPresentationTests: XCTestCase {
    private let reference = Date(timeIntervalSince1970: 1_800_000_000)

    func testCodexStatusBecomesHistoricalWithoutAnyNewMarker() {
        let label = LocalAgentEventPresentation.codexLabel(reference, now: reference)
        XCTAssertEqual(label, "Turn completion reported")
        XCTAssertEqual(
            LocalAgentEventPresentation.codexLabel(
                reference, now: reference.addingTimeInterval(120)
            ),
            "Turn completion reported"
        )
        XCTAssertEqual(
            LocalAgentEventPresentation.codexLabel(
                reference, now: reference.addingTimeInterval(121)
            ),
            "Previous turn completion (not live)"
        )
    }

    func testClaudeStopAndSessionEndBecomeHistorical() {
        for event in ClaudeHookEvent.allCases {
            XCTAssertEqual(
                LocalAgentEventPresentation.claudeLabel(
                    event, at: reference, now: reference
                ),
                event.label
            )
            XCTAssertEqual(
                LocalAgentEventPresentation.claudeLabel(
                    event, at: reference, now: reference.addingTimeInterval(121)
                ),
                event.label + " (previous event, not live)"
            )
        }
    }

    func testDigestDistinguishesEarlierEventsFromRecentEvents() {
        XCTAssertEqual(
            LocalAgentEventPresentation.attentionTimingLabel(reference, at: reference),
            "Recently observed"
        )
        XCTAssertEqual(
            LocalAgentEventPresentation.attentionTimingLabel(
                reference, at: reference.addingTimeInterval(121)
            ),
            "Earlier event, not live"
        )
        XCTAssertEqual(
            LocalAgentEventPresentation.timelineTimingLabel(
                reference, at: reference.addingTimeInterval(121)
            ),
            "Earlier event, not live"
        )
    }

    func testDigestStopsShowingExpiredHistory() {
        XCTAssertTrue(LocalAgentEventPresentation.attentionIsVisible(reference, at: reference))
        XCTAssertTrue(
            LocalAgentEventPresentation.attentionIsVisible(
                reference, at: reference.addingTimeInterval(1_800)
            )
        )
        XCTAssertFalse(
            LocalAgentEventPresentation.attentionIsVisible(
                reference, at: reference.addingTimeInterval(1_801)
            )
        )
    }

    func testUntrustedFutureEventsAreNotDescribedAsRecent() {
        let future = reference.addingTimeInterval(31)
        XCTAssertFalse(
            LocalAgentEventPresentation.attentionIsVisible(future, at: reference)
        )
        XCTAssertEqual(
            LocalAgentEventPresentation.timelineTimingLabel(future, at: reference),
            "Earlier event, not live"
        )
        XCTAssertEqual(
            LocalAgentEventPresentation.attentionTimingLabel(future, at: reference),
            "Earlier event, not live"
        )
    }
}
