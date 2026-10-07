import AppKit
import PixelCompanionCore

extension NSScreen {
    /// The notch on this screen, from `safeAreaInsets` and the auxiliary top areas; `nil` if none.
    var notchGeometry: NotchGeometry? {
        NotchGeometry(
            screenFrame: frame,
            safeAreaTop: safeAreaInsets.top,
            leftAuxiliaryWidth: auxiliaryTopLeftArea?.width,
            rightAuxiliaryWidth: auxiliaryTopRightArea?.width
        )
    }
}

/// Chooses between the notch panel and the menu-bar item, and re-evaluates whenever displays,
/// sleep state or the presentation preference change.
@MainActor
final class PresentationCoordinator {
    private let model: AppModel
    private let openSettings: () -> Void
    private var notchController: NotchPanelController?
    private var statusController: StatusItemController?
    /// Lives as long as the app, so the observers are never removed.
    private var observers: [NSObjectProtocol] = []

    init(model: AppModel, openSettings: @escaping () -> Void) {
        self.model = model
        self.openSettings = openSettings
    }

    func start() {
        observe(NSApplication.didChangeScreenParametersNotification, in: .default)
        let workspace = NSWorkspace.shared.notificationCenter
        observe(NSWorkspace.didWakeNotification, in: workspace)
        observe(NSWorkspace.screensDidWakeNotification, in: workspace)
        model.onPresentationPreferenceChange = { [weak self] in self?.refresh() }
        refresh()
    }

    func refresh() {
        // Prefer the built-in display: with the lid closed or on an external-only setup no screen
        // reports a notch and the companion moves to the menu bar.
        let notched = NSScreen.screens.lazy.compactMap(\.notchGeometry).first
        let mode = PresentationMode.resolve(preference: model.presentation, notchAvailable: notched != nil)
        model.updatePresentation(mode: mode, notchAvailable: notched != nil)

        if mode == .notch, let notched {
            statusController?.remove()
            statusController = nil
            let controller = notchController ?? NotchPanelController(model: model, openSettings: openSettings)
            notchController = controller
            controller.show(on: notched)
        } else {
            notchController?.close()
            notchController = nil
            if statusController == nil {
                statusController = StatusItemController(model: model, openSettings: openSettings)
            }
        }
    }

    private func observe(_ name: Notification.Name, in center: NotificationCenter) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleRefresh() }
        }
        observers.append(token)
    }

    /// Screen parameters settle shortly after wake and display changes; refresh now and once more.
    private func scheduleRefresh() {
        refresh()
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            self?.refresh()
        }
    }
}
