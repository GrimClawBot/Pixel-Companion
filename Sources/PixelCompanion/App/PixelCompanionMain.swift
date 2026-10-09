import AppKit
import PixelCompanionCore

@main
enum PixelCompanionMain {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        // Accessory: no Dock icon or app menu, without needing an Info.plist (LSUIElement).
        app.setActivationPolicy(.accessory)
        // `NSApplication.delegate` is weak; keep the delegate alive for the whole run loop.
        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel?
    private var settingsWindow: SettingsWindowController?
    private var coordinator: PresentationCoordinator?

    func applicationWillTerminate(_ notification: Notification) {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    @objc private func workspaceDidWake(_ notification: Notification) {
        model?.didWake()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        model?.refreshNotificationPermission()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let model = AppModel(settings: SettingsStore())
        let settingsWindow = SettingsWindowController(model: model)
        let coordinator = PresentationCoordinator(model: model) { [weak settingsWindow] in
            settingsWindow?.show()
        }
        self.model = model
        self.settingsWindow = settingsWindow
        self.coordinator = coordinator
        model.start()
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(workspaceDidWake(_:)),
            name: NSWorkspace.didWakeNotification, object: nil
        )
        coordinator.start()
    }
}
