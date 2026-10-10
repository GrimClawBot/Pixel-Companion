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
        let probe = LockedLocalReportReader()
        let monitor = CodexTurnMonitor(read: { probe.read($0) })
        monitor.refresh()
        XCTAssertEqual(monitor.status, .off)
        monitor.configure(enabled: true)
        XCTAssertEqual(monitor.status, .unconnected)
        monitor.refresh()
        XCTAssertEqual(probe.calls, 0)
        XCTAssertEqual(CodexTurnMonitor.refreshInterval, 15)
        monitor.configure(enabled: false)
    }

    @MainActor
    func testNoFileReadOnSelectionWhileOff() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("PC42Directory-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let probe = LockedLocalReportReader(marker())
        let monitor = CodexTurnMonitor(
            read: { probe.read($0) },
            now: { self.eventTime }
        )
        monitor.connectDirectory(folder)
        XCTAssertFalse(monitor.isConnected)
        XCTAssertEqual(probe.calls, 0)
        monitor.configure(enabled: true)
        XCTAssertEqual(monitor.status, .unconnected)
        monitor.connectDirectory(folder)
        XCTAssertTrue(monitor.isConnected)
        await awaitLocalReport { monitor.status == .observed(eventTime) }
        XCTAssertEqual(probe.calls, 1)
        XCTAssertEqual(probe.lastPath?.lastPathComponent, CodexTurnMonitor.eventFilename)
        monitor.configure(enabled: false)
        XCTAssertEqual(monitor.status, .off)
        monitor.configure(enabled: true)
        XCTAssertEqual(monitor.status, .unconnected)
        monitor.configure(enabled: false)
    }

    @MainActor
    func testFileUnavailableAndDisconnectClearCachedEvents() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("PC42Missing-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let probe = LockedLocalReportReader(marker())
        let monitor = CodexTurnMonitor(
            read: { probe.read($0) }, now: { self.eventTime }
        )
        monitor.configure(enabled: true)
        monitor.connectDirectory(folder)
        await awaitLocalReport { monitor.status == .observed(eventTime) }
        probe.set(nil)
        monitor.refresh()
        await awaitLocalReport { monitor.status == .unavailable }
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
