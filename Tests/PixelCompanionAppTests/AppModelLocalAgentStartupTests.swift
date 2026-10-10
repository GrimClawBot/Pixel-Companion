import Foundation
import PixelCompanionCore
@testable import PixelCompanion
import XCTest

@MainActor
final class AppModelLocalAgentStartupTests: XCTestCase {
    private final class RecordingCenter: CompanionNoticeCenter {
        var notices: [CompanionNotice] = []
        func authorization() async -> CompanionAuthorization { .authorized }
        func requestPermission() async -> Bool { true }
        func deliver(_ notice: CompanionNotice) { notices.append(notice) }
        func submitTest() async throws {}
    }

    private func marker(_ date: Date) -> Data {
        let timestamp = ISO8601DateFormatter().string(from: date)
        return Data(
            """
            {"schemaVersion":1,"event":"agent-turn-complete","lastCompletedAt":"\(timestamp)"}
            """.utf8
        )
    }

    func testModelLaunchDelayedOldMarkerNeverSendsBannerButNewEventCan() async throws {
        let suite = "PC084DelayedNotification-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "pixelCompanion.notificationsEnabled")
        let settings = SettingsStore(defaults: defaults)
        settings.codexTurnEventsEnabled = true
        settings.localAgentAlertsEnabled = true
        settings.managedAgentHookAutoConnectEnabled = false

        let center = RecordingCenter()
        let manager = CompanionNotificationManager(
            defaults: defaults, center: center, isBundled: true, isQABuild: false
        )
        let past = Date().addingTimeInterval(-5)
        let reader = DelayedBaselineReader(marker(past))
        defer { reader.release() }
        let monitor = CodexTurnMonitor(read: { reader.read($0) })
        let model = AppModel(
            settings: settings, notificationManager: manager,
            injectedCodexTurnMonitor: monitor
        )
        model.start()
        monitor.connectDirectory(
            URL(fileURLWithPath: "/tmp/pc084-test-only-" + UUID().uuidString, isDirectory: true)
        )
        await awaitLocalReport { reader.started }
        await awaitLocalReport { manager.permission == .ready }
        XCTAssertTrue(center.notices.isEmpty)
        // The initial report was written just BEFORE app launch, but arrives
        // after permission and local alerts are fully enabled.
        reader.release()
        await awaitLocalReport { !monitor.isRefreshing && model.localAgentAttention.latest.count == 1 }
        XCTAssertTrue(center.notices.isEmpty, "Prior marker must remain history, not a banner")

        // Marker timestamps are second-granular, so wait beyond activation
        // second before a genuine subsequent event.
        try await Task.sleep(for: .milliseconds(1_100))
        let newer = Date()
        reader.set(marker(newer))
        monitor.refresh()
        await awaitLocalReport {
            model.localAgentAttention.latest.first?.timestamp
                == ISO8601DateFormatter().date(from: ISO8601DateFormatter().string(from: newer))
        }
        XCTAssertEqual(center.notices, [.localAgent(.codexTurnEnded)])
        monitor.configure(enabled: false)
    }
}
