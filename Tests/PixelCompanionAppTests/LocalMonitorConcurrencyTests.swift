import Foundation
import XCTest
@testable import PixelCompanion

private final class SwitchingRead: @unchecked Sendable {
    let oldFile: URL
    let oldData: Data
    let newData: Data
    let started: XCTestExpectation
    let release = DispatchSemaphore(value: 0)

    init(oldFile: URL, oldData: Data, newData: Data, started: XCTestExpectation) {
        self.oldFile = oldFile
        self.oldData = oldData
        self.newData = newData
        self.started = started
    }

    func read(_ file: URL) -> Data? {
        if file == oldFile {
            started.fulfill()
            release.wait()
            return oldData
        }
        return newData
    }
}

@MainActor
final class LocalMonitorConcurrencyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func directory() throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("PixelMonitorConcurrency-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    func testLocalAgentSlowReadDoesNotBlockAndCannotRestoreStaleSource() async {
        let old = URL(fileURLWithPath: "/tmp/pixel-monitor-old-source.json")
        let replacement = URL(fileURLWithPath: "/tmp/pixel-monitor-current-source.json")
        let began = expectation(description: "Local feed started background read")
        let probe = SwitchingRead(
            oldFile: old, oldData: Data(#"{"schemaVersion":1,"sessions":[]}"#.utf8),
            newData: Data(#"{"schemaVersion":1,"sessions":[]}"#.utf8), started: began
        )
        defer { probe.release.signal() }
        let monitor = LocalAgentFeedMonitor(read: { probe.read($0) }, now: { self.now })
        monitor.configure(enabled: true)
        monitor.connect(old)
        await fulfillment(of: [began], timeout: 3)
        XCTAssertEqual(monitor.status, .unavailable)
        monitor.connect(replacement)
        await waitForMonitorStatus { monitor.status == .empty }
        probe.release.signal()
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(monitor.status, .empty)
        monitor.configure(enabled: false)
        XCTAssertEqual(monitor.status, .disabled)
    }

    func testCodexTurnOldReadCannotOverwriteNewSelection() async throws {
        let oldFolder = try directory()
        let newFolder = try directory()
        defer {
            try? FileManager.default.removeItem(at: oldFolder)
            try? FileManager.default.removeItem(at: newFolder)
        }
        let older = Data(
            #"{"schemaVersion":1,"event":"agent-turn-complete","lastCompletedAt":"2027-01-15T08:00:00Z"}"#.utf8
        )
        let newer = Data(
            #"{"schemaVersion":1,"event":"agent-turn-complete","lastCompletedAt":"2027-01-15T08:01:00Z"}"#.utf8
        )
        let started = expectation(description: "Codex old source read started")
        let probe = SwitchingRead(
            oldFile: oldFolder.appendingPathComponent(CodexTurnMonitor.eventFilename),
            oldData: older, newData: newer, started: started
        )
        defer { probe.release.signal() }
        let monitor = CodexTurnMonitor(read: { probe.read($0) }, now: { self.now })
        monitor.configure(enabled: true)
        monitor.connectDirectory(oldFolder)
        await fulfillment(of: [started], timeout: 3)
        monitor.connectDirectory(newFolder)
        let expected = CodexTurnParser.parse(newer, now: now)
        await waitForMonitorStatus { monitor.status == expected }
        probe.release.signal()
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(monitor.status, expected)
        monitor.disconnect()
        XCTAssertEqual(monitor.status, .unconnected)
    }

    func testClaudeHookOldReadCannotOverwriteNewSelection() async throws {
        let oldFolder = try directory()
        let newFolder = try directory()
        defer {
            try? FileManager.default.removeItem(at: oldFolder)
            try? FileManager.default.removeItem(at: newFolder)
        }
        let older = Data(#"{"schemaVersion":1,"event":"Stop","observedAt":"2027-01-15T08:00:00Z"}"#.utf8)
        let newer = Data(#"{"schemaVersion":1,"event":"SessionEnd","observedAt":"2027-01-15T08:01:00Z"}"#.utf8)
        let started = expectation(description: "Claude old source read started")
        let probe = SwitchingRead(
            oldFile: oldFolder.appendingPathComponent(ClaudeHookMonitor.eventFilename),
            oldData: older, newData: newer, started: started
        )
        defer { probe.release.signal() }
        let monitor = ClaudeHookMonitor(read: { probe.read($0) }, now: { self.now })
        monitor.configure(enabled: true)
        monitor.connectDirectory(oldFolder)
        await fulfillment(of: [started], timeout: 3)
        monitor.connectDirectory(newFolder)
        let expected = ClaudeHookParser.parse(newer, now: now)
        await waitForMonitorStatus { monitor.status == expected }
        probe.release.signal()
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(monitor.status, expected)
        monitor.configure(enabled: false)
        XCTAssertEqual(monitor.status, .off)
    }
}
