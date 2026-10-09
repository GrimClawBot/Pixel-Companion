import Foundation
import PixelCompanionCore
@testable import PixelCompanion
import XCTest

final class ClaudeHookMonitorTests: XCTestCase {
    private let moment = Date(timeIntervalSince1970: 1_800_000_000)

    private func payload(
        event: String = "Stop",
        date: String = "2027-01-15T08:00:00Z",
        version: Int = 1
    ) -> Data {
        Data(
            """
            {"schemaVersion":\(version),"event":"\(event)","observedAt":"\(date)"}
            """.utf8
        )
    }

    func testEachSupportedMilestoneIsPreservedWithoutInventedState() {
        for event in ClaudeHookEvent.allCases {
            XCTAssertEqual(
                ClaudeHookParser.parse(payload(event: event.rawValue), now: moment),
                .observed(event: event, timestamp: moment)
            )
            XCTAssertFalse(event.label.isEmpty)
        }
    }

    func testUnknownEventAndSchemaFailClosed() {
        XCTAssertEqual(ClaudeHookParser.parse(payload(event: "PermissionRequest")), .unavailable)
        XCTAssertEqual(ClaudeHookParser.parse(payload(event: "PreToolUse")), .unavailable)
        XCTAssertEqual(ClaudeHookParser.parse(payload(version: 2)), .unavailable)
        XCTAssertEqual(ClaudeHookParser.parse(Data("null".utf8)), .unavailable)
        XCTAssertEqual(ClaudeHookParser.parse(Data("not JSON".utf8)), .unavailable)
    }

    func testUnknownKeysRejectedToAvoidAccidentalPrivateDataFiles() {
        let sensitive = Data(
            """
            {"schemaVersion":1,"event":"Stop","observedAt":"2027-01-15T08:00:00Z",
             "prompt":"NO-TRANSCRIPTS"}
            """.utf8
        )
        XCTAssertEqual(ClaudeHookParser.parse(sensitive, now: moment), .unavailable)
        XCTAssertEqual(
            ClaudeHookParser.parse(Data(repeating: 65, count: ClaudeHookParser.maximumBytes + 1)),
            .unavailable
        )
    }

    func testFutureAndInvalidTimestampsFailClosed() {
        XCTAssertEqual(
            ClaudeHookParser.parse(payload(date: "2027-01-15T08:00:31Z"), now: moment),
            .unavailable
        )
        XCTAssertEqual(
            ClaudeHookParser.parse(payload(date: "not-a-timestamp"), now: moment),
            .unavailable
        )
    }

    func testOldEventsAreHistoricalNotCurrentActivity() {
        XCTAssertTrue(ClaudeHookParser.isRecent(moment, at: moment))
        XCTAssertTrue(
            ClaudeHookParser.isRecent(moment, at: moment.addingTimeInterval(120))
        )
        XCTAssertFalse(
            ClaudeHookParser.isRecent(moment, at: moment.addingTimeInterval(121))
        )
    }

    @MainActor
    func testDisabledAndUnconnectedNeverRead() {
        let probe = LockedLocalReportReader()
        let monitor = ClaudeHookMonitor(read: { probe.read($0) })
        monitor.refresh()
        XCTAssertEqual(monitor.status, .off)
        monitor.configure(enabled: true)
        XCTAssertEqual(monitor.status, .unconnected)
        monitor.refresh()
        XCTAssertEqual(probe.calls, 0)
        XCTAssertEqual(ClaudeHookMonitor.refreshInterval, 15)
        monitor.configure(enabled: false)
    }

    @MainActor
    func testOptInFolderSelectionAndDisableForgetPath() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("PC43Folder-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let probe = LockedLocalReportReader(payload())
        let monitor = ClaudeHookMonitor(
            read: { probe.read($0) },
            now: { self.moment }
        )
        monitor.connectDirectory(folder)
        XCTAssertFalse(monitor.isConnected)
        monitor.configure(enabled: true)
        XCTAssertEqual(monitor.status, .unconnected)
        monitor.connectDirectory(folder)
        XCTAssertTrue(monitor.isConnected)
        await awaitLocalReport {
            monitor.status == .observed(event: .responseStopped, timestamp: moment)
        }
        XCTAssertEqual(probe.calls, 1)
        XCTAssertEqual(probe.lastPath?.lastPathComponent, ClaudeHookMonitor.eventFilename)
        monitor.configure(enabled: false)
        XCTAssertEqual(monitor.status, .off)
        monitor.configure(enabled: true)
        XCTAssertFalse(monitor.isConnected)
        XCTAssertEqual(monitor.status, .unconnected)
        XCTAssertEqual(probe.calls, 1)
        monitor.configure(enabled: false)
    }

    @MainActor
    func testMissingMarkerAndDisconnectFailClosed() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("PC43Missing-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let probe = LockedLocalReportReader(payload())
        let monitor = ClaudeHookMonitor(read: { probe.read($0) }, now: { self.moment })
        monitor.configure(enabled: true)
        monitor.connectDirectory(folder)
        await awaitLocalReport {
            monitor.status == .observed(event: .responseStopped, timestamp: moment)
        }
        probe.set(nil)
        monitor.refresh()
        await awaitLocalReport { monitor.status == .unavailable }
        XCTAssertEqual(monitor.status, .unavailable)
        monitor.disconnect()
        XCTAssertEqual(monitor.status, .unconnected)
        monitor.configure(enabled: false)
    }

    func testUnderlyingFileReaderWillNotFollowSymlink() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("PC43Reader-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("event.json")
        let link = folder.appendingPathComponent("link.json")
        let data = payload()
        try data.write(to: file)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        XCTAssertEqual(LocalAgentFeedFileReader.read(file), data)
        XCTAssertNil(LocalAgentFeedFileReader.read(link))
    }

    func testOffByDefaultPreferenceRemainsIndependent() {
        let suite = "PC43Preference-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SettingsStore(defaults: defaults)
        XCTAssertFalse(store.claudeHookEventsEnabled)
        store.claudeHookEventsEnabled = true
        XCTAssertTrue(SettingsStore(defaults: defaults).claudeHookEventsEnabled)
        XCTAssertFalse(store.codexTurnEventsEnabled)
        store.reset()
        XCTAssertFalse(store.claudeHookEventsEnabled)
    }
}
