import Foundation
import PixelCompanionCore
@testable import PixelCompanion
import XCTest

final class LocalAgentFeedTests: XCTestCase {
    private func document(_ rows: String, version: Int = 1) -> Data {
        Data(#"{"schemaVersion":\#(version),"sessions":[\#(rows)]}"#.utf8)
    }

    private func row(
        id: String = "session-1", source: String = "codex",
        name: String = "Codex local", state: String = "running",
        timestamp: String = "2027-01-15T08:00:00Z"
    ) -> String {
        #"{"id":"\#(id)","source":"\#(source)","name":"\#(name)","state":"\#(state)","updatedAt":"\#(timestamp)"}"#
    }

    func testValidStatusIncludesSourceAndActualTime() {
        let moment = ISO8601DateFormatter().date(from: "2027-01-15T08:00:00Z")!
        guard case let .loaded(sessions) = LocalAgentFeedParser.parse(document(row()), now: moment) else {
            return XCTFail("Expected loaded")
        }
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].source, .codex)
        XCTAssertEqual(sessions[0].name, "Codex local")
        XCTAssertEqual(sessions[0].state, .running)
        XCTAssertTrue(sessions[0].isFresh(at: moment))
        XCTAssertFalse(sessions[0].isFresh(at: moment.addingTimeInterval(121)))
    }

    func testMultipleIndependentProvidersAreSupported() {
        let rows = [
            row(id: "a", source: "claude-code", name: "Claude", state: "waiting"),
            row(id: "b", source: "hermes", name: "Hermes", state: "idle"),
            row(id: "c", source: "custom", name: "Worker", state: "failed")
        ]
        let moment = Date(timeIntervalSince1970: 1_800_000_000)
        guard case let .loaded(sessions) = LocalAgentFeedParser.parse(
            document(rows.joined(separator: ",")), now: moment
        ) else { return XCTFail("Expected sessions") }
        XCTAssertEqual(sessions.map(\.source), [.claudeCode, .hermes, .custom])
        XCTAssertEqual(sessions.map(\.state), [.waiting, .idle, .failed])
    }

    func testUnsupportedSchemaTypesAndDuplicateIDsFailClosed() {
        XCTAssertEqual(LocalAgentFeedParser.parse(document(row(), version: 2)), .unavailable)
        XCTAssertEqual(LocalAgentFeedParser.parse(document(row(source: "evil"))), .unavailable)
        XCTAssertEqual(LocalAgentFeedParser.parse(document(row(state: "approved"))), .unavailable)
        XCTAssertEqual(LocalAgentFeedParser.parse(document(row(id: "../../file"))), .unavailable)
        XCTAssertEqual(LocalAgentFeedParser.parse(document(row() + "," + row())), .unavailable)
        XCTAssertEqual(LocalAgentFeedParser.parse(Data("not JSON".utf8)), .unavailable)
    }

    func testEmptyRowsBoundsAndFutureTime() {
        XCTAssertEqual(LocalAgentFeedParser.parse(document("")), .empty)
        let tooMany = Array(repeating: row(), count: LocalAgentFeedParser.maximumSessions + 1)
        XCTAssertEqual(
            LocalAgentFeedParser.parse(document(tooMany.joined(separator: ","))), .unavailable
        )
        XCTAssertEqual(
            LocalAgentFeedParser.parse(
                Data(repeating: 65, count: LocalAgentFeedParser.maximumBytes + 1)
            ), .unavailable
        )
        let moment = ISO8601DateFormatter().date(from: "2027-01-15T08:00:00Z")!
        XCTAssertEqual(
            LocalAgentFeedParser.parse(
                document(row(timestamp: "2027-01-15T08:00:31Z")), now: moment
            ), .unavailable
        )
    }

    func testUntrustedNamesHaveDirectionOverridesStripped() {
        let moment = ISO8601DateFormatter().date(from: "2027-01-15T08:00:00Z")!
        guard case let .loaded(sessions) = LocalAgentFeedParser.parse(
            document(row(name: #"agent\u202Ename"#)), now: moment
        ) else { return XCTFail("Expected sanitized label") }
        XCTAssertEqual(sessions[0].name, "agentname")
    }

    @MainActor
    func testNoReadsBeforeOptInOrFileSelection() {
        let probe = LockedLocalReportReader()
        let monitor = LocalAgentFeedMonitor(read: { probe.read($0) })
        monitor.refresh()
        XCTAssertEqual(monitor.status, .disabled)
        monitor.configure(enabled: true)
        XCTAssertEqual(monitor.status, .unconnected)
        monitor.refresh()
        XCTAssertEqual(probe.calls, 0)
        XCTAssertEqual(LocalAgentFeedMonitor.refreshInterval, 10)
        monitor.configure(enabled: false)
    }

    @MainActor
    func testExplicitSelectionAndDisablePurgeConnection() async {
        let probe = LockedLocalReportReader(Data(#"{"schemaVersion":1,"sessions":[]}"#.utf8))
        let monitor = LocalAgentFeedMonitor(read: { probe.read($0) })
        let file = URL(fileURLWithPath: "/tmp/local-session.json")
        monitor.connect(file)
        XCTAssertFalse(monitor.isConnected)
        monitor.configure(enabled: true)
        monitor.connect(file)
        await awaitLocalReport { monitor.status == .empty }
        XCTAssertEqual(probe.calls, 1)
        XCTAssertEqual(monitor.status, .empty)
        monitor.configure(enabled: false)
        XCTAssertEqual(monitor.status, .disabled)
        monitor.configure(enabled: true)
        XCTAssertEqual(monitor.status, .unconnected)
        XCTAssertFalse(monitor.isConnected)
        monitor.configure(enabled: false)
    }

    func testFileReaderRejectsSymlinkAndDirectory() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("LocalFeedTest-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("status.json")
        let link = root.appendingPathComponent("redirect.json")
        let payload = Data(#"{"schemaVersion":1,"sessions":[]}"#.utf8)
        try payload.write(to: file)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        XCTAssertEqual(LocalAgentFeedFileReader.read(file), payload)
        XCTAssertNil(LocalAgentFeedFileReader.read(link))
        XCTAssertNil(LocalAgentFeedFileReader.read(root))
        XCTAssertNil(LocalAgentFeedFileReader.read(URL(string: "https://example.com")!))
    }

    func testLocalPreferenceDefaultOffAndReset() {
        let name = "LocalAgentFeed-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = SettingsStore(defaults: defaults)
        XCTAssertFalse(settings.localAgentFeedEnabled)
        settings.localAgentFeedEnabled = true
        XCTAssertTrue(SettingsStore(defaults: defaults).localAgentFeedEnabled)
        XCTAssertFalse(settings.clipboardHistoryEnabled)
        settings.reset()
        XCTAssertFalse(settings.localAgentFeedEnabled)
    }
}
