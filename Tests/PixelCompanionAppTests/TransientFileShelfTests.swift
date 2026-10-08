import Foundation
import PixelCompanionCore
@testable import PixelCompanion
import XCTest

final class TransientFileShelfTests: XCTestCase {
    @MainActor
    func testDisabledShelfRejectsEvenValidFileURLs() {
        let shelf = TransientFileShelf()
        shelf.add([URL(fileURLWithPath: "/tmp/example.txt")])
        XCTAssertTrue(shelf.items.isEmpty)
        XCTAssertFalse(shelf.enabled)
    }

    @MainActor
    func testExplicitEnableAddsOnlyUniqueFileReferences() {
        let shelf = TransientFileShelf()
        shelf.configure(enabled: true)
        let file = URL(fileURLWithPath: "/tmp/example.txt")
        shelf.add([file, file, URL(string: "https://example.com/secret")!])
        XCTAssertEqual(shelf.items.count, 1)
        XCTAssertEqual(shelf.items.first?.displayName, "example.txt")
        XCTAssertEqual(shelf.items.first?.url, file.standardizedFileURL)
    }

    @MainActor
    func testDirectoriesAreNotKept() {
        let shelf = TransientFileShelf()
        shelf.configure(enabled: true)
        shelf.add([URL(fileURLWithPath: "/tmp/", isDirectory: true)])
        XCTAssertTrue(shelf.items.isEmpty)
    }

    @MainActor
    func testEightItemMaximumAndRemove() {
        let shelf = TransientFileShelf()
        shelf.configure(enabled: true)
        shelf.add((1...20).map { URL(fileURLWithPath: "/tmp/document-\($0).txt") })
        XCTAssertEqual(shelf.items.count, TransientFileShelf.maximumItems)
        let id = shelf.items[0].id
        shelf.remove(id: id)
        XCTAssertEqual(shelf.items.count, 7)
        shelf.clear()
        XCTAssertTrue(shelf.items.isEmpty)
    }

    @MainActor
    func testDisableClearsPreviouslyChosenReferences() {
        let shelf = TransientFileShelf()
        shelf.configure(enabled: true)
        shelf.add([URL(fileURLWithPath: "/tmp/secret.txt")])
        XCTAssertEqual(shelf.items.count, 1)
        shelf.configure(enabled: false)
        XCTAssertTrue(shelf.items.isEmpty)
        shelf.add([URL(fileURLWithPath: "/tmp/again.txt")])
        XCTAssertTrue(shelf.items.isEmpty)
    }

    func testUntrustedFilenamesHaveBoundedSafeDisplayText() {
        XCTAssertEqual(FileShelfLabel.sanitized("\n\ttest\u{202E}file\u{2066}.txt"), "testfile.txt")
        XCTAssertEqual(FileShelfLabel.sanitized("\n\t\u{202E}"), "Unnamed file")
        XCTAssertEqual(FileShelfLabel.sanitized(String(repeating: "x", count: 100)).count, 80)
    }

    func testShelfPreferenceIsIndependentAndOffByDefault() {
        let name = "TransientFileShelfTests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let store = SettingsStore(defaults: defaults)
        XCTAssertFalse(store.fileShelfEnabled)
        store.fileShelfEnabled = true
        XCTAssertTrue(SettingsStore(defaults: defaults).fileShelfEnabled)
        XCTAssertFalse(store.downloadHUDEnabled)
        XCTAssertFalse(store.musicWidgetEnabled)
        store.reset()
        XCTAssertFalse(store.fileShelfEnabled)
    }
}
