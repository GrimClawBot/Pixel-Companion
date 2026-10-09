import Foundation
import PixelCompanionCore
@testable import PixelCompanion
import XCTest

final class CodexTurnMonitorTests: XCTestCase {
    private let eventTime = Date(timeIntervalSince1970: 1_800_000_000)

    private func marker(
        schema: Int = 1, event: String = "agent-turn-complete",
        time: String = "2027-01-15T08:00:00Z"
    ) -> Data {
        Data(
            """
            {"schemaVersion":\(schema),"event":"\(event)","lastCompletedAt":"\(time)"}
            """.utf8
        )
    }

    func testOnlyKnownVersionAndEventCount() {
        XCTAssertEqual(CodexTurnParser.parse(marker(schema: 2)), .unavailable)
        XCTAssertEqual(CodexTurnParser.parse(marker(event: "running")), .unavailable)
        XCTAssertEqual(CodexTurnParser.parse(Data("not JSON".utf8)), .unavailable)
        XCTAssertEqual(CodexTurnParser.parse(Data()), .unavailable)
        XCTAssertEqual(
            CodexTurnParser.parse(Data(repeating: 65, count: CodexTurnParser.maximumBytes + 1)),
            .unavailable
        )
    }

    func testVerifiedTurnCompletedAtIsOnlyReportedField() {
        XCTAssertEqual(CodexTurnParser.parse(marker(), now: eventTime), .observed(eventTime))
        XCTAssertTrue(CodexTurnParser.isRecent(eventTime, at: eventTime))
        XCTAssertTrue(CodexTurnParser.isRecent(eventTime, at: eventTime.addingTimeInterval(120)))
        XCTAssertFalse(CodexTurnParser.isRecent(eventTime, at: eventTime.addingTimeInterval(121)))
    }

    func testFutureAndMissingTimestampFailClosed() {
        XCTAssertEqual(
            CodexTurnParser.parse(
                marker(time: "2027-01-15T08:00:31Z"), now: eventTime
            ), .unavailable
        )
        XCTAssertEqual(
            CodexTurnParser.parse(
                marker(time: "not-a-time"), now: eventTime
            ), .unavailable
        )
    }

    @MainActor
    func testFilenameIsFixedAndNotUserControlled() {
        XCTAssertEqual(CodexTurnMonitor.eventFilename, "pixel-companion-codex-turn.json")
    }

    @MainActor
    func testNoReadsUntilEnableAndFolderSelection() {
        var reads = 0
        let monitor = CodexTurnMonitor(read: { _ in reads += 1; return nil })
        monitor.refresh()
        XCTAssertEqual(monitor.status, .off)
        monitor.configure(enabled: true)
        XCTAssertEqual(monitor.status, .unconnected)
        monitor.refresh()
        XCTAssertEqual(reads, 0)
        XCTAssertEqual(CodexTurnMonitor.refreshInterval, 15)
        monitor.configure(enabled: false)
    }

    @MainActor
    func testNoFileReadOnSelectionWhileOff() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("PC42Directory-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        var requests: [URL] = []
        let monitor = CodexTurnMonitor(
            read: { url in requests.append(url); return self.marker() },
            now: { self.eventTime }
        )
        monitor.connectDirectory(folder)
        XCTAssertFalse(monitor.isConnected)
        XCTAssertTrue(requests.isEmpty)
        monitor.configure(enabled: true)
        XCTAssertEqual(monitor.status, .unconnected)
        monitor.connectDirectory(folder)
        XCTAssertTrue(monitor.isConnected)
        XCTAssertEqual(monitor.status, .observed(eventTime))
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0].lastPathComponent, CodexTurnMonitor.eventFilename)
        monitor.configure(enabled: false)
        XCTAssertEqual(monitor.status, .off)
        monitor.configure(enabled: true)
        XCTAssertEqual(monitor.status, .unconnected)
        monitor.configure(enabled: false)
    }

    @MainActor
    func testFileUnavailableAndDisconnectClearCachedEvents() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("PC42Missing-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        var response: Data? = marker()
        let monitor = CodexTurnMonitor(
            read: { _ in response }, now: { self.eventTime }
        )
        monitor.configure(enabled: true)
        monitor.connectDirectory(folder)
        XCTAssertEqual(monitor.status, .observed(eventTime))
        response = nil
        monitor.refresh()
        XCTAssertEqual(monitor.status, .unavailable)
        monitor.disconnect()
        XCTAssertEqual(monitor.status, .unconnected)
        monitor.configure(enabled: false)
    }

    @MainActor
    func testActualRegularFileAndSymlinkRejection() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("PC42File-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let path = folder.appendingPathComponent(CodexTurnMonitor.eventFilename)
        let content = marker()
        try content.write(to: path)
        XCTAssertEqual(LocalAgentFeedFileReader.read(path), content)
        let link = folder.appendingPathComponent("link.json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: path)
        XCTAssertNil(LocalAgentFeedFileReader.read(link))
    }

    func testPreferenceIsOffByDefaultAndIndependent() {
        let suite = "CodexTurnTests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(defaults: defaults)
        XCTAssertFalse(settings.codexTurnEventsEnabled)
        settings.codexTurnEventsEnabled = true
        XCTAssertTrue(SettingsStore(defaults: defaults).codexTurnEventsEnabled)
        XCTAssertFalse(settings.codexPresenceEnabled)
        settings.reset()
        XCTAssertFalse(settings.codexTurnEventsEnabled)
    }
}
