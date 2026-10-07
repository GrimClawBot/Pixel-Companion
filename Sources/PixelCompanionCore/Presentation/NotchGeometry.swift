import Foundation

/// The camera housing on a display, derived from the values `NSScreen` reports
/// (`frame`, `safeAreaInsets.top`, `auxiliaryTopLeftArea`, `auxiliaryTopRightArea`).
/// All rectangles use AppKit screen coordinates (origin bottom-left).
public struct NotchGeometry: Equatable, Sendable {
    public let screenFrame: CGRect
    public let notchRect: CGRect

    /// Returns `nil` when the display has no notch: no top safe-area inset, a missing auxiliary
    /// area on either side, or no gap between the two areas.
    public init?(
        screenFrame: CGRect,
        safeAreaTop: CGFloat,
        leftAuxiliaryWidth: CGFloat?,
        rightAuxiliaryWidth: CGFloat?
    ) {
        guard safeAreaTop > 0, let leftWidth = leftAuxiliaryWidth, let rightWidth = rightAuxiliaryWidth else {
            return nil
        }
        let notchWidth = screenFrame.width - leftWidth - rightWidth
        guard notchWidth > 0 else { return nil }
        self.screenFrame = screenFrame
        notchRect = CGRect(
            x: screenFrame.minX + leftWidth,
            y: screenFrame.maxY - safeAreaTop,
            width: notchWidth,
            height: safeAreaTop
        )
    }

    /// A frame of `size` hanging from the top edge, centred on the notch and kept on screen.
    /// The width never shrinks below the notch so the panel always covers it.
    public func panelFrame(for size: CGSize) -> CGRect {
        let width = min(max(size.width, notchRect.width), screenFrame.width)
        let height = min(max(size.height, notchRect.height), screenFrame.height)
        let centredX = notchRect.midX - width / 2
        let originX = min(max(centredX, screenFrame.minX), screenFrame.maxX - width)
        return CGRect(x: originX, y: screenFrame.maxY - height, width: width, height: height)
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
