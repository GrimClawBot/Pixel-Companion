import Foundation
import PixelCompanionCore
@testable import PixelCompanion
import XCTest

final class CompanionRefreshCadenceTests: XCTestCase {
    private func cadence(
        mock: Bool = false, lowPower: Bool = false, conserve: Bool = true,
        mockInterval: TimeInterval = 4, paperclipInterval: TimeInterval = 5
    ) -> TimeInterval {
        CompanionRefreshCadence.interval(
            isMock: mock, mockInterval: mockInterval,
            paperclipInterval: paperclipInterval,
            conserveEnergy: conserve, lowPowerMode: lowPower
        )
    }

    func testPaperclipKeepsNormalRefreshWhenNotConservingOrPowerIsNormal() {
        XCTAssertEqual(cadence(), 5)
        XCTAssertEqual(cadence(lowPower: false, conserve: true), 5)
        XCTAssertEqual(cadence(lowPower: true, conserve: false), 5)
    }

    func testLowPowerUsesConservativeIntervalWithoutAcceleratingAnExistingLongerOne() {
        XCTAssertEqual(cadence(lowPower: true), 20)
        XCTAssertEqual(cadence(lowPower: true, paperclipInterval: 30), 30)
        XCTAssertEqual(CompanionRefreshCadence.lowPowerPaperclipInterval, 20)
    }

    func testMockScriptNeverChangesItsExplicitSpeedInLowPower() {
        for interval in [1.0, 4, 10, 30] {
            XCTAssertEqual(
                cadence(mock: true, lowPower: true, mockInterval: interval),
                interval
            )
            XCTAssertEqual(
                cadence(mock: true, lowPower: false, mockInterval: interval),
                interval
            )
        }
    }

    func testEnergyPreferenceDefaultsOnAndPersistsWithoutChangingOtherSettings() {
        let key = "PixelCompanionEnergyTests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: key)!
        defer { defaults.removePersistentDomain(forName: key) }
        let store = SettingsStore(defaults: defaults)
        XCTAssertTrue(store.conserveEnergy)
        store.conserveEnergy = false
        store.paperclipBaseURL = "http://127.0.0.1:3100"
        let restored = SettingsStore(defaults: defaults)
        XCTAssertFalse(restored.conserveEnergy)
        XCTAssertEqual(restored.paperclipBaseURL, "http://127.0.0.1:3100")
        restored.conserveEnergy = true
        XCTAssertTrue(store.conserveEnergy)
    }
}
