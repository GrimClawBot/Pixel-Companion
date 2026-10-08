import Foundation
import PixelCompanionCore
@testable import PixelCompanion
import XCTest

final class OutputVolumeTests: XCTestCase {
    func testValidRangeAndRoundedPercentage() {
        XCTAssertEqual(
            OutputVolumeSnapshot.validated(.init(scalar: 0, isMuted: false)).percentage, 0
        )
        XCTAssertEqual(
            OutputVolumeSnapshot.validated(.init(scalar: 0.495, isMuted: true)).percentage, 50
        )
        XCTAssertEqual(
            OutputVolumeSnapshot.validated(.init(scalar: 1, isMuted: nil)).percentage, 100
        )
    }

    func testInvalidOrUnreportedScalarNeverInventsVolume() {
        for scalar in [-0.1, 1.01, .nan, .infinity, -.infinity] {
            XCTAssertEqual(
                OutputVolumeSnapshot.validated(.init(scalar: scalar, isMuted: false)),
                .unavailable
            )
        }
        XCTAssertEqual(OutputVolumeSnapshot.validated(nil), .unavailable)
    }

    func testMissingMutePropertyIsNotMisreportedAsUnmuted() {
        let snapshot = OutputVolumeSnapshot.validated(.init(scalar: 0.75, isMuted: nil))
        XCTAssertEqual(snapshot.percentage, 75)
        XCTAssertNil(snapshot.isMuted)
    }

    @MainActor
    func testMonitorDoesNotReadBeforeExplicitEnable() {
        var reads = 0
        let monitor = OutputVolumeMonitor(readOutput: {
            reads += 1
            return .init(scalar: 0.7, isMuted: false)
        })
        monitor.refresh()
        XCTAssertEqual(reads, 0)
        XCTAssertEqual(monitor.snapshot, .unavailable)
        monitor.configure(enabled: true)
        XCTAssertEqual(reads, 1)
        XCTAssertEqual(monitor.snapshot.percentage, 70)
        XCTAssertEqual(OutputVolumeMonitor.refreshInterval, 10)
        monitor.configure(enabled: false)
    }

    @MainActor
    func testDisableClearsAllDataAndStopsReads() {
        var reads = 0
        let monitor = OutputVolumeMonitor(readOutput: {
            reads += 1
            return .init(scalar: 0.2, isMuted: true)
        })
        monitor.configure(enabled: true)
        XCTAssertEqual(monitor.snapshot.isMuted, true)
        monitor.configure(enabled: false)
        monitor.refresh()
        XCTAssertEqual(monitor.snapshot, .unavailable)
        XCTAssertEqual(reads, 1)
    }

    @MainActor
    func testMissingHardwareDataClearsPreviouslyReportedValue() {
        var sample: OutputVolumeSample? = .init(scalar: 0.4, isMuted: false)
        let monitor = OutputVolumeMonitor(readOutput: { sample })
        monitor.configure(enabled: true)
        XCTAssertEqual(monitor.snapshot.percentage, 40)
        sample = nil
        monitor.refresh()
        XCTAssertEqual(monitor.snapshot, .unavailable)
        monitor.configure(enabled: false)
    }

    func testOffByDefaultAndIndependentOfOtherUtilities() {
        let suite = "OutputVolumeTests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(defaults: defaults)
        XCTAssertFalse(settings.outputVolumeHUDEnabled)
        settings.outputVolumeHUDEnabled = true
        XCTAssertTrue(SettingsStore(defaults: defaults).outputVolumeHUDEnabled)
        XCTAssertFalse(settings.batteryHUDEnabled)
        XCTAssertFalse(settings.musicWidgetEnabled)
        XCTAssertFalse(settings.calendarWidgetEnabled)
        XCTAssertFalse(settings.focusTimerEnabled)
        settings.reset()
        XCTAssertFalse(settings.outputVolumeHUDEnabled)
    }
}
