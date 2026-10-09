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

    func testAuxiliaryRectanglesAnchorFromTheirActualGlobalEdges() throws {
        let frame = CGRect(x: -1_600, y: 400, width: 1_512, height: 982)
        let left = CGRect(x: -1_590, y: 1_350, width: 630, height: 32)
        let right = CGRect(x: -760, y: 1_350, width: 640, height: 32)
        let geometry = try XCTUnwrap(NotchGeometry(
            screenFrame: frame, safeAreaTop: 32,
            leftAuxiliaryArea: left, rightAuxiliaryArea: right, backingScaleFactor: 2
        ))
        XCTAssertEqual(
            geometry.notchRect, CGRect(x: -960, y: 1_350, width: 200, height: 32)
        )
        XCTAssertEqual(geometry.backingScaleFactor, 2)
        let compact = geometry.panelFrame(for: CGSize(width: 200, height: 64))
        XCTAssertEqual(compact, CGRect(x: -960, y: 1_318, width: 200, height: 64))
    }

    func testSubpointNotchEdgesAlignToRetinaPixelGrid() throws {
        let left = CGRect(x: 0, y: 950, width: 663.1, height: 32)
        let right = CGRect(x: 848.9, y: 950, width: 663.1, height: 32)
        let geometry = try XCTUnwrap(NotchGeometry(
            screenFrame: screen, safeAreaTop: 32,
            leftAuxiliaryArea: left, rightAuxiliaryArea: right, backingScaleFactor: 2
        ))
        XCTAssertEqual(geometry.notchRect.minX, 663)
        XCTAssertEqual(geometry.notchRect.maxX, 849)
        XCTAssertEqual(geometry.notchRect.width, 186)
        let frame = geometry.panelFrame(for: CGSize(width: 401, height: 220))
        XCTAssertEqual((frame.minX * 2).truncatingRemainder(dividingBy: 1), 0)
        XCTAssertEqual(frame.maxY, screen.maxY)
    }

    func testInvalidOrNotchlessTopAuxiliaryRectanglesFailClosed() {
        let left = CGRect(x: 0, y: 950, width: sideWidth, height: 32)
        let right = CGRect(x: screen.maxX - sideWidth, y: 950, width: sideWidth, height: 32)
        func candidate(
            top: CGFloat = 32, leftArea: CGRect?, rightArea: CGRect?, scale: CGFloat = 2
        ) -> NotchGeometry? {
            NotchGeometry(
                screenFrame: screen, safeAreaTop: top,
                leftAuxiliaryArea: leftArea, rightAuxiliaryArea: rightArea,
                backingScaleFactor: scale
            )
        }
        XCTAssertNil(candidate(top: 0, leftArea: left, rightArea: right))
        XCTAssertNil(candidate(leftArea: nil, rightArea: right))
        XCTAssertNil(candidate(leftArea: left, rightArea: nil))
        XCTAssertNil(candidate(leftArea: left, rightArea: left))
        XCTAssertNil(candidate(leftArea: left, rightArea: right, scale: 0))
        XCTAssertNil(candidate(leftArea: left, rightArea: right, scale: .infinity))
        XCTAssertNil(candidate(top: .nan, leftArea: left, rightArea: right))
        XCTAssertNil(candidate(leftArea: left.offsetBy(dx: -30, dy: 0), rightArea: right))
        XCTAssertNil(candidate(leftArea: left, rightArea: right.offsetBy(dx: 30, dy: 0)))
        XCTAssertNil(candidate(leftArea: left.offsetBy(dx: 0, dy: -10), rightArea: right))
        XCTAssertNil(candidate(leftArea: left, rightArea: right.offsetBy(dx: 0, dy: -10)))
        XCTAssertNil(candidate(leftArea: left, rightArea: .zero))
    }

    func testValidMeasuredNotchDoesNotChangeExistingExpandedSizes() throws {
        let left = CGRect(x: 0, y: 950, width: sideWidth, height: 32)
        let right = CGRect(x: screen.maxX - sideWidth, y: 950, width: sideWidth, height: 32)
        let actual = try XCTUnwrap(NotchGeometry(
            screenFrame: screen, safeAreaTop: 32,
            leftAuxiliaryArea: left, rightAuxiliaryArea: right, backingScaleFactor: 2
        ))
        let former = try XCTUnwrap(notch())
        XCTAssertEqual(actual.notchRect, former.notchRect)
        XCTAssertEqual(actual.panelFrame(for: CGSize(width: 400, height: 232)),
                       former.panelFrame(for: CGSize(width: 400, height: 232)))
        XCTAssertEqual(actual.panelFrame(for: CGSize(width: 440, height: 472)),
                       former.panelFrame(for: CGSize(width: 440, height: 472)))
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
