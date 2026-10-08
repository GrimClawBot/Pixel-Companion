@testable import PixelCompanion
import XCTest

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
        XCTAssertTrue(LoginItemPresentation.status(.approvalRequired).contains("System Settings"))
        XCTAssertTrue(LoginItemPresentation.status(.unavailable).contains("not find"))
        XCTAssertTrue(LoginItemPresentation.status(.unsupported).contains("temporary QA"))
    }
}
