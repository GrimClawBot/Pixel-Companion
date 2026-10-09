import CoreGraphics
@testable import PixelCompanion
import XCTest

final class NotchLayoutTests: XCTestCase {
    private let notchSize = CGSize(width: 185, height: 32)

    func testCompactSurfaceStaysWithinNotchWidthAndExtendsBelowIt() {
        XCTAssertEqual(
            NotchLayout.size(for: .compact, notchSize: notchSize),
            CGSize(width: 185, height: 64)
        )
        XCTAssertEqual(NotchLayout.compactBarHeight, 32)
    }

    func testCompactStatusShowsFreshMoodButNeverLabelsStaleWorkingAsLive() {
        XCTAssertEqual(
            CompactBarPresentation.status(mood: .working, feedFreshness: .current),
            "Working"
        )
        XCTAssertEqual(
            CompactBarPresentation.status(mood: .coding, feedFreshness: .notApplicable),
            "Coding"
        )
        XCTAssertEqual(
            CompactBarPresentation.status(mood: .working, feedFreshness: .stale),
            "Updates delayed"
        )
        XCTAssertEqual(
            CompactBarPresentation.status(mood: .working, feedFreshness: .unavailable),
            "Disconnected"
        )
        XCTAssertEqual(
            CompactBarPresentation.status(mood: .working, feedFreshness: .connecting),
            "Connecting"
        )
    }

    func testCompactCharacterNeverShowsWorkingWhenSourceIsStale() {
        for state in [FeedFreshness.connecting, .stale, .unavailable] {
            XCTAssertEqual(
                CompactBarPresentation.displayMood(mood: .working, feedFreshness: state),
                .offline
            )
        }
        XCTAssertEqual(
            CompactBarPresentation.displayMood(mood: .working, feedFreshness: .current),
            .working
        )
        XCTAssertEqual(
            CompactBarPresentation.displayMood(mood: .coding, feedFreshness: .notApplicable),
            .coding
        )
    }

    func testStatusIndicatorMatchesActualFeedFreshness() {
        XCTAssertEqual(
            CompactBarPresentation.indicator(mood: .working, feedFreshness: .current),
            CharacterMood.working.symbolName
        )
        XCTAssertEqual(
            CompactBarPresentation.indicator(mood: .working, feedFreshness: .stale),
            "wifi.exclamationmark"
        )
        XCTAssertEqual(
            CompactBarPresentation.indicator(mood: .working, feedFreshness: .unavailable),
            "wifi.slash"
        )
        XCTAssertEqual(
            CompactBarPresentation.indicator(mood: .working, feedFreshness: .connecting),
            "arrow.triangle.2.circlepath"
        )
    }

    func testSnapshotExpandsBelowAndBeyondNotchOnlyDuringInteraction() {
        XCTAssertEqual(
            NotchLayout.size(for: .snapshot, notchSize: notchSize),
            CGSize(width: 400, height: 232)
        )
    }

    func testDetailExpandsBelowAndBeyondNotchOnlyDuringInteraction() {
        XCTAssertEqual(
            NotchLayout.size(for: .detail, notchSize: notchSize),
            CGSize(width: 440, height: 472)
        )
    }

    func testExpandedSurfacesNeverShrinkBelowWideNotch() {
        let wideNotch = CGSize(width: 500, height: 40)
        XCTAssertEqual(
            NotchLayout.size(for: .snapshot, notchSize: wideNotch),
            CGSize(width: 500, height: 240)
        )
        XCTAssertEqual(
            NotchLayout.size(for: .detail, notchSize: wideNotch),
            CGSize(width: 500, height: 480)
        )
    }
}
