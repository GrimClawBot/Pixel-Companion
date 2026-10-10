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

        var testFailure: Error?
        var pauseTest = false
        var testContinuation: CheckedContinuation<Void, Never>?

        func submitTest() async throws {
            if pauseTest {
                await withCheckedContinuation { testContinuation = $0 }
            }
            if let testFailure { throw testFailure }
            delivered.append(.test)
        }

        func finishTest() {
            testContinuation?.resume()
            testContinuation = nil
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

    func testManualNotificationIsOnlySentWhenBundledAndAuthorized() async {
        let center = FakeCenter()
        let manager = makeManager(center: center)
        XCTAssertFalse(manager.canSendTest)
        await manager.sendTestNotification()
        XCTAssertTrue(center.delivered.isEmpty)

        manager.setEnabled(true)
        await drain()
        XCTAssertFalse(manager.canSendTest)
        await manager.sendTestNotification()
        XCTAssertTrue(center.delivered.isEmpty)

        center.answer(true)
        await drain()
        XCTAssertTrue(manager.canSendTest)
        await manager.sendTestNotification()
        XCTAssertEqual(center.delivered, [.test])
        XCTAssertTrue(manager.testStatus?.contains("macOS accepted") == true)

        manager.setEnabled(false)
        await manager.sendTestNotification()
        XCTAssertEqual(center.delivered, [.test])
    }

    func testFailedMacOSSubmissionIsShownInsteadOfSilentlyIgnored() async {
        let center = FakeCenter()
        let manager = makeManager(center: center)
        manager.setEnabled(true)
        await drain()
        center.answer(true)
        await drain()

        center.testFailure = NSError(domain: "CompanionTest", code: 4)
        await manager.sendTestNotification()
        XCTAssertTrue(manager.testStatus?.contains("macOS rejected") == true)
        XCTAssertTrue(center.delivered.isEmpty)
        XCTAssertTrue(manager.canSendTest)
    }

    func testDisableWhileTestSubmissionIsPendingDoesNotShowStaleResult() async {
        let center = FakeCenter()
        let manager = makeManager(center: center)
        manager.setEnabled(true)
        await drain()
        center.answer(true)
        await drain()

        center.pauseTest = true
        let request = Task { await manager.sendTestNotification() }
        await drain()
        XCTAssertNotNil(center.testContinuation)
        XCTAssertTrue(manager.testStatus?.contains("Submitting") == true)

        manager.setEnabled(false)
        XCTAssertNil(manager.testStatus)
        center.finishTest()
        await request.value

        XCTAssertNil(manager.testStatus)
        XCTAssertFalse(manager.canSendTest)
    }

    func testQASimulationUsesDetectorWithoutPaperclipAndHonorsOptIn() async {
        let center = FakeCenter()
        let manager = makeManager(center: center, qaBuild: true)
        manager.simulateQAEvent(.newApproval)
        XCTAssertTrue(center.delivered.isEmpty)
        manager.setEnabled(true)
        await drain()
        center.answer(true)
        await drain()
        XCTAssertTrue(manager.canSimulateQAEvent)
        for scenario in CompanionQAScenario.allCases {
            manager.simulateQAEvent(scenario)
        }
        XCTAssertEqual(center.delivered, [.approvals(1), .completedRuns(1), .failedRuns(1)])
        XCTAssertTrue(manager.testStatus?.contains("No Paperclip changes") == true)
        manager.setEnabled(false)
        manager.simulateQAEvent(.newApproval)
        XCTAssertEqual(center.delivered.count, 3)

        let productionCenter = FakeCenter()
        let production = makeManager(center: productionCenter)
        production.setEnabled(true)
        await drain()
        productionCenter.answer(true)
        await drain()
        production.simulateQAEvent(.newApproval)
        XCTAssertFalse(production.canSimulateQAEvent)
        XCTAssertTrue(productionCenter.delivered.isEmpty)
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
        bundled: Bool = true,
        qaBuild: Bool = false
    ) -> CompanionNotificationManager {
        let defaults = UserDefaults(suiteName: "PixelCompanionNotifyTests.\(UUID().uuidString)")!
        return CompanionNotificationManager(
            defaults: defaults, center: center, isBundled: bundled, isQABuild: qaBuild
        )
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
