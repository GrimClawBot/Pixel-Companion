import AppKit
import PixelCompanionCore
import SwiftUI

/// Borderless, non-activating panel that sits over the notch on every Space, above the menu bar.
final class NotchPanel: NSPanel {
    /// Escape while the panel is key.
    var onCancel: (() -> Void)?

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        isMovable = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

/// Reports pointer enter/exit even while the app is inactive, which SwiftUI's `onHover` does not
/// guarantee for an accessory app's panel. Tracking areas never swallow clicks.
final class HoverTrackingView: NSView {
    var onHoverChange: ((Bool) -> Void)?
    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        onHoverChange?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHoverChange?(false)
    }
}

/// Owns the notch panel and maps hover, click and dismiss events to the three notch surfaces.
@MainActor
final class NotchPanelController {
    private let panel: NotchPanel
    private let viewState: NotchViewState
    private var interaction = NotchInteraction()
    private var geometry: NotchGeometry?
    private var outsideClickMonitor: Any?

    init(model: AppModel, openSettings: @escaping () -> Void) {
        panel = NotchPanel()
        viewState = NotchViewState()
        let root = NotchRootView(
            model: model,
            state: viewState,
            onClick: { [weak self] in self?.handle(.clicked) },
            openSettings: openSettings
        )
        let hosting = NSHostingView(rootView: root.environment(\.colorScheme, .dark))
        // The controller sizes the panel per surface; stop the hosting view from resizing it.
        hosting.sizingOptions = []
        hosting.autoresizingMask = [.width, .height]

        let container = HoverTrackingView()
        container.addSubview(hosting)
        container.onHoverChange = { [weak self] inside in
            self?.handle(inside ? .pointerEntered : .pointerExited)
        }
        panel.contentView = container
        hosting.frame = container.bounds
        panel.onCancel = { [weak self] in self?.handle(.dismissed) }
    }

    func show(on geometry: NotchGeometry) {
        self.geometry = geometry
        viewState.notchSize = geometry.notchRect.size
        applyFrame()
        panel.orderFrontRegardless()
    }

    func close() {
        stopOutsideClickMonitor()
        panel.orderOut(nil)
    }

    private func handle(_ event: NotchEvent) {
        guard interaction.handle(event) else { return }
        viewState.surface = interaction.surface
        applyFrame()
        if interaction.surface == .detail {
            panel.makeKey()
            startOutsideClickMonitor()
        } else {
            stopOutsideClickMonitor()
        }
    }

    private func applyFrame() {
        guard let geometry else { return }
        let size = NotchLayout.size(for: interaction.surface, notchSize: geometry.notchRect.size)
        panel.setFrame(geometry.panelFrame(for: size), display: true)
    }

    /// A click in any other app dismisses the pinned detail view. Global mouse monitors need no
    /// accessibility permission.
    private func startOutsideClickMonitor() {
        guard outsideClickMonitor == nil else { return }
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown]
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: clicks) { [weak self] _ in
            MainActor.assumeIsolated { self?.handle(.dismissed) }
        }
    }

    private func stopOutsideClickMonitor() {
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        outsideClickMonitor = nil
    }
}
