import Foundation
import PixelCompanionCore
@testable import PixelCompanion
import XCTest

final class ActivityTimelineTests: XCTestCase {
    private let fixedNow = Date(timeIntervalSince1970: 1_729_000_000)

    private func event(
        _ id: String,
        kind: ActivityEvent.Kind = .note,
        title: String = "Event",
        detail: String? = nil,
        timestamp: Date? = nil
    ) -> ActivityEvent {
        ActivityEvent(
            id: id, kind: kind, title: title,
            detail: detail, timestamp: timestamp ?? fixedNow
        )
    }

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }

    func testKindFiltersCoverAllRealEventTypes() {
        let events = [
            event("r", kind: .running),
            event("c", kind: .completed),
            event("f", kind: .failed),
            event("n", kind: .note)
        ]
        XCTAssertEqual(ActivityTimelinePresentation.filtered(
            events, query: "", scope: .all
        ).map(\.id), ["r", "c", "f", "n"])
        XCTAssertEqual(ActivityTimelinePresentation.filtered(
            events, query: "", scope: .running
        ).map(\.id), ["r"])
        XCTAssertEqual(ActivityTimelinePresentation.filtered(
            events, query: "", scope: .completed
        ).map(\.id), ["c"])
        XCTAssertEqual(ActivityTimelinePresentation.filtered(
            events, query: "", scope: .failed
        ).map(\.id), ["f"])
        XCTAssertEqual(ActivityTimelinePresentation.filtered(
            events, query: "", scope: .notes
        ).map(\.id), ["n"])
    }

    func testSearchMatchesReportedTitleAndDetailWithoutCaseSensitivity() {
        let events = [
            event("a", title: "Émma analysis", detail: "PX-17 assigned"),
            event("b", title: "Other event", detail: "Paperclip heartbeat")
        ]
        for term in ["emma", "ANALYSIS", "px-17"] {
            XCTAssertEqual(ActivityTimelinePresentation.filtered(
                events, query: term, scope: .all
            ).map(\.id), ["a"])
        }
        XCTAssertEqual(ActivityTimelinePresentation.filtered(
            events, query: "heartBEAT", scope: .all
        ).map(\.id), ["b"])
        XCTAssertEqual(ActivityTimelinePresentation.filtered(
            events, query: "  ", scope: .all
        ).map(\.id), ["a", "b"])
        XCTAssertTrue(ActivityTimelinePresentation.filtered(
            events, query: "not present", scope: .all
        ).isEmpty)
    }

    func testSearchAndKindFilterIntersect() {
        let events = [
            event("r", kind: .running, title: "Atlas ready"),
            event("f", kind: .failed, title: "Atlas failed"),
            event("n", title: "Pixel")
        ]
        XCTAssertEqual(ActivityTimelinePresentation.filtered(
            events, query: "atlas", scope: .failed
        ).map(\.id), ["f"])
        XCTAssertTrue(ActivityTimelinePresentation.filtered(
            events, query: "pixel", scope: .running
        ).isEmpty)
    }

    func testChronologicalOrderIsStableOnEqualTimestamps() {
        let events = [
            event("old", timestamp: fixedNow.addingTimeInterval(-100)),
            event("one"),
            event("two"),
            event("missing", timestamp: .distantPast)
        ]
        XCTAssertEqual(ActivityTimelinePresentation.filtered(
            events, query: "", scope: .all
        ).map(\.id), ["one", "two", "old", "missing"])
    }

    func testDayGroupingRecognizesTodayYesterdayAndUnknownTime() {
        let yesterday = utcCalendar.date(
            byAdding: .day, value: -1, to: fixedNow
        ) ?? fixedNow.addingTimeInterval(-86_400)
        let items = [
            event("today", timestamp: fixedNow),
            event("yesterday", timestamp: yesterday),
            event("unknown", timestamp: .distantPast)
        ]
        let sections = ActivityTimelinePresentation.sections(
            items, now: fixedNow, calendar: utcCalendar
        )
        XCTAssertEqual(sections.map(\.label), ["Today", "Yesterday", "Date not reported"])
        XCTAssertEqual(sections.map { $0.events.map(\.id) },
                       [["today"], ["yesterday"], ["unknown"]])
        XCTAssertFalse(ActivityTimelinePresentation.hasValidTime(.distantPast))
        XCTAssertTrue(ActivityTimelinePresentation.hasValidTime(fixedNow))
    }

    func testEmptyHistoryAndNoMatchesHaveDifferentMessages() {
        XCTAssertTrue(ActivityTimelinePresentation.emptyMessage(
            total: 0, query: "", scope: .all
        ).contains("No activity"))
        XCTAssertTrue(ActivityTimelinePresentation.emptyMessage(
            total: 3, query: "unmatched", scope: .all
        ).contains("search"))
        XCTAssertTrue(ActivityTimelinePresentation.emptyMessage(
            total: 3, query: "", scope: .failed
        ).contains("failed"))
        XCTAssertTrue(ActivityTimelinePresentation.sections(
            [], now: fixedNow, calendar: utcCalendar
        ).isEmpty)
    }
}
