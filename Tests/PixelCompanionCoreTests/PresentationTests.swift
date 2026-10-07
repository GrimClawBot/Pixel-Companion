#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation
import PixelCompanionCore
import XCTest

final class PresentationTests: XCTestCase {
    // A 14" MacBook Pro display: 1512 × 982 points with a 185 pt wide, 32 pt tall notch.
    private let screen = CGRect(x: 0, y: 0, width: 1_512, height: 982)
    private let sideWidth: CGFloat = (1_512 - 185) / 2

    private func notch(in frame: CGRect? = nil) -> NotchGeometry? {
        NotchGeometry(
            screenFrame: frame ?? screen,
            safeAreaTop: 32,
            leftAuxiliaryWidth: sideWidth,
            rightAuxiliaryWidth: sideWidth
        )
    }

    func testNotchRectSitsCentredOnTheTopEdge() throws {
        let geometry = try XCTUnwrap(notch())

        XCTAssertEqual(geometry.notchRect, CGRect(x: sideWidth, y: 950, width: 185, height: 32))
        XCTAssertEqual(geometry.notchRect.midX, screen.midX)
    }

    func testNotchUsesTheScreenOriginOnSecondaryDisplays() throws {
        let geometry = try XCTUnwrap(notch(in: screen.offsetBy(dx: -1_512, dy: 400)))

        XCTAssertEqual(geometry.notchRect.minX, -1_512 + sideWidth)
        XCTAssertEqual(geometry.notchRect.maxY, 1_382)
    }

    func testGeometryEqualityComparesScreenAndNotch() throws {
        let geometry = try XCTUnwrap(notch())

        XCTAssertEqual(geometry, try XCTUnwrap(notch()))
        XCTAssertNotEqual(geometry, try XCTUnwrap(notch(in: screen.offsetBy(dx: 0, dy: 100))))
    }

    func testDisplaysWithoutANotchAreRejected() {
        func geometry(top: CGFloat, left: CGFloat?, right: CGFloat?) -> NotchGeometry? {
            NotchGeometry(screenFrame: screen, safeAreaTop: top, leftAuxiliaryWidth: left, rightAuxiliaryWidth: right)
        }
        XCTAssertNil(geometry(top: 0, left: 600, right: 600), "no safe-area inset")
        XCTAssertNil(geometry(top: 32, left: nil, right: 600), "missing auxiliary area")
        XCTAssertNil(geometry(top: 32, left: 756, right: 756), "no gap between the auxiliary areas")
    }

    func testPanelFrameHangsFromTheTopAndCoversTheNotch() throws {
        let geometry = try XCTUnwrap(notch())

        let snapshot = geometry.panelFrame(for: CGSize(width: 360, height: 180))
        XCTAssertEqual(snapshot, CGRect(x: 576, y: 802, width: 360, height: 180))

        let tiny = geometry.panelFrame(for: CGSize(width: 10, height: 10))
        XCTAssertEqual(tiny.size, geometry.notchRect.size)
        XCTAssertEqual(tiny.maxY, screen.maxY)
    }

    func testPanelFrameStaysOnScreen() throws {
        let geometry = try XCTUnwrap(notch())

        let huge = geometry.panelFrame(for: CGSize(width: 5_000, height: 5_000))
        XCTAssertEqual(huge, screen)
    }

    func testPresentationResolution() {
        XCTAssertEqual(PresentationMode.resolve(preference: .automatic, notchAvailable: true), .notch)
        XCTAssertEqual(PresentationMode.resolve(preference: .automatic, notchAvailable: false), .menuBar)
        XCTAssertEqual(PresentationMode.resolve(preference: .notch, notchAvailable: true), .notch)
        XCTAssertEqual(PresentationMode.resolve(preference: .notch, notchAvailable: false), .menuBar)
        XCTAssertEqual(PresentationMode.resolve(preference: .menuBar, notchAvailable: true), .menuBar)
    }

    func testHoverShowsSnapshotAndLeavingCollapses() {
        var interaction = NotchInteraction()

        XCTAssertTrue(interaction.handle(.pointerEntered))
        XCTAssertEqual(interaction.surface, .snapshot)
        XCTAssertTrue(interaction.handle(.pointerExited))
        XCTAssertEqual(interaction.surface, .compact)
        XCTAssertFalse(interaction.handle(.pointerExited))
    }

    func testClickPinsDetailUntilDismissed() {
        var interaction = NotchInteraction()
        interaction.handle(.pointerEntered)
        interaction.handle(.clicked)
        XCTAssertEqual(interaction.surface, .detail)

        XCTAssertFalse(interaction.handle(.pointerExited))
        XCTAssertFalse(interaction.handle(.pointerEntered))
        XCTAssertFalse(interaction.handle(.clicked))
        XCTAssertEqual(interaction.surface, .detail)

        XCTAssertTrue(interaction.handle(.dismissed))
        XCTAssertEqual(interaction.surface, .compact)
    }

    func testClickFromCompactOpensDetailDirectly() {
        var interaction = NotchInteraction()

        interaction.handle(.clicked)
        XCTAssertEqual(interaction.surface, .detail)
    }
}
