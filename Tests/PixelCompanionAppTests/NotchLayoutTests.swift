import CoreGraphics
@testable import PixelCompanion
import XCTest

final class NotchLayoutTests: XCTestCase {
    private let notchSize = CGSize(width: 185, height: 32)

    func testCompactSurfaceStaysWithinNotchWidthAndExtendsBelowIt() {
        XCTAssertEqual(
            NotchLayout.size(for: .compact, notchSize: notchSize),
            CGSize(width: 185, height: 56)
        )
        XCTAssertEqual(NotchLayout.compactBarHeight, 24)
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
