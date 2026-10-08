import Foundation
@testable import PixelCompanion
import XCTest

final class CompanionDetailTabsTests: XCTestCase {
    func testFourDistinctNativeNavigationTabs() {
        XCTAssertEqual(
            CompanionDetailTab.allCases.map(\.rawValue),
            ["overview", "agents", "usage", "activity"]
        )
        XCTAssertEqual(
            CompanionDetailTab.allCases.map(\.label),
            ["Overview", "Agents", "Usage", "Activity"]
        )
        XCTAssertEqual(Set(CompanionDetailTab.allCases.map(\.symbol)).count, 4)
        XCTAssertEqual(Set(CompanionDetailTab.allCases.map(\.id)).count, 4)
    }

    func testNavigationDoesNotInventExtraDestinations() {
        for tab in CompanionDetailTab.allCases {
            XCTAssertFalse(tab.label.isEmpty)
            XCTAssertFalse(tab.symbol.isEmpty)
            XCTAssertEqual(tab.id, tab.rawValue)
        }
    }
}
