@testable import PixelCompanion
import XCTest

final class SettingsNavigationTests: XCTestCase {
    func testAllSettingsDestinationsExistWithDistinctNamesAndSymbols() {
        let panes = CompanionSettingsPane.allCases
        XCTAssertEqual(panes.count, 4)
        XCTAssertEqual(Set(panes.map(\.rawValue)).count, 4)
        XCTAssertEqual(Set(panes.map(\.title)).count, 4)
        XCTAssertEqual(Set(panes.map(\.symbol)).count, 4)
        XCTAssertTrue(panes.allSatisfy { !$0.detail.isEmpty })
    }

    func testNativeSettingsDestinationsKeepOriginalCategories() {
        XCTAssertEqual(CompanionSettingsPane.general.title, "General")
        XCTAssertEqual(CompanionSettingsPane.connections.title, "Connections")
        XCTAssertEqual(CompanionSettingsPane.utilities.title, "Utilities")
        XCTAssertEqual(CompanionSettingsPane.notifications.title, "Notifications")
    }
}
