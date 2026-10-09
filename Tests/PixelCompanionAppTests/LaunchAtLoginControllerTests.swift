@testable import PixelCompanion
import XCTest

@MainActor
private final class FakeLoginItemService: LoginItemService {
    var state: LoginItemPresentation.State
    var registerCalls = 0
    var unregisterCalls = 0
    var shouldThrow = false

    init(_ state: LoginItemPresentation.State) {
        self.state = state
    }

    func register() throws {
        registerCalls += 1
        if shouldThrow { throw NSError(domain: "FakeLogin", code: 1) }
        state = .enabled
    }

    func unregister() throws {
        unregisterCalls += 1
        if shouldThrow { throw NSError(domain: "FakeLogin", code: 2) }
        state = .disabled
    }
}

@MainActor
final class LaunchAtLoginControllerTests: XCTestCase {
    func testOnlyInstalledNonTemporaryAppAllowsRegistration() {
        XCTAssertTrue(LoginItemPresentation.supported(
            isBundled: true, isTemporaryQABuild: false
        ))
        XCTAssertFalse(LoginItemPresentation.supported(
            isBundled: true, isTemporaryQABuild: true
        ))
        XCTAssertFalse(LoginItemPresentation.supported(
            isBundled: false, isTemporaryQABuild: false
        ))
        XCTAssertFalse(LoginItemPresentation.supported(
            isBundled: false, isTemporaryQABuild: true
        ))
    }

    func testLoginStatusesClearlyCommunicateMacAuthority() {
        XCTAssertTrue(LoginItemPresentation.status(.disabled).contains("Off"))
        XCTAssertTrue(LoginItemPresentation.status(.enabled).contains("Enabled"))
        XCTAssertTrue(LoginItemPresentation.status(.approvalRequired).contains("Pending approval"))
        XCTAssertTrue(LoginItemPresentation.status(.approvalRequired).contains("System Settings"))
        XCTAssertTrue(LoginItemPresentation.status(.approvalRequired).contains("cancel"))
        XCTAssertTrue(LoginItemPresentation.status(.unavailable).contains("not find"))
        XCTAssertTrue(LoginItemPresentation.status(.unsupported).contains("temporary QA"))
    }

    func testApprovalRequiredDisplaysOnAndCanCancelPendingRegistration() {
        let fake = FakeLoginItemService(.approvalRequired)
        let controller = LaunchAtLoginController(service: fake, isSupportedOverride: true)
        XCTAssertTrue(controller.enabled)
        XCTAssertTrue(controller.pendingApproval)
        XCTAssertTrue(controller.canChange)
        controller.setEnabled(false)
        XCTAssertEqual(fake.unregisterCalls, 1)
        XCTAssertEqual(fake.registerCalls, 0)
        XCTAssertFalse(controller.enabled)
        XCTAssertFalse(controller.pendingApproval)
    }

    func testExplicitCancelButtonOnlyActsOnPendingApproval() {
        let fake = FakeLoginItemService(.approvalRequired)
        let controller = LaunchAtLoginController(service: fake, isSupportedOverride: true)
        controller.cancelPendingApproval()
        controller.cancelPendingApproval()
        XCTAssertEqual(fake.unregisterCalls, 1)
        XCTAssertFalse(controller.enabled)
    }

    func testPendingOnDoesNotReregisterAndRefreshTracksMacChanges() {
        let fake = FakeLoginItemService(.approvalRequired)
        let controller = LaunchAtLoginController(service: fake, isSupportedOverride: true)
        controller.setEnabled(true)
        XCTAssertEqual(fake.registerCalls, 0)
        fake.state = .enabled
        controller.refresh()
        XCTAssertTrue(controller.enabled)
        XCTAssertFalse(controller.pendingApproval)
        XCTAssertTrue(controller.statusText.contains("Enabled"))
    }

    func testEnabledAndDisabledTransitionsCallSystemOnlyOnChange() {
        let fake = FakeLoginItemService(.disabled)
        let controller = LaunchAtLoginController(service: fake, isSupportedOverride: true)
        controller.setEnabled(false)
        XCTAssertEqual(fake.unregisterCalls, 0)
        controller.setEnabled(true)
        XCTAssertEqual(fake.registerCalls, 1)
        controller.setEnabled(true)
        XCTAssertEqual(fake.registerCalls, 1)
        controller.setEnabled(false)
        XCTAssertEqual(fake.unregisterCalls, 1)
    }

    func testSystemStateWinsOverStaleUIToggle() {
        let fake = FakeLoginItemService(.disabled)
        let controller = LaunchAtLoginController(service: fake, isSupportedOverride: true)
        fake.state = .approvalRequired
        controller.setEnabled(false)
        XCTAssertEqual(fake.unregisterCalls, 1)
        XCTAssertFalse(controller.enabled)
    }

    func testUnsupportedQABuildCannotChangeSystemService() {
        let fake = FakeLoginItemService(.approvalRequired)
        let controller = LaunchAtLoginController(service: fake, isSupportedOverride: false)
        XCTAssertFalse(controller.canChange)
        XCTAssertFalse(controller.enabled)
        XCTAssertFalse(controller.pendingApproval)
        controller.setEnabled(false)
        controller.setEnabled(true)
        controller.cancelPendingApproval()
        XCTAssertEqual(fake.unregisterCalls, 0)
        XCTAssertEqual(fake.registerCalls, 0)
    }

    func testUnregisterFailureKeepsPendingStateWithError() {
        let fake = FakeLoginItemService(.approvalRequired)
        fake.shouldThrow = true
        let controller = LaunchAtLoginController(service: fake, isSupportedOverride: true)
        controller.cancelPendingApproval()
        XCTAssertEqual(fake.unregisterCalls, 1)
        XCTAssertTrue(controller.enabled)
        XCTAssertTrue(controller.pendingApproval)
        XCTAssertTrue(controller.statusText.contains("couldn't change"))
    }
}
