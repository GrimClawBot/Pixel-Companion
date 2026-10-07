import PixelCompanionCore
@testable import PixelCompanion
import XCTest

final class PresentationCoordinatorTests: XCTestCase {
    func testEnvironmentChangesResetNotchInteraction() {
        let plan = PresentationTransitionPlan.resolve(
            preference: .automatic,
            notchAvailable: true,
            reason: .environmentChange
        )

        XCTAssertEqual(plan.mode, .notch)
        XCTAssertTrue(plan.resetNotchInteraction)
    }

    func testStartupAndPreferenceChangesDoNotForceReset() {
        let startup = PresentationTransitionPlan.resolve(
            preference: .automatic,
            notchAvailable: true,
            reason: .startup
        )
        let preference = PresentationTransitionPlan.resolve(
            preference: .notch,
            notchAvailable: true,
            reason: .preference
        )

        let followUp = PresentationTransitionPlan.resolve(
            preference: .automatic,
            notchAvailable: true,
            reason: .environmentFollowUp
        )

        XCTAssertFalse(startup.resetNotchInteraction)
        XCTAssertFalse(preference.resetNotchInteraction)
        XCTAssertFalse(followUp.resetNotchInteraction)
    }

    func testEnvironmentChangeFallsBackToMenuBarWithoutNotch() {
        let plan = PresentationTransitionPlan.resolve(
            preference: .notch,
            notchAvailable: false,
            reason: .environmentChange
        )

        XCTAssertEqual(plan.mode, .menuBar)
        XCTAssertTrue(plan.resetNotchInteraction)
    }

    func testMenuBarPreferenceRemainsMenuBarWhenNotchExists() {
        let plan = PresentationTransitionPlan.resolve(
            preference: .menuBar,
            notchAvailable: true,
            reason: .preference
        )

        XCTAssertEqual(plan.mode, .menuBar)
        XCTAssertFalse(plan.resetNotchInteraction)
    }
}
