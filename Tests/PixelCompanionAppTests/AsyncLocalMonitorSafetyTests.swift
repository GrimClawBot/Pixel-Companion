import Foundation
@testable import PixelCompanion
import XCTest

private final class BlockedLocalFileReader: @unchecked Sendable {
    private let lock = NSLock()
    private let gate = DispatchSemaphore(value: 0)
    private let oldURL: URL
    private let oldData: Data
    private let newData: Data
    private var didStart = false

    init(oldURL: URL, oldData: Data, newData: Data) {
        self.oldURL = oldURL
        self.oldData = oldData
        self.newData = newData
    }

    var started: Bool {
        lock.lock()
        defer { lock.unlock() }
        return didStart
    }

    func read(_ file: URL) -> Data? {
        if file == oldURL {
            lock.lock()
            didStart = true
            lock.unlock()
            gate.wait()
            return oldData
        }
        return newData
    }

    func release() { gate.signal() }
}

@MainActor
final class AsyncLocalMonitorSafetyTests: XCTestCase {
    private let current = Date(timeIntervalSince1970: 1_800_000_000)

    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PC84-Async-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testLocalSessionBlockedSourceNeverBlocksUIOrRestoresOldResult() async {
        let first = URL(fileURLWithPath: "/tmp/pc84-slow-local-sessions.json")
        let second = URL(fileURLWithPath: "/tmp/pc84-current-local-sessions.json")
        let reader = BlockedLocalFileReader(
            oldURL: first, oldData: Data("invalid".utf8),
            newData: Data(#"{"schemaVersion":1,"sessions":[]}"#.utf8)
        )
        defer { reader.release() }
        let monitor = LocalAgentFeedMonitor(read: { reader.read($0) }, now: { self.current })
        monitor.configure(enabled: true)
        monitor.connect(first)
        await awaitLocalReport { reader.started }
        XCTAssertEqual(monitor.status, .unavailable)
        monitor.connect(second)
        await awaitLocalReport { monitor.status == .empty }
        reader.release()
        try? await Task.sleep(for: .milliseconds(60))
        XCTAssertEqual(monitor.status, .empty)
        monitor.configure(enabled: false)
        XCTAssertEqual(monitor.status, .disabled)
    }

    func testCodexBlockedFolderFileCanSwitchAndRejectLateResult() async throws {
        let first = try folder()
        let second = try folder()
        defer {
            try? FileManager.default.removeItem(at: first)
            try? FileManager.default.removeItem(at: second)
        }
        let firstFile = first.appendingPathComponent(CodexTurnMonitor.eventFilename)
        let newPayload = Data(
            #"{"schemaVersion":1,"event":"agent-turn-complete","lastCompletedAt":"2027-01-15T08:00:00Z"}"#.utf8
        )
        let reader = BlockedLocalFileReader(
            oldURL: firstFile, oldData: Data("invalid".utf8), newData: newPayload
        )
        defer { reader.release() }
        let monitor = CodexTurnMonitor(read: { reader.read($0) }, now: { self.current })
        monitor.configure(enabled: true)
        monitor.connectDirectory(first)
        await awaitLocalReport { reader.started }
        XCTAssertEqual(monitor.status, .unavailable)
        monitor.connectDirectory(second)
        await awaitLocalReport { monitor.status == .observed(current) }
        reader.release()
        try? await Task.sleep(for: .milliseconds(60))
        XCTAssertEqual(monitor.status, .observed(current))
        monitor.disconnect()
        XCTAssertEqual(monitor.status, .unconnected)
        monitor.configure(enabled: false)
    }

    func testClaudeBlockedFolderFileCanSwitchAndRejectLateResult() async throws {
        let first = try folder()
        let second = try folder()
        defer {
            try? FileManager.default.removeItem(at: first)
            try? FileManager.default.removeItem(at: second)
        }
        let firstFile = first.appendingPathComponent(ClaudeHookMonitor.eventFilename)
        let newPayload = Data(
            #"{"schemaVersion":1,"event":"Stop","observedAt":"2027-01-15T08:00:00Z"}"#.utf8
        )
        let reader = BlockedLocalFileReader(
            oldURL: firstFile, oldData: Data("invalid".utf8), newData: newPayload
        )
        defer { reader.release() }
        let monitor = ClaudeHookMonitor(read: { reader.read($0) }, now: { self.current })
        monitor.configure(enabled: true)
        monitor.connectDirectory(first)
        await awaitLocalReport { reader.started }
        XCTAssertEqual(monitor.status, .unavailable)
        monitor.connectDirectory(second)
        await awaitLocalReport {
            monitor.status == .observed(event: .responseStopped, timestamp: current)
        }
        reader.release()
        try? await Task.sleep(for: .milliseconds(60))
        XCTAssertEqual(monitor.status, .observed(event: .responseStopped, timestamp: current))
        monitor.configure(enabled: false)
        XCTAssertEqual(monitor.status, .off)
    }
}
