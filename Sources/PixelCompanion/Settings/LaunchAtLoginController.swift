import Foundation
import ServiceManagement
import SwiftUI

/// macOS owns this preference. We never write it to UserDefaults or create login agents.
enum LoginItemPresentation {
    enum State {
        case disabled
        case enabled
        case approvalRequired
        case unavailable
        case unsupported
    }

    static func supported(isBundled: Bool, isTemporaryQABuild: Bool) -> Bool {
        isBundled && !isTemporaryQABuild
    }

    static func status(_ state: State) -> String {
        switch state {
        case .disabled: return "Off — Pixel Companion will not start at login."
        case .enabled: return "Enabled — macOS will open Pixel Companion at login."
        case .approvalRequired: return "Open System Settings → General → Login Items to approve."
        case .unavailable: return "macOS could not find a registered login item."
        case .unsupported: return "Available in an installed release app, not a temporary QA build."
        }
    }
}

/// Registration is performed only on an explicit user switch action.
/// QA builds and swift-run cannot accidentally persist startup for a disposable binary.
@MainActor
final class LaunchAtLoginController: ObservableObject {
    @Published private(set) var enabled = false
    @Published private(set) var statusText = ""
    @Published private(set) var canChange = false

    init() {
        refresh()
    }

    func refresh() {
        let supported = LoginItemPresentation.supported(
            isBundled: Bundle.main.bundleURL.pathExtension.lowercased() == "app",
            isTemporaryQABuild: Bundle.main.object(forInfoDictionaryKey: "PCQAUpdateNumber") != nil
        )
        guard supported else {
            enabled = false
            canChange = false
            statusText = LoginItemPresentation.status(.unsupported)
            return
        }
        canChange = true
        switch SMAppService.mainApp.status {
        case .enabled:
            enabled = true
            statusText = LoginItemPresentation.status(.enabled)
        case .notRegistered:
            enabled = false
            statusText = LoginItemPresentation.status(.disabled)
        case .requiresApproval:
            enabled = false
            statusText = LoginItemPresentation.status(.approvalRequired)
        case .notFound:
            enabled = false
            statusText = LoginItemPresentation.status(.unavailable)
        @unknown default:
            enabled = false
            statusText = LoginItemPresentation.status(.unavailable)
        }
    }

    func setEnabled(_ value: Bool) {
        guard canChange, value != enabled else { return }
        do {
            if value {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            refresh()
        } catch {
            refresh()
            statusText = "macOS couldn't change the login setting: \(error.localizedDescription)"
        }
    }
}
