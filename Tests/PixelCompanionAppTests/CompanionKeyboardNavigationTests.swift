import Foundation
@testable import PixelCompanion
import XCTest

final class CompanionKeyboardNavigationTests: XCTestCase {
    func testKeyboardNumbersAreStableAndUnique() {
        let tabs = CompanionDetailTab.allCases
        XCTAssertEqual(tabs.map(\.keyboardNumber), ["1", "2", "3", "4"])
        XCTAssertEqual(Set(tabs.map(\.keyboardNumber)).count, tabs.count)
    }

    func testArrowNavigationStopsAtBoundaries() {
        XCTAssertEqual(CompanionDetailTab.overview.moving(by: -1), .overview)
        XCTAssertEqual(CompanionDetailTab.activity.moving(by: 1), .activity)
        XCTAssertEqual(CompanionDetailTab.overview.moving(by: 1), .agents)
        XCTAssertEqual(CompanionDetailTab.agents.moving(by: 1), .usage)
        XCTAssertEqual(CompanionDetailTab.usage.moving(by: -1), .agents)
        XCTAssertEqual(CompanionDetailTab.activity.moving(by: -1), .usage)
    }

    func testKeyboardNavigationClampsLargeOffsets() {
        XCTAssertEqual(CompanionDetailTab.overview.moving(by: 999), .activity)
        XCTAssertEqual(CompanionDetailTab.activity.moving(by: -999), .overview)
        XCTAssertEqual(CompanionDetailTab.usage.moving(by: 0), .usage)
    }
}
