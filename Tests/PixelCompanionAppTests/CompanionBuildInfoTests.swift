@testable import PixelCompanion
import XCTest

final class CompanionBuildInfoTests: XCTestCase {
    func testVersionAndQAUpdateFromBundledMetadata() {
        let info: [String: Any] = [
            "CFBundleShortVersionString": "0.1.0",
            "CFBundleVersion": "3",
            "PCQAUpdateNumber": "3"
        ]
        XCTAssertEqual(CompanionBuildInfo.version(info: info), "0.1.0 (build 3)")
        XCTAssertEqual(CompanionBuildInfo.qaUpdate(info: info), "QA Update #3")
        XCTAssertEqual(
            CompanionBuildInfo.settingsTitle(info: info),
            "Pixel Companion Settings — QA Update #3"
        )
    }

    func testNoQAUpdateForRegularBundle() {
        let info: [String: Any] = [
            "CFBundleShortVersionString": "0.2.0",
            "CFBundleVersion": "19"
        ]
        XCTAssertEqual(CompanionBuildInfo.version(info: info), "0.2.0 (build 19)")
        XCTAssertNil(CompanionBuildInfo.qaUpdate(info: info))
        XCTAssertEqual(CompanionBuildInfo.settingsTitle(info: info), "Pixel Companion Settings")
    }

    func testMissingAndInvalidMetadataHaveSafeFallbacks() {
        XCTAssertEqual(CompanionBuildInfo.version(info: [:]), "Development (build local)")
        XCTAssertNil(CompanionBuildInfo.qaUpdate(info: ["PCQAUpdateNumber": ""]))
        XCTAssertNil(CompanionBuildInfo.qaUpdate(info: ["PCQAUpdateNumber": 5]))
        XCTAssertEqual(
            CompanionBuildInfo.settingsTitle(info: ["PCQAUpdateNumber": ""]),
            "Pixel Companion Settings"
        )
    }
}
