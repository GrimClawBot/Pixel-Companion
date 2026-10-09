import SwiftUI
@testable import PixelCompanion
import XCTest

final class CompanionCardStyleTests: XCTestCase {
    func testTabTransitionHonorsReduceMotion() {
        XCTAssertNil(CompanionMotion.tabTransition(reduceMotion: true))
        XCTAssertNotNil(CompanionMotion.tabTransition(reduceMotion: false))
    }
}
