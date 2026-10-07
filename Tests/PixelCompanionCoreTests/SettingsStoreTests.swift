import PixelCompanionCore
import XCTest

final class SettingsStoreTests: XCTestCase {
    private var suiteName = ""
    private var defaults = UserDefaults()

    override func setUpWithError() throws {
        try super.setUpWithError()
        suiteName = "PixelCompanionCoreTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testDefaults() {
        let store = SettingsStore(defaults: defaults)

        XCTAssertEqual(store.connectorID, ConnectorRegistry.defaultID)
        XCTAssertEqual(store.presentation, .automatic)
        XCTAssertEqual(store.mockConnectionState, .connected)
        XCTAssertEqual(store.mockStepInterval, SettingsStore.defaultStepInterval)
    }

    func testValuesPersistAcrossInstances() {
        let store = SettingsStore(defaults: defaults)
        store.connectorID = .disabled
        store.presentation = .menuBar
        store.mockConnectionState = .error
        store.mockStepInterval = 10

        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.connectorID, .disabled)
        XCTAssertEqual(reloaded.presentation, .menuBar)
        XCTAssertEqual(reloaded.mockConnectionState, .error)
        XCTAssertEqual(reloaded.mockStepInterval, 10)
    }

    func testCorruptValuesFallBackToDefaults() {
        defaults.set("sideways", forKey: SettingsStore.Key.presentation.rawValue)
        defaults.set("melting", forKey: SettingsStore.Key.mockConnectionState.rawValue)
        defaults.set("fast", forKey: SettingsStore.Key.mockStepInterval.rawValue)
        let store = SettingsStore(defaults: defaults)

        XCTAssertEqual(store.presentation, .automatic)
        XCTAssertEqual(store.mockConnectionState, .connected)
        XCTAssertEqual(store.mockStepInterval, SettingsStore.defaultStepInterval)
    }

    func testUnknownConnectorFallsBackToDefault() {
        defaults.set("removed.connector", forKey: SettingsStore.Key.connectorID.rawValue)
        let store = SettingsStore(defaults: defaults)
        XCTAssertEqual(store.connectorID, ConnectorRegistry.defaultID)

        store.connectorID = ConnectorID(rawValue: "")
        XCTAssertEqual(store.connectorID, ConnectorRegistry.defaultID)

        for option in ConnectorRegistry.options {
            store.connectorID = option.id
            XCTAssertEqual(store.connectorID, option.id, "registered connectors must round-trip")
        }
    }

    func testStepIntervalIsClamped() {
        let store = SettingsStore(defaults: defaults)
        store.mockStepInterval = 0.01
        XCTAssertEqual(store.mockStepInterval, SettingsStore.stepIntervalRange.lowerBound)

        store.mockStepInterval = 3_600
        XCTAssertEqual(store.mockStepInterval, SettingsStore.stepIntervalRange.upperBound)
    }

    func testResetRestoresDefaults() {
        let store = SettingsStore(defaults: defaults)
        store.presentation = .notch
        store.connectorID = .mockQuiet
        store.reset()

        XCTAssertEqual(store.presentation, .automatic)
        XCTAssertEqual(store.connectorID, ConnectorRegistry.defaultID)
    }
}
