import Foundation
import PixelCompanionCore
@testable import PixelCompanion
import XCTest

@MainActor
final class LocalAgentAlertDeliveryTests: XCTestCase {
    private final class TestCenter: CompanionNoticeCenter {
        var permission: CompanionAuthorization = .denied
        var delivered: [CompanionNotice] = []
        func authorization() async -> CompanionAuthorization { permission }
        func requestPermission() async -> Bool { permission == .authorized }
        func deliver(_ notice: CompanionNotice) { delivered.append(notice) }
        func submitTest() async throws {}
    }

    func testNoDeliveryWithoutGlobalPermission() {
        let center = TestCenter()
        let suite = "PC045Deliver-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let manager = CompanionNotificationManager(
            defaults: defaults, center: center, isBundled: true, isQABuild: false
        )
        manager.deliverLocalAgent(.codexTurnEnded)
        XCTAssertTrue(center.delivered.isEmpty)
        manager.start()
        manager.deliverLocalAgent(.claudeResponseFailed)
        XCTAssertTrue(center.delivered.isEmpty)
    }

    func testDeniedPermissionNeverQueuesOrReplaysLocalEvents() async {
        let center = TestCenter()
        let suite = "PC045Denied-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let manager = CompanionNotificationManager(
            defaults: defaults, center: center, isBundled: true, isQABuild: false
        )
        manager.setEnabled(true)
        manager.deliverLocalAgent(.claudeResponseFailed)
        for _ in 0..<40 where manager.permission == .checking {
            await Task.yield()
        }
        XCTAssertTrue(center.delivered.isEmpty)
        center.permission = .authorized
        manager.refreshPermission()
        for _ in 0..<40 where manager.permission != .ready {
            await Task.yield()
        }
        XCTAssertTrue(center.delivered.isEmpty)
        XCTAssertEqual(manager.permission, .ready)
        manager.deliverLocalAgent(.codexTurnEnded)
        XCTAssertEqual(center.delivered, [.localAgent(.codexTurnEnded)])
        manager.setEnabled(false)
        manager.deliverLocalAgent(.claudeResponseFailed)
        XCTAssertEqual(center.delivered.count, 1)
    }

    func testUnbundledProcessIsNeverAllowedToNotify() {
        let center = TestCenter()
        let suite = "PC045Unbundled-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let manager = CompanionNotificationManager(
            defaults: defaults, center: center, isBundled: false, isQABuild: false
        )
        manager.setEnabled(true)
        manager.deliverLocalAgent(.claudeResponseEnded)
        XCTAssertTrue(center.delivered.isEmpty)
    }
}
