#if canImport(CoreGraphics)
// CGRect's geometry members, initialisers and Equatable conformance live in the CoreGraphics
// overlay; Foundation alone does not make them visible on current macOS SDKs.
import CoreGraphics
#endif
import Foundation

/// The camera housing on a display, derived from the values `NSScreen` reports
/// (`frame`, `safeAreaInsets.top`, `auxiliaryTopLeftArea`, `auxiliaryTopRightArea`).
/// All rectangles use AppKit screen coordinates (origin bottom-left).
public struct NotchGeometry: Equatable, Sendable {
    public let screenFrame: CGRect
    public let notchRect: CGRect
    /// Device pixels per AppKit point on the screen carrying the camera housing.
    public let backingScaleFactor: CGFloat

    /// Returns `nil` when the display has no notch: no top safe-area inset, a missing auxiliary
    /// area on either side, or no gap between the two areas.
    public init?(
        screenFrame: CGRect,
        safeAreaTop: CGFloat,
        leftAuxiliaryWidth: CGFloat?,
        rightAuxiliaryWidth: CGFloat?
    ) {
        guard screenFrame.width.isFinite, screenFrame.height.isFinite,
              screenFrame.width > 0, screenFrame.height > 0,
              safeAreaTop.isFinite, safeAreaTop > 0, safeAreaTop <= screenFrame.height,
              let leftWidth = leftAuxiliaryWidth, let rightWidth = rightAuxiliaryWidth,
              leftWidth.isFinite, rightWidth.isFinite,
              leftWidth >= 0, rightWidth >= 0 else {
            return nil
        }
        let notchWidth = screenFrame.width - leftWidth - rightWidth
        guard notchWidth > 0 else { return nil }
        self.screenFrame = screenFrame
        backingScaleFactor = 1
        notchRect = CGRect(
            x: screenFrame.minX + leftWidth,
            y: screenFrame.maxY - safeAreaTop,
            width: notchWidth,
            height: safeAreaTop
        )
    }

    /// The actual unobscured rectangles are reported in global screen coordinates.
    /// Using the *edges* instead of assuming widths touch the display's edges avoids
    /// a horizontal notch offset on unusual resolutions or multi-display layouts.
    /// Measured boundaries are snapped to device pixels to reduce dark edge seams.
    public init?(
        screenFrame: CGRect,
        safeAreaTop: CGFloat,
        leftAuxiliaryArea: CGRect?,
        rightAuxiliaryArea: CGRect?,
        backingScaleFactor: CGFloat
    ) {
        guard screenFrame.width.isFinite, screenFrame.height.isFinite,
              screenFrame.minX.isFinite, screenFrame.minY.isFinite,
              screenFrame.width > 0, screenFrame.height > 0,
              safeAreaTop.isFinite, safeAreaTop > 0, safeAreaTop <= screenFrame.height,
              backingScaleFactor.isFinite, backingScaleFactor > 0,
              let left = leftAuxiliaryArea, let right = rightAuxiliaryArea,
              left.width.isFinite, right.width.isFinite,
              left.minX.isFinite, right.minX.isFinite,
              left.maxX.isFinite, right.maxX.isFinite,
              left.maxY.isFinite, right.maxY.isFinite,
              left.width > 0, right.width > 0,
              left.height > 0, right.height > 0 else {
            return nil
        }
        let tolerance = 1 / backingScaleFactor
        guard left.minX >= screenFrame.minX - tolerance,
              right.maxX <= screenFrame.maxX + tolerance,
              abs(left.maxY - screenFrame.maxY) <= tolerance,
              abs(right.maxY - screenFrame.maxY) <= tolerance,
              left.maxX < right.minX,
              left.maxX >= screenFrame.minX,
              right.minX <= screenFrame.maxX else {
            return nil
        }
        let leftEdge = (left.maxX * backingScaleFactor).rounded() / backingScaleFactor
        let rightEdge = (right.minX * backingScaleFactor).rounded() / backingScaleFactor
        let top = (screenFrame.maxY * backingScaleFactor).rounded() / backingScaleFactor
        let bottom = ((screenFrame.maxY - safeAreaTop) * backingScaleFactor).rounded()
            / backingScaleFactor
        guard rightEdge > leftEdge, top > bottom,
              leftEdge >= screenFrame.minX - tolerance,
              rightEdge <= screenFrame.maxX + tolerance else {
            return nil
        }
        self.screenFrame = screenFrame
        self.backingScaleFactor = backingScaleFactor
        notchRect = CGRect(
            x: leftEdge, y: bottom, width: rightEdge - leftEdge, height: top - bottom
        )
    }

    /// A frame of `size` hanging from the top edge, centred on the notch and kept on screen.
    /// The width never shrinks below the notch so the panel always covers it.
    public func panelFrame(for size: CGSize) -> CGRect {
        let width = min(max(size.width, notchRect.width), screenFrame.width)
        let height = min(max(size.height, notchRect.height), screenFrame.height)
        let centredX = notchRect.midX - width / 2
        let originX = min(max(centredX, screenFrame.minX), screenFrame.maxX - width)
        // Preserve subpoint placement for the original width-based initializer
        // (scale 1), so rounding cannot uncover the fractional notch edge.
        // Real Retina measurements are snapped to the backing-pixel grid.
        guard backingScaleFactor > 1 else {
            return CGRect(x: originX, y: screenFrame.maxY - height, width: width, height: height)
        }
        let alignedX = (originX * backingScaleFactor).rounded() / backingScaleFactor
        let boundedX = min(max(alignedX, screenFrame.minX), screenFrame.maxX - width)
        return CGRect(x: boundedX, y: screenFrame.maxY - height, width: width, height: height)
    }
}

/// Where the companion is actually shown.
public enum PresentationMode: Equatable, Sendable {
    case notch
    case menuBar

    /// The notch is used only when one exists; `.notch` falls back to the menu bar otherwise
    /// (no notch, lid closed, external display only).
    public static func resolve(preference: PresentationPreference, notchAvailable: Bool) -> PresentationMode {
        switch preference {
        case .menuBar: return .menuBar
        case .automatic, .notch: return notchAvailable ? .notch : .menuBar
        }
    }
}
