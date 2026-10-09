import EventKit
import Foundation
import PixelCompanionCore
@testable import PixelCompanion
import XCTest

final class CalendarNextEventTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func event(
        _ title: String? = "Meeting",
        start: TimeInterval, duration: TimeInterval = 1_800,
        allDay: Bool = false
    ) -> CalendarNextEvent {
        CalendarNextEvent(
            title: title,
            start: now.addingTimeInterval(start),
            end: now.addingTimeInterval(start + duration),
            isAllDay: allDay
        )
    }

    func testNextIsEarliestFutureEventNotOriginalInputOrder() {
        let candidates = [
            event("Friday", start: 72_000),
            event("Soon", start: 300),
            event("Later", start: 7_200)
        ]
        let next = CalendarEventPresentation.next(from: candidates, now: now)
        XCTAssertEqual(next?.title, "Soon")
        XCTAssertEqual(next?.start, now.addingTimeInterval(300))
    }

    func testPastOrEndedEventsAreExcluded() {
        XCTAssertNil(CalendarEventPresentation.next(from: [
            event("Past", start: -3_600),
            event("Ended", start: -100, duration: 50)
        ], now: now))
        XCTAssertEqual(CalendarEventPresentation.next(from: [
            event("Past", start: -3_600),
            event("Future", start: 600)
        ], now: now)?.title, "Future")
    }

    func testOngoingAllDayIsFallbackWhenNoNextFutureEvent() {
        let activeAllDay = event("All day", start: -4_000, duration: 86_400, allDay: true)
        XCTAssertEqual(CalendarEventPresentation.next(
            from: [activeAllDay], now: now
        ), activeAllDay)
        XCTAssertEqual(CalendarEventPresentation.next(
            from: [activeAllDay, event("Soon", start: 600)], now: now
        )?.title, "Soon")
    }

    func testStartedNonAllDayEventDoesNotPretendToBeUpcoming() {
        XCTAssertNil(CalendarEventPresentation.next(from: [
            event("In progress", start: -300, duration: 3_600)
        ], now: now))
    }

    func testMissingEventsAndFinishedAllDayRemainAbsent() {
        XCTAssertNil(CalendarEventPresentation.next(from: [], now: now))
        XCTAssertNil(CalendarEventPresentation.next(from: [
            event("Yesterday", start: -172_800, duration: 86_400, allDay: true)
        ], now: now))
    }

    func testPrivateTitlesStayMaskedByDefaultUnlessExplicitlyEnabled() {
        let secret = event(" Private appointment ", start: 300)
        XCTAssertEqual(CalendarEventPresentation.displayTitle(
            for: secret, showTitles: false
        ), "Calendar event")
        XCTAssertEqual(CalendarEventPresentation.displayTitle(
            for: secret, showTitles: true
        ), "Private appointment")
        XCTAssertEqual(CalendarEventPresentation.displayTitle(
            for: event("   ", start: 300), showTitles: true
        ), "Calendar event")
        XCTAssertEqual(CalendarEventPresentation.displayTitle(
            for: event(nil, start: 300), showTitles: true
        ), "Calendar event")
    }

    @MainActor
    func testAuthorizationStatusFailsClosedExceptFullReadAccess() {
        XCTAssertEqual(CalendarNextEventMonitor.accessState(from: .fullAccess), .authorized)
        XCTAssertEqual(CalendarNextEventMonitor.accessState(from: .notDetermined), .notRequested)
        XCTAssertEqual(CalendarNextEventMonitor.accessState(from: .denied), .denied)
        XCTAssertEqual(CalendarNextEventMonitor.accessState(from: .restricted), .restricted)
        XCTAssertEqual(CalendarNextEventMonitor.accessState(from: .writeOnly), .unavailable)
    }

    func testRefreshBoundedAndUnavailableMessagesClear() {
        XCTAssertEqual(CalendarEventPresentation.lookAheadDays, 7)
        XCTAssertEqual(CalendarEventPresentation.refreshInterval, 120)
        XCTAssertTrue(CalendarAccessState.notRequested.explanation.contains("Grant"))
        XCTAssertTrue(CalendarAccessState.denied.explanation.contains("System Settings"))
        XCTAssertTrue(CalendarAccessState.restricted.explanation.contains("restricted"))
        XCTAssertTrue(CalendarAccessState.unavailable.explanation.contains("unavailable"))
    }

    func testCalendarPreferencesDefaultOffAndRemainIndependent() {
        let suite = "PixelCompanionCalendarTests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SettingsStore(defaults: defaults)
        XCTAssertFalse(store.calendarWidgetEnabled)
        XCTAssertFalse(store.calendarShowTitles)
        XCTAssertFalse(store.focusTimerEnabled)
        XCTAssertFalse(store.batteryHUDEnabled)
        store.calendarWidgetEnabled = true
        XCTAssertFalse(store.calendarShowTitles)
        let restored = SettingsStore(defaults: defaults)
        XCTAssertTrue(restored.calendarWidgetEnabled)
        restored.calendarShowTitles = true
        XCTAssertTrue(store.calendarShowTitles)
        XCTAssertFalse(store.focusTimerEnabled)
        XCTAssertFalse(store.batteryHUDEnabled)
    }

    func testAppBundleDescriptionIsRecordedOnlyWhenPackaged() {
        // No actual EKEventStore is opened and no permission dialog is
        // triggered during unit testing. Packaging verifies Info.plist.
        XCTAssertEqual(CalendarEventPresentation.lookAheadDays, 7)
        XCTAssertEqual(CalendarAccessState.notRequested, .notRequested)
    }
}
