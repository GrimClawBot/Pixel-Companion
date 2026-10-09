import Foundation
import ServiceManagement
import SwiftUI

/// macOS owns login registration. Pixel Companion never caches the choice
/// in UserDefaults or creates its own login agents.
enum LoginItemPresentation {
    enum State: Equatable {
        case disabled
        case enabled
        case approvalRequired
        case unavailable
        case unsupported
    }

    static func supported(isBundled: Bool, isTemporaryQABuild: Bool) -> Bool {
        isBundled && !isTemporaryQABuild
    }

    static func isRegistered(_ state: State) -> Bool {
        state == .enabled || state == .approvalRequired
    }

    static func status(_ state: State) -> String {
        switch state {
        case .disabled: return "Off — Pixel Companion will not start at login."
        case .enabled: return "Enabled — macOS will open Pixel Companion at login."
        case .approvalRequired:
            return "Pending approval — open System Settings → General → Login Items to approve, " +
                "or switch Off to cancel the pending request."
        case .unavailable: return "macOS could not find a registered login item."
        case .unsupported: return "Available in an installed release app, not a temporary QA build."
        }
    }
}

@MainActor
protocol LoginItemService {
    var state: LoginItemPresentation.State { get }
    func register() throws
    func unregister() throws
}

/// Thin system-only boundary lets QA tests inspect state transitions without
/// registering or removing actual login items on the developer's Mac.
private struct SystemLoginItemService: LoginItemService {
    var state: LoginItemPresentation.State {
        switch SMAppService.mainApp.status {
        case .enabled: return .enabled
        case .notRegistered: return .disabled
        case .requiresApproval: return .approvalRequired
        case .notFound: return .unavailable
        @unknown default: return .unavailable
        }
    }

    func register() throws { try SMAppService.mainApp.register() }
    func unregister() throws { try SMAppService.mainApp.unregister() }
}

/// Registration changes only from explicit user control; QA app and swift run
/// cannot persist startup for temporary/disposable binaries.
@MainActor
final class LaunchAtLoginController: ObservableObject {
    @Published private(set) var enabled = false
    @Published private(set) var pendingApproval = false
    @Published private(set) var statusText = ""
    @Published private(set) var canChange = false

    private let service: any LoginItemService
    private let isSupportedOverride: Bool?

    init(
        service: (any LoginItemService)? = nil,
        isSupportedOverride: Bool? = nil
    ) {
        self.service = service ?? SystemLoginItemService()
        self.isSupportedOverride = isSupportedOverride
        refresh()
    }

    func refresh() {
        let supported = isSupportedOverride ?? LoginItemPresentation.supported(
            isBundled: Bundle.main.bundleURL.pathExtension.lowercased() == "app",
            isTemporaryQABuild: Bundle.main.object(forInfoDictionaryKey: "PCQAUpdateNumber") != nil
        )
        guard supported else {
            enabled = false
            pendingApproval = false
            canChange = false
            statusText = LoginItemPresentation.status(.unsupported)
            return
        }
        canChange = true
        let state = service.state
        enabled = LoginItemPresentation.isRegistered(state)
        pendingApproval = state == .approvalRequired
        statusText = LoginItemPresentation.status(state)
    }

    func setEnabled(_ value: Bool) {
        guard canChange else { return }
        // Read the current macOS status before making a decision. The login
        // item may have changed in System Settings since our last refresh.
        let registered = LoginItemPresentation.isRegistered(service.state)
        guard value != registered else {
            refresh()
            return
        }
        do {
            if value {
                try service.register()
            } else {
                // A requiresApproval item is ALREADY registered. It must be
                // unregistered to cancel the pending system approval.
                try service.unregister()
            }
            refresh()
        } catch {
            refresh()
            statusText = "macOS couldn't change the login setting: \(error.localizedDescription)"
        }
    }

    func cancelPendingApproval() {
        guard canChange else { return }
        guard service.state == .approvalRequired else {
            // macOS can approve or remove the item after the pending UI
            // rendered. Never leave a stale pending indicator or cancel button.
            refresh()
            return
        }
        setEnabled(false)
    }
}
