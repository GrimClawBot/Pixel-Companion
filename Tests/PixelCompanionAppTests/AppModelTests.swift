import Foundation
import PixelCompanionCore
@testable import PixelCompanion
import XCTest

@MainActor
final class AppModelTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "PixelCompanionAppTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testStartBuildsDefaultConnectorAndSettingChangesUpdateSnapshot() {
        let model = AppModel(settings: SettingsStore(defaults: defaults))
        model.start()

        XCTAssertEqual(model.snapshot.connectorName, "Mock: demo loop")
        XCTAssertEqual(model.snapshot.connectionState, .connected)
        XCTAssertTrue(model.isMockConnector)

        model.mockConnectionState = .error
        XCTAssertEqual(model.snapshot.connectionState, .error)
        XCTAssertEqual(model.snapshot.lastError, "Simulated connection error")
        XCTAssertEqual(model.mood, .error)

        model.connectorID = .disabled
        XCTAssertEqual(model.snapshot.connectorName, "No connector")
        XCTAssertEqual(model.snapshot.connectionState, .disconnected)
        XCTAssertFalse(model.isMockConnector)
        XCTAssertEqual(model.mood, .offline)
    }

    func testPresentationPreferenceNotifiesOnlyOnChangeAndPlacementPublishes() {
        let model = AppModel(settings: SettingsStore(defaults: defaults))
        var notifications = 0
        model.onPresentationPreferenceChange = { notifications += 1 }

        model.presentation = .menuBar
        XCTAssertEqual(notifications, 1)
        XCTAssertEqual(model.presentation, .menuBar)

        model.presentation = .menuBar
        XCTAssertEqual(notifications, 1)

        model.updatePresentation(mode: .notch, notchAvailable: true)
        XCTAssertEqual(model.activeMode, .notch)
        XCTAssertTrue(model.notchAvailable)

        model.updatePresentation(mode: .menuBar, notchAvailable: false)
        XCTAssertEqual(model.activeMode, .menuBar)
        XCTAssertFalse(model.notchAvailable)
    }


    func testPaperclipSettingsRebuildAndRefreshImmediately() {
        let settings = SettingsStore(defaults: defaults)
        settings.connectorID = .paperclip
        let model = AppModel(settings: settings)
        model.start()

        XCTAssertTrue(model.isPaperclipConnector)
        XCTAssertEqual(model.snapshot.connectionState, .disconnected)

        model.paperclipBaseURL = "not-a-valid-url"
        XCTAssertEqual(model.paperclipBaseURL, "not-a-valid-url")
        XCTAssertEqual(model.snapshot.connectionState, .error)
        XCTAssertNotNil(model.snapshot.lastError)

        model.paperclipCompanyID = "company-2"
        XCTAssertEqual(model.paperclipCompanyID, "company-2")
        XCTAssertEqual(model.snapshot.connectionState, .error)

        model.paperclipBaseURL = ""
        XCTAssertEqual(model.snapshot.connectionState, .disconnected)
        XCTAssertNil(model.snapshot.lastError)
    }

    func testTimerAdvancesMockAndRestartReturnsToFirstStep() async throws {
        let settings = SettingsStore(defaults: defaults)
        settings.mockStepInterval = 1
        let model = AppModel(settings: settings)
        model.start()

        XCTAssertEqual(model.snapshot.currentActivity?.title, "Ready")

        try await Task.sleep(for: .seconds(1.2))
        XCTAssertEqual(model.snapshot.currentActivity?.title, "Reading the workspace")

        model.restartScript()
        XCTAssertEqual(model.snapshot.currentActivity?.title, "Ready")
    }
}
