import Foundation
import PixelCompanionCore
@testable import PixelCompanion
import XCTest

final class FeedFreshnessTests: XCTestCase {
    func testMissingSuccessCannotBeLabeledCurrent() {
        let now = Date(timeIntervalSince1970: 1_000)
        XCTAssertEqual(
            FeedFreshness.evaluate(
                isPaperclip: true, state: .connected, lastSuccess: nil, now: now
            ), .connecting
        )
        XCTAssertEqual(
            FeedFreshness.evaluate(
                isPaperclip: true, state: .connecting, lastSuccess: now, now: now
            ), .connecting
        )
        XCTAssertFalse(FeedFreshness.connecting.canPresentAsLive)
    }

    func testStaleThresholdAndRecovery() {
        let now = Date(timeIntervalSince1970: 1_000)
        let recent = now.addingTimeInterval(-19)
        let old = now.addingTimeInterval(-21)
        XCTAssertEqual(
            FeedFreshness.evaluate(isPaperclip: true, state: .connected, lastSuccess: recent, now: now),
            .current
        )
        XCTAssertEqual(
            FeedFreshness.evaluate(isPaperclip: true, state: .connected, lastSuccess: old, now: now),
            .stale
        )
        XCTAssertFalse(FeedFreshness.stale.canPresentAsLive)
        XCTAssertNotNil(FeedFreshness.stale.warning)
        XCTAssertEqual(
            FeedFreshness.evaluate(isPaperclip: true, state: .connected, lastSuccess: now, now: now),
            .current
        )
        XCTAssertTrue(FeedFreshness.current.canPresentAsLive)
    }

    func testFailuresNeverShowCachedLiveStatus() {
        let before = Date(timeIntervalSince1970: 100)
        for state in [ConnectionState.error, .disconnected] {
            XCTAssertEqual(
                FeedFreshness.evaluate(
                    isPaperclip: true, state: state, lastSuccess: before,
                    now: before.addingTimeInterval(2)
                ), .unavailable
            )
        }
        XCTAssertFalse(FeedFreshness.unavailable.canPresentAsLive)
        XCTAssertNotNil(FeedFreshness.unavailable.warning)
    }

    func testMocksRemainUnaffectedAndClockSkewFailsClosed() {
        let now = Date(timeIntervalSince1970: 1_000)
        XCTAssertEqual(
            FeedFreshness.evaluate(isPaperclip: false, state: .error, lastSuccess: nil),
            .notApplicable
        )
        XCTAssertTrue(FeedFreshness.notApplicable.canPresentAsLive)
        XCTAssertEqual(
            FeedFreshness.evaluate(
                isPaperclip: true, state: .connected,
                lastSuccess: now.addingTimeInterval(5), now: now
            ), .stale
        )
    }
}
