import Foundation
import PixelCompanionCore
@testable import PixelCompanion
import XCTest

final class TransientFileShelfTests: XCTestCase {
    @MainActor
    private func awaitValidation(_ shelf: TransientFileShelf) async {
        for _ in 0..<200 {
            if !shelf.isChecking { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for background shelf metadata validation")
    }

    @MainActor
    func testDisabledShelfRejectsEvenValidFileURLs() {
        let shelf = TransientFileShelf()
        shelf.add([URL(fileURLWithPath: "/tmp/example.txt")])
        XCTAssertTrue(shelf.items.isEmpty)
        XCTAssertFalse(shelf.enabled)
    }

    @MainActor
    func testExplicitEnableAddsOnlyUniqueFileReferences() async {
        let shelf = TransientFileShelf()
        shelf.configure(enabled: true)
        let file = URL(fileURLWithPath: "/tmp/example.txt")
        shelf.add([file, file, URL(string: "https://example.com/secret")!])
        await awaitValidation(shelf)
        XCTAssertEqual(shelf.items.count, 1)
        XCTAssertEqual(shelf.items.first?.displayName, "example.txt")
        XCTAssertEqual(shelf.items.first?.url, file.standardizedFileURL)
    }

    @MainActor
    func testDirectoriesAreNotKept() async {
        let shelf = TransientFileShelf()
        shelf.configure(enabled: true)
        shelf.add([URL(fileURLWithPath: "/tmp/", isDirectory: true)])
        await awaitValidation(shelf)
        XCTAssertTrue(shelf.items.isEmpty)
    }

    @MainActor
    func testDirectoryWithoutTrailingSlashRejectedUsingMetadata() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PixelShelfDirectory-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let shelf = TransientFileShelf()
        shelf.configure(enabled: true)
        // Intentionally construct a file-shaped URL, despite a real directory on disk.
        let url = URL(fileURLWithPath: root.path, isDirectory: false)
        XCTAssertFalse(url.hasDirectoryPath)
        shelf.add([url])
        await awaitValidation(shelf)
        XCTAssertTrue(shelf.items.isEmpty)
    }

    @MainActor
    func testEightItemMaximumAndRemove() async {
        let shelf = TransientFileShelf()
        shelf.configure(enabled: true)
        shelf.add((1...20).map { URL(fileURLWithPath: "/tmp/document-\($0).txt") })
        await awaitValidation(shelf)
        XCTAssertEqual(shelf.items.count, TransientFileShelf.maximumItems)
        let id = shelf.items[0].id
        shelf.remove(id: id)
        XCTAssertEqual(shelf.items.count, 7)
        shelf.clear()
        XCTAssertTrue(shelf.items.isEmpty)
    }

    @MainActor
    func testDisableClearsPreviouslyChosenReferences() async {
        let shelf = TransientFileShelf()
        shelf.configure(enabled: true)
        shelf.add([URL(fileURLWithPath: "/tmp/secret.txt")])
        await awaitValidation(shelf)
        XCTAssertEqual(shelf.items.count, 1)
        shelf.configure(enabled: false)
        XCTAssertTrue(shelf.items.isEmpty)
        shelf.add([URL(fileURLWithPath: "/tmp/again.txt")])
        XCTAssertTrue(shelf.items.isEmpty)
    }

    @MainActor
    func testBlockedMetadataCannotFreezeMainActorOrRestoreAfterDisable() async {
        let started = expectation(description: "background directory check started")
        let gate = DispatchSemaphore(value: 0)
        defer { gate.signal() }
        let shelf = TransientFileShelf(isDirectory: { _ in
            started.fulfill()
            gate.wait()
            return false
        })
        shelf.configure(enabled: true)
        let candidate = URL(fileURLWithPath: "/tmp/qa-shelf-file.txt")
        XCTAssertTrue(shelf.add([candidate]))
        await fulfillment(of: [started], timeout: 3)
        XCTAssertTrue(shelf.items.isEmpty)
        XCTAssertTrue(shelf.isChecking)
        // If metadata were still on the main actor, this line would never run.
        shelf.configure(enabled: false)
        XCTAssertFalse(shelf.isChecking)
        gate.signal()
        try? await Task.sleep(for: .milliseconds(80))
        XCTAssertFalse(shelf.enabled)
        XCTAssertTrue(shelf.items.isEmpty)
    }

    @MainActor
    func testClearedShelfRejectsLateSuccessfulMetadataResult() async {
        let entered = expectation(description: "check began")
        let gate = DispatchSemaphore(value: 0)
        defer { gate.signal() }
        let shelf = TransientFileShelf(isDirectory: { _ in
            entered.fulfill()
            gate.wait()
            return false
        })
        shelf.configure(enabled: true)
        XCTAssertTrue(shelf.add([URL(fileURLWithPath: "/tmp/qa-removed.txt")]))
        await fulfillment(of: [entered], timeout: 3)
        shelf.clear()
        gate.signal()
        try? await Task.sleep(for: .milliseconds(80))
        XCTAssertTrue(shelf.items.isEmpty)
        XCTAssertFalse(shelf.isChecking)
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
