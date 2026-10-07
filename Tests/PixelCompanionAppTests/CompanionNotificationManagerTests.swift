import Foundation
import PixelCompanionCore
@testable import PixelCompanion
import XCTest

@MainActor
final class CompanionNotificationManagerTests: XCTestCase {
    private final class FakeCenter: CompanionNoticeCenter {
        var authorizationValue: CompanionAuthorization = .denied
        var delivered: [CompanionNotice] = []
        var permissionRequests = 0
        var permissionContinuation: CheckedContinuation<Bool, Never>?

        func authorization() async -> CompanionAuthorization {
            authorizationValue
        }

        func requestPermission() async -> Bool {
            permissionRequests += 1
            return await withCheckedContinuation { permissionContinuation = $0 }
        }

        func deliver(_ notice: CompanionNotice) {
            delivered.append(notice)
        }

        func answer(_ value: Bool) {
            permissionContinuation?.resume(returning: value)
            permissionContinuation = nil
        }
    }

    func testPermissionPendingBuffersNewNoticesUntilGranted() async {
        let center = FakeCenter()
        let manager = makeManager(center: center)
        manager.setEnabled(true)
        manager.observe(snapshot(["existing"]), isPaperclip: true)
        manager.observe(snapshot(["existing", "new"]), isPaperclip: true)
        XCTAssertTrue(center.delivered.isEmpty)
        await drain()
        XCTAssertEqual(center.permissionRequests, 1)
        center.answer(true)
        await drain()
        XCTAssertEqual(center.delivered, [.approvals(1)])
        manager.observe(snapshot(["existing", "new"]), isPaperclip: true)
        XCTAssertEqual(center.delivered.count, 1)
    }

    func testPermissionDeniedDoesNotDeliverAndDisableDropsPending() async {
        let center = FakeCenter()
        let manager = makeManager(center: center)
        manager.setEnabled(true)
        manager.observe(snapshot(["old"]), isPaperclip: true)
        manager.observe(snapshot(["old", "new"]), isPaperclip: true)
        await drain()
        center.answer(false)
        await drain()
        XCTAssertTrue(center.delivered.isEmpty)
        XCTAssertEqual(manager.permission, .denied)

        manager.setEnabled(false)
        XCTAssertEqual(manager.permission, .off)
        manager.observe(snapshot(["old", "new", "later"]), isPaperclip: true)
        XCTAssertTrue(center.delivered.isEmpty)
    }

    func testSystemSettingsAuthorizationRefreshDeliversOnlyFutureChanges() async {
        let center = FakeCenter()
        let manager = makeManager(center: center)
        manager.setEnabled(true)
        manager.observe(snapshot(["old"]), isPaperclip: true)
        await drain()
        center.answer(false)
        await drain()
        manager.observe(snapshot(["old", "while-denied"]), isPaperclip: true)

        center.authorizationValue = .authorized
        manager.refreshPermission()
        await drain()
        XCTAssertEqual(manager.permission, .ready)
        XCTAssertTrue(center.delivered.isEmpty)
        manager.observe(snapshot(["old", "while-denied", "future"]), isPaperclip: true)
        XCTAssertEqual(center.delivered, [.approvals(1)])
    }

    func testOffByDefaultAndUnbundledCannotRequestOrDeliver() async {
        let center = FakeCenter()
        let manager = makeManager(center: center, bundled: false)
        manager.start()
        XCTAssertFalse(manager.enabled)
        manager.setEnabled(true)
        manager.observe(snapshot(["old"]), isPaperclip: true)
        manager.observe(snapshot(["old", "new"]), isPaperclip: true)
        await drain()
        XCTAssertEqual(manager.permission, .unavailable)
        XCTAssertEqual(center.permissionRequests, 0)
        XCTAssertTrue(center.delivered.isEmpty)
    }

    func testAppActivationDoesNotCancelInFlightPermissionPrompt() async {
        let center = FakeCenter()
        let manager = makeManager(center: center)
        manager.setEnabled(true)
        manager.observe(snapshot(["old"]), isPaperclip: true)
        manager.observe(snapshot(["old", "new"]), isPaperclip: true)
        await drain()
        XCTAssertEqual(center.permissionRequests, 1)
        center.authorizationValue = .notDetermined
        manager.refreshPermission()
        XCTAssertEqual(manager.permission, .checking)
        center.answer(true)
        await drain()
        XCTAssertEqual(manager.permission, .ready)
        XCTAssertEqual(center.delivered, [.approvals(1)])
    }

    func testDisableDuringPermissionRequestInvalidatesResult() async {
        let center = FakeCenter()
        let manager = makeManager(center: center)
        manager.setEnabled(true)
        await drain()
        manager.setEnabled(false)
        center.answer(true)
        await drain()
        XCTAssertEqual(manager.permission, .off)
        XCTAssertTrue(center.delivered.isEmpty)
    }

    private func makeManager(
        center: FakeCenter,
        bundled: Bool = true
    ) -> CompanionNotificationManager {
        let defaults = UserDefaults(suiteName: "PixelCompanionNotifyTests.\(UUID().uuidString)")!
        return CompanionNotificationManager(defaults: defaults, center: center, isBundled: bundled)
    }

    private func snapshot(_ approvalIDs: [String]) -> ConnectorSnapshot {
        ConnectorSnapshot(
            connectorName: "Paperclip",
            connectionState: .connected,
            pendingApprovals: approvalIDs.map {
                ApprovalRequest(id: $0, title: "Secret title", requestedAt: .distantPast)
            }
        )
    }

    private func drain() async {
        for _ in 0..<12 { await Task.yield() }
    }
}
