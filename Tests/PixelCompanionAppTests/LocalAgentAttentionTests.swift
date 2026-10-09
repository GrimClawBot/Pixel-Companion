import Foundation
import PixelCompanionCore
@testable import PixelCompanion
import XCTest

@MainActor
final class LocalAgentAttentionTests: XCTestCase {
    private let moment = Date(timeIntervalSince1970: 1_800_000_000)

    private struct Fixture {
        let timeline: LocalAgentActivityTimeline
        let attention: LocalAgentAttention
        let notices: NoticeRecorder
    }

    private func setup() -> Fixture {
        let timeline = LocalAgentActivityTimeline(now: { self.moment })
        let attention = LocalAgentAttention(now: { self.moment })
        let recorder = NoticeRecorder()
        attention.bind(timeline: timeline) { alert in recorder.values.append(alert) }
        return Fixture(timeline: timeline, attention: attention, notices: recorder)
    }

    private final class NoticeRecorder {
        var values: [LocalAgentAlert] = []
    }

    func testNotificationEligibilityNeverIncludesPromptOrSessionEvents() {
        for event in ClaudeHookEvent.allCases {
            let item = LocalAgentActivityEvent(
                id: "id", source: .claudeCode, label: event.label, timestamp: moment
            )
            let result = LocalAgentAlert.from(item)
            switch event {
            case .responseStopped: XCTAssertEqual(result, .claudeResponseEnded)
            case .responseFailed: XCTAssertEqual(result, .claudeResponseFailed)
            default: XCTAssertNil(result)
            }
        }
        let codex = LocalAgentActivityEvent(
            id: "x", source: .codex,
            label: "Turn finished (outcome unknown)", timestamp: moment
        )
        XCTAssertEqual(LocalAgentAlert.from(codex), .codexTurnEnded)
        XCTAssertNil(LocalAgentAlert.from(LocalAgentActivityEvent(
            id: "x", source: .codex,
            label: "Prompt submitted", timestamp: moment
        )))
    }

    func testDefaultOffAllowsDigestButNeverBanners() {
        let fixture = setup()
        let (timeline, attention, notices) = (fixture.timeline, fixture.attention, fixture.notices)
        timeline.receive(codex: .observed(moment))
        XCTAssertEqual(attention.latest.count, 1)
        XCTAssertTrue(notices.values.isEmpty)
    }

    func testEnablingAfterExistingEventNeverReplaysIt() {
        let fixture = setup()
        let (timeline, attention, notices) = (fixture.timeline, fixture.attention, fixture.notices)
        timeline.receive(codex: .observed(moment))
        attention.configureNotifications(enabled: true)
        XCTAssertEqual(attention.latest.count, 1)
        XCTAssertTrue(notices.values.isEmpty)
        timeline.receive(codex: .observed(moment))
        XCTAssertTrue(notices.values.isEmpty)
    }

    func testNewCodexEndNotifiesOnlyOnce() {
        let fixture = setup()
        let (timeline, attention, notices) = (fixture.timeline, fixture.attention, fixture.notices)
        attention.configureNotifications(enabled: true)
        timeline.receive(codex: .observed(moment))
        timeline.receive(codex: .observed(moment))
        XCTAssertEqual(notices.values, [.codexTurnEnded])
    }

    func testSourcePriorityAndCooldownDoNotSpam() {
        var time = moment
        let timeline = LocalAgentActivityTimeline(now: { time })
        let attention = LocalAgentAttention(now: { time })
        let recorder = NoticeRecorder()
        attention.bind(timeline: timeline) { recorder.values.append($0) }
        attention.configureNotifications(enabled: true)
        timeline.receive(claude: .observed(event: .responseFailed, timestamp: time))
        XCTAssertEqual(recorder.values, [.claudeResponseFailed])
        time = moment.addingTimeInterval(30)
        timeline.receive(codex: .observed(time))
        XCTAssertEqual(recorder.values.count, 1)
        time = moment.addingTimeInterval(90)
        timeline.receive(codex: .observed(time))
        XCTAssertEqual(recorder.values, [.claudeResponseFailed, .codexTurnEnded])
        XCTAssertEqual(LocalAgentAttention.minimumNotificationGap, 90)
    }

    func testUnimportantEventsNeverTriggerNotifications() {
        let fixture = setup()
        let (timeline, attention, notices) = (fixture.timeline, fixture.attention, fixture.notices)
        attention.configureNotifications(enabled: true)
        timeline.receive(claude: .observed(event: .promptSubmitted, timestamp: moment))
        timeline.receive(claude: .observed(event: .sessionStart, timestamp: moment))
        XCTAssertTrue(notices.values.isEmpty)
        XCTAssertTrue(attention.latest.isEmpty)
    }

    func testDisablingThenEnablingDoesNotReplayCachedEntries() {
        let fixture = setup()
        let (timeline, attention, notices) = (fixture.timeline, fixture.attention, fixture.notices)
        attention.configureNotifications(enabled: true)
        timeline.receive(codex: .observed(moment.addingTimeInterval(-2)))
        attention.configureNotifications(enabled: false)
        attention.configureNotifications(enabled: true)
        timeline.receive(codex: .observed(moment.addingTimeInterval(-1)))
        // Re-enable suppresses replay, and cooldown persists for new events.
        XCTAssertEqual(notices.values, [.codexTurnEnded])
    }

    func testSourceDisconnectDropsDigestAndAlertsRemainSeparate() {
        let fixture = setup()
        let (timeline, attention) = (fixture.timeline, fixture.attention)
        timeline.receive(codex: .observed(moment))
        timeline.receive(claude: .observed(event: .responseStopped, timestamp: moment))
        XCTAssertEqual(attention.latest.count, 2)
        timeline.receive(codex: .off)
        XCTAssertEqual(attention.latest.count, 1)
        XCTAssertEqual(attention.latest.first?.source, .claudeCode)
        timeline.receive(claude: .unavailable)
        XCTAssertTrue(attention.latest.isEmpty)
    }

    func testOldMarkersCannotGenerateNewAttention() {
        let fixture = setup()
        let (timeline, attention, notices) = (fixture.timeline, fixture.attention, fixture.notices)
        attention.configureNotifications(enabled: true)
        timeline.receive(codex: .observed(moment.addingTimeInterval(-121)))
        timeline.receive(claude: .observed(
            event: .responseFailed, timestamp: moment.addingTimeInterval(-120)
        ))
        XCTAssertTrue(notices.values.isEmpty)
        // Older events can remain in the UI as history, never as new alerts.
        XCTAssertEqual(attention.latest.count, 1)
    }

    func testStaticNotificationTextHasNoUserDetails() {
        for alert in [
            LocalAgentAlert.codexTurnEnded, .claudeResponseEnded, .claudeResponseFailed
        ] {
            let notice = CompanionNotice.localAgent(alert)
            XCTAssertFalse(notice.title.isEmpty)
            XCTAssertFalse(notice.body.isEmpty)
            XCTAssertFalse(notice.body.contains("/Users/"))
            XCTAssertFalse(notice.body.contains("prompt"))
            XCTAssertFalse(notice.body.contains("approval"))
            XCTAssertFalse(notice.body.contains("Success"))
        }
    }

    func testNewAlertPreferenceIsIndependentOffByDefault() {
        let name = "PC045Pref-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let store = SettingsStore(defaults: defaults)
        XCTAssertFalse(store.localAgentAlertsEnabled)
        store.localAgentAlertsEnabled = true
        XCTAssertTrue(SettingsStore(defaults: defaults).localAgentAlertsEnabled)
        XCTAssertFalse(store.codexTurnEventsEnabled)
        XCTAssertFalse(store.claudeHookEventsEnabled)
        store.reset()
        XCTAssertFalse(store.localAgentAlertsEnabled)
    }
}
