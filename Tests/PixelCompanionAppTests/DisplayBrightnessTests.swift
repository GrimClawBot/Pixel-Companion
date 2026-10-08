import Foundation
import PixelCompanionCore
@testable import PixelCompanion
import XCTest

final class DisplayBrightnessTests: XCTestCase {
    func testFiniteReportedScalarsMapToBoundedPercentages() {
        XCTAssertEqual(DisplayBrightnessSnapshot.validated(0).percentage, 0)
        XCTAssertEqual(DisplayBrightnessSnapshot.validated(0.5).percentage, 50)
        XCTAssertEqual(DisplayBrightnessSnapshot.validated(1).percentage, 100)
        XCTAssertEqual(DisplayBrightnessSnapshot.validated(0.495).percentage, 50)
    }

    func testInvalidOrUnreportedBrightnessNeverInventsPercentage() {
        for scalar in [-0.1, 1.01, Double.nan, .infinity, -.infinity] {
            XCTAssertEqual(DisplayBrightnessSnapshot.validated(scalar), .unavailable)
        }
        XCTAssertEqual(DisplayBrightnessSnapshot.validated(nil), .unavailable)
    }

    func testAmbiguousOrAbsentDisplayServiceNeverAttributesBrightness() {
        XCTAssertNil(DisplayBrightnessSelection.unambiguous(0.65, serviceCount: 0))
        XCTAssertNil(DisplayBrightnessSelection.unambiguous(0.65, serviceCount: 2))
        XCTAssertNil(DisplayBrightnessSelection.unambiguous(0.65, serviceCount: 3))
        XCTAssertNil(DisplayBrightnessSelection.unambiguous(nil, serviceCount: 1))
        XCTAssertEqual(DisplayBrightnessSelection.unambiguous(0.65, serviceCount: 1), 0.65)
    }

    @MainActor
    func testDefaultOffNeverReadsPhysicalDisplay() {
        var reads = 0
        let monitor = DisplayBrightnessMonitor(readBrightness: {
            reads += 1
            return 0.4
        })
        monitor.refresh()
        XCTAssertEqual(reads, 0)
        XCTAssertEqual(monitor.snapshot, .unavailable)
        XCTAssertFalse(monitor.enabled)
        XCTAssertEqual(DisplayBrightnessMonitor.refreshInterval, 15)
    }

    @MainActor
    func testExplicitEnableReadsAndDisableClearsEphemeralSnapshot() {
        var reads = 0
        let monitor = DisplayBrightnessMonitor(readBrightness: {
            reads += 1
            return 0.72
        })
        monitor.configure(enabled: true)
        XCTAssertEqual(reads, 1)
        XCTAssertEqual(monitor.snapshot.percentage, 72)
        monitor.configure(enabled: false)
        XCTAssertNil(monitor.snapshot.percentage)
        monitor.refresh()
        XCTAssertEqual(reads, 1)
    }

    @MainActor
    func testUnavailableHardwareClearsPreviouslyReadValue() {
        var value: Double? = 0.64
        let monitor = DisplayBrightnessMonitor(readBrightness: { value })
        monitor.configure(enabled: true)
        XCTAssertEqual(monitor.snapshot.percentage, 64)
        value = nil
        monitor.refresh()
        XCTAssertNil(monitor.snapshot.percentage)
        monitor.configure(enabled: false)
    }

    @MainActor
    func testRedundantEnableDoesNotCreateAnExtraRead() {
        var reads = 0
        let monitor = DisplayBrightnessMonitor(readBrightness: {
            reads += 1
            return 0.2
        })
        monitor.configure(enabled: true)
        monitor.configure(enabled: true)
        XCTAssertEqual(reads, 1)
        monitor.configure(enabled: false)
    }

    func testBrightnessPreferenceOffByDefaultAndIndependent() {
        let suite = "DisplayBrightness-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(defaults: defaults)
        XCTAssertFalse(settings.displayBrightnessHUDEnabled)
        settings.displayBrightnessHUDEnabled = true
        XCTAssertTrue(SettingsStore(defaults: defaults).displayBrightnessHUDEnabled)
        XCTAssertFalse(settings.outputVolumeHUDEnabled)
        XCTAssertFalse(settings.batteryHUDEnabled)
        XCTAssertFalse(settings.calendarWidgetEnabled)
        XCTAssertFalse(settings.musicWidgetEnabled)
        settings.reset()
        XCTAssertFalse(settings.displayBrightnessHUDEnabled)
    }
}
