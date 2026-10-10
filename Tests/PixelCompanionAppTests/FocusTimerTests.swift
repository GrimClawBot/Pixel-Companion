import Foundation
import PixelCompanionCore
@testable import PixelCompanion
import XCTest

final class FocusTimerTests: XCTestCase {
    private let beginning = Date(timeIntervalSince1970: 1_800_000_000)

    func testDefaultsToIdleTwentyFiveMinuteFocus() {
        let timer = FocusTimerState()
        XCTAssertEqual(timer.mode, .focus)
        XCTAssertEqual(timer.phase, .idle)
        XCTAssertEqual(timer.remaining(at: beginning), 1_500)
        XCTAssertNil(timer.deadline)
    }

    func testRunningDeadlineNeverDriftsWithIrregularTicks() {
        var timer = FocusTimerState()
        timer.start(at: beginning)
        XCTAssertEqual(timer.phase, .running)
        XCTAssertEqual(timer.remaining(at: beginning.addingTimeInterval(1.2)), 1_499)
        XCTAssertEqual(timer.remaining(at: beginning.addingTimeInterval(600)), 900)
        XCTAssertEqual(timer.remaining(at: beginning.addingTimeInterval(1_500)), 0)
        timer.advance(to: beginning.addingTimeInterval(1_500))
        XCTAssertEqual(timer.phase, .finished)
        XCTAssertNil(timer.deadline)
        XCTAssertEqual(timer.remaining(at: beginning.addingTimeInterval(1_900)), 0)
    }

    func testPauseAndResumeKeepExactRemainingTime() {
        var timer = FocusTimerState()
        timer.start(at: beginning)
        timer.pause(at: beginning.addingTimeInterval(120))
        XCTAssertEqual(timer.phase, .paused)
        XCTAssertEqual(timer.remaining(at: beginning.addingTimeInterval(1_000)), 1_380)
        XCTAssertNil(timer.deadline)
        timer.start(at: beginning.addingTimeInterval(2_000))
        XCTAssertEqual(timer.remaining(at: beginning.addingTimeInterval(2_100)), 1_280)
        timer.pause(at: beginning.addingTimeInterval(3_380))
        XCTAssertEqual(timer.phase, .finished)
        XCTAssertNil(timer.deadline)
    }

    func testSleepWakeUsesElapsedWallClockWithoutExtraWork() {
        var timer = FocusTimerState()
        timer.choose(.shortBreak)
        timer.start(at: beginning)
        // Simulate a suspended process: no ticker fires for ten minutes.
        timer.advance(to: beginning.addingTimeInterval(600))
        XCTAssertEqual(timer.phase, .finished)
        XCTAssertEqual(timer.remaining(at: beginning.addingTimeInterval(600)), 0)
    }

    func testModesResetAndDoNotAutoStartAnotherSession() {
        var timer = FocusTimerState()
        timer.start(at: beginning)
        timer.choose(.shortBreak)
        XCTAssertEqual(timer.phase, .idle)
        XCTAssertEqual(timer.remaining(at: beginning), 300)
        timer.start(at: beginning)
        timer.advance(to: beginning.addingTimeInterval(300))
        XCTAssertEqual(timer.phase, .finished)
        XCTAssertEqual(timer.mode, .shortBreak)
        timer.choose(.longBreak)
        XCTAssertEqual(timer.phase, .idle)
        XCTAssertEqual(timer.remaining(at: beginning), 900)
        timer.reset()
        XCTAssertEqual(timer.remaining(at: beginning), 900)
    }

    func testFinishedSessionCanBeStartedAgainExplicitly() {
        var timer = FocusTimerState()
        timer.choose(.shortBreak)
        timer.start(at: beginning)
        timer.advance(to: beginning.addingTimeInterval(300))
        timer.start(at: beginning.addingTimeInterval(350))
        XCTAssertEqual(timer.phase, .running)
        XCTAssertEqual(timer.remaining(at: beginning.addingTimeInterval(350)), 300)
    }

    func testClockFormattingClampsNegativeValues() {
        XCTAssertEqual(FocusTimerState.clockLabel(1_500), "25:00")
        XCTAssertEqual(FocusTimerState.clockLabel(301), "05:01")
        XCTAssertEqual(FocusTimerState.clockLabel(59), "00:59")
        XCTAssertEqual(FocusTimerState.clockLabel(0), "00:00")
        XCTAssertEqual(FocusTimerState.clockLabel(-10), "00:00")
    }

    func testTimerUtilityOffByDefaultAndPreferenceIsIndependent() {
        let suite = "PixelCompanionFocusTimer-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(defaults: defaults)
        XCTAssertFalse(settings.focusTimerEnabled)
        XCTAssertEqual(settings.connectorID, ConnectorRegistry.defaultID)
        settings.focusTimerEnabled = true
        let restored = SettingsStore(defaults: defaults)
        XCTAssertTrue(restored.focusTimerEnabled)
        XCTAssertEqual(restored.connectorID, ConnectorRegistry.defaultID)
        settings.focusTimerEnabled = false
        XCTAssertFalse(restored.focusTimerEnabled)
    }
}
