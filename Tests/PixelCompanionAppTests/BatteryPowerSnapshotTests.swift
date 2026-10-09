import Foundation
import PixelCompanionCore
@testable import PixelCompanion
import XCTest

final class BatteryPowerSnapshotTests: XCTestCase {
    private func report(
        current: NSNumber = 65, maximum: NSNumber = 100,
        charging: NSNumber? = true, state: String? = "AC Power",
        type: String = "InternalBattery", present: NSNumber = true
    ) -> [String: Any] {
        var result: [String: Any] = [
            "Type": type, "Is Present": present,
            "Current Capacity": current, "Max Capacity": maximum
        ]
        if let charging { result["Is Charging"] = charging }
        if let state { result["Power Source State"] = state }
        return result
    }

    private func snapshot(
        _ sources: [[String: Any]], lowPower: Bool = false
    ) -> BatteryPowerSnapshot {
        BatteryPowerSnapshot.reported(by: sources, lowPowerMode: lowPower)
    }

    func testReportedBatteryChargingAndPowerState() {
        let value = snapshot([report()], lowPower: true)
        XCTAssertEqual(value.percentage, 65)
        XCTAssertEqual(value.isCharging, true)
        XCTAssertEqual(value.isOnExternalPower, true)
        XCTAssertTrue(value.isLowPowerMode)
        XCTAssertEqual(value.powerLabel, "Charging")
    }

    func testBatteryDischargingAndOnAdapterWithoutChargingAreDistinguished() {
        let discharging = snapshot([report(charging: false, state: "Battery Power")])
        XCTAssertEqual(discharging.powerLabel, "Running on battery")
        XCTAssertEqual(discharging.isOnExternalPower, false)
        let onAdapter = snapshot([report(charging: false)])
        XCTAssertEqual(onAdapter.powerLabel, "Power adapter connected")
        XCTAssertEqual(onAdapter.isCharging, false)
    }

    func testNoBatteryOrAbsentBatteryDoesNotInventReadings() {
        let empty = snapshot([], lowPower: true)
        XCTAssertNil(empty.percentage)
        XCTAssertNil(empty.isCharging)
        XCTAssertNil(empty.isOnExternalPower)
        XCTAssertTrue(empty.isLowPowerMode)
        let absent = snapshot([report(present: false)])
        XCTAssertNil(absent.percentage)
        let powerSupply = snapshot([report(type: "UPS Power")])
        XCTAssertNil(powerSupply.percentage)
    }

    func testMissingAndInvalidCapacityRemainUnknown() {
        let missing = snapshot([[
            "Type": "InternalBattery", "Is Present": true,
            "Power Source State": "Battery Power"
        ]])
        XCTAssertNil(missing.percentage)
        XCTAssertEqual(missing.powerLabel, "Running on battery")
        let invalid = snapshot([report(current: -1)])
        XCTAssertNil(invalid.percentage)
        XCTAssertNil(snapshot([report(current: 101)]).percentage)
        XCTAssertNil(snapshot([report(maximum: 0)]).percentage)
        XCTAssertNil(snapshot([report(current: NSNumber(value: Double.infinity))]).percentage)
    }

    func testCapacityConversionAndBoundariesAreCorrect() {
        XCTAssertEqual(snapshot([report(current: 0)]).percentage, 0)
        XCTAssertEqual(snapshot([report(current: 100)]).percentage, 100)
        XCTAssertEqual(snapshot([report(current: 29, maximum: 60)]).percentage, 48)
    }

    func testChargingAndExternalPowerMissingAreNotGuessed() {
        let value = snapshot([report(charging: nil, state: nil)])
        XCTAssertNil(value.isCharging)
        XCTAssertNil(value.isOnExternalPower)
        XCTAssertEqual(value.powerLabel, "Power source not reported")
    }

    func testSnapshotNeverStoresRawHardwareDescriptions() {
        let source: [String: Any] = [
            "Type": "InternalBattery", "Is Present": true,
            "Current Capacity": 50, "Max Capacity": 100,
            "Hardware Serial Number": "secret-test-serial",
            "Name": "My MacBook"
        ]
        let value = snapshot([source])
        XCTAssertEqual(value.percentage, 50)
        XCTAssertFalse(String(reflecting: value).contains("secret-test-serial"))
        XCTAssertFalse(String(reflecting: value).contains("My MacBook"))
    }

    func testPreferenceDefaultsOffPersistsAndDoesNotAffectOtherUtilities() {
        let suite = "PixelCompanionBatteryTests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SettingsStore(defaults: defaults)
        XCTAssertFalse(store.batteryHUDEnabled)
        XCTAssertFalse(store.focusTimerEnabled)
        store.batteryHUDEnabled = true
        let restored = SettingsStore(defaults: defaults)
        XCTAssertTrue(restored.batteryHUDEnabled)
        XCTAssertFalse(restored.focusTimerEnabled)
        store.batteryHUDEnabled = false
        XCTAssertFalse(restored.batteryHUDEnabled)
    }
}
