import Foundation
@testable import PixelCompanion
import XCTest

@MainActor
final class AgentHookVerificationTests: XCTestCase {
    private let moment = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(
            "PC48-" + UUID().uuidString, isDirectory: true
        )
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func codexMarker(_ date: Date) -> Data {
        let timestamp = ISO8601DateFormatter().string(from: date)
        return Data(
            """
            {"schemaVersion":1,"event":"agent-turn-complete","lastCompletedAt":"\(timestamp)"}
            """.utf8
        )
    }

    private func claudeMarker(_ event: String, _ date: Date) -> Data {
        let timestamp = ISO8601DateFormatter().string(from: date)
        return Data(
            """
            {"schemaVersion":1,"event":"\(event)","observedAt":"\(timestamp)"}
            """.utf8
        )
    }

    func testFreshExistingCodexMarkerDoesNotProveNewDelivery() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        var time = moment
        var content = codexMarker(time)
        let monitor = CodexTurnMonitor(read: { _ in content }, now: { time })
        monitor.configure(enabled: true)
        monitor.connectDirectory(folder)
        let verifier = AgentHookVerifier(now: { time })
        verifier.bind(codex: monitor, claude: ClaudeHookMonitor())
        verifier.start(codex: monitor)
        XCTAssertEqual(verifier.codexState, .waiting(moment))
        monitor.refresh()
        XCTAssertEqual(verifier.codexState, .waiting(moment))
        time = moment.addingTimeInterval(10)
        content = codexMarker(time)
        monitor.refresh()
        XCTAssertEqual(verifier.codexState, .observed(time))
        monitor.configure(enabled: false)
    }

    func testFirstMarkerAfterPreviouslyMissingFileCounts() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        var time = moment
        var content: Data?
        let monitor = CodexTurnMonitor(read: { _ in content }, now: { time })
        monitor.configure(enabled: true)
        monitor.connectDirectory(folder)
        let verifier = AgentHookVerifier(now: { time })
        verifier.bind(codex: monitor, claude: ClaudeHookMonitor())
        verifier.start(codex: monitor)
        XCTAssertEqual(verifier.codexState, .waiting(moment))
        time = moment.addingTimeInterval(5)
        content = codexMarker(time)
        monitor.refresh()
        XCTAssertEqual(verifier.codexState, .observed(time))
        monitor.configure(enabled: false)
    }

    func testNoReadsBeforeStartBeyondExistingMonitorBehavior() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        var reads = 0
        let monitor = CodexTurnMonitor(
            read: { _ in reads += 1; return nil }, now: { self.moment }
        )
        let verifier = AgentHookVerifier(now: { self.moment })
        verifier.bind(codex: monitor, claude: ClaudeHookMonitor())
        XCTAssertEqual(reads, 0)
        verifier.start(codex: monitor)
        XCTAssertEqual(verifier.codexState, .needsSetup)
        XCTAssertEqual(reads, 0)
        monitor.configure(enabled: true)
        monitor.connectDirectory(folder)
        let existingReads = reads
        verifier.start(codex: monitor)
        XCTAssertEqual(reads, existingReads + 1)
        monitor.configure(enabled: false)
    }

    func testStaleAtArmTimeDoesNotCountAsNewEvenIfFileChanges() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let stale = moment.addingTimeInterval(-130)
        var content: Data? = codexMarker(stale)
        let monitor = CodexTurnMonitor(read: { _ in content }, now: { self.moment })
        monitor.configure(enabled: true)
        monitor.connectDirectory(folder)
        let verifier = AgentHookVerifier(now: { self.moment })
        verifier.bind(codex: monitor, claude: ClaudeHookMonitor())
        verifier.start(codex: monitor)
        content = codexMarker(moment.addingTimeInterval(-40))
        monitor.refresh()
        XCTAssertEqual(verifier.codexState, .waiting(moment))
        monitor.configure(enabled: false)
    }

    func testSameSecondIdenticalEventCannotCountTwice() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let data = codexMarker(moment)
        let monitor = CodexTurnMonitor(read: { _ in data }, now: { self.moment })
        monitor.configure(enabled: true)
        monitor.connectDirectory(folder)
        let verifier = AgentHookVerifier(now: { self.moment })
        verifier.bind(codex: monitor, claude: ClaudeHookMonitor())
        verifier.start(codex: monitor)
        for _ in 0..<4 { monitor.refresh() }
        XCTAssertEqual(verifier.codexState, .waiting(moment))
        monitor.configure(enabled: false)
    }

    func testClaudeDifferentMilestoneTimestampAfterArmCanCount() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        var time = moment
        var content = claudeMarker("SessionStart", moment)
        let monitor = ClaudeHookMonitor(read: { _ in content }, now: { time })
        monitor.configure(enabled: true)
        monitor.connectDirectory(folder)
        let verifier = AgentHookVerifier(now: { time })
        verifier.bind(codex: CodexTurnMonitor(), claude: monitor)
        verifier.start(claude: monitor)
        time = time.addingTimeInterval(3)
        content = claudeMarker("Stop", time)
        monitor.refresh()
        XCTAssertEqual(verifier.claudeState, .observed(time))
        monitor.configure(enabled: false)
    }

    func testCodexAndClaudeChecksRemainIndependent() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        var time = moment
        var codexData: Data? = codexMarker(time)
        var claudeData: Data? = claudeMarker("SessionStart", time)
        let codex = CodexTurnMonitor(read: { _ in codexData }, now: { time })
        let claude = ClaudeHookMonitor(read: { _ in claudeData }, now: { time })
        codex.configure(enabled: true)
        claude.configure(enabled: true)
        codex.connectDirectory(folder)
        claude.connectDirectory(folder)
        let verifier = AgentHookVerifier(now: { time })
        verifier.bind(codex: codex, claude: claude)
        verifier.start(codex: codex)
        verifier.start(claude: claude)
        time = moment.addingTimeInterval(5)
        codexData = codexMarker(time)
        codex.refresh()
        XCTAssertEqual(verifier.codexState, .observed(time))
        XCTAssertEqual(verifier.claudeState, .waiting(moment))
        claudeData = claudeMarker("Stop", time)
        claude.refresh()
        XCTAssertEqual(verifier.claudeState, .observed(time))
        codex.configure(enabled: false)
        claude.configure(enabled: false)
    }

    func testDisconnectClearsObservedResult() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        var time = moment
        var data = codexMarker(time)
        let monitor = CodexTurnMonitor(read: { _ in data }, now: { time })
        monitor.configure(enabled: true)
        monitor.connectDirectory(folder)
        let verifier = AgentHookVerifier(now: { time })
        verifier.bind(codex: monitor, claude: ClaudeHookMonitor())
        verifier.start(codex: monitor)
        time = moment.addingTimeInterval(2)
        data = codexMarker(time)
        monitor.refresh()
        XCTAssertEqual(verifier.codexState, .observed(time))
        monitor.disconnect()
        XCTAssertEqual(verifier.codexState, .needsSetup)
        monitor.configure(enabled: false)
    }

    func testTimeoutRefusesLateMarkersAndDisplaysTimeout() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        var time = moment
        var data: Data?
        let monitor = CodexTurnMonitor(read: { _ in data }, now: { time })
        monitor.configure(enabled: true)
        monitor.connectDirectory(folder)
        let verifier = AgentHookVerifier(now: { time })
        verifier.bind(codex: monitor, claude: ClaudeHookMonitor())
        verifier.start(codex: monitor)
        XCTAssertEqual(
            verifier.state(for: .codex, at: time.addingTimeInterval(180)),
            .waiting(moment)
        )
        XCTAssertEqual(
            verifier.state(for: .codex, at: time.addingTimeInterval(181)),
            .timedOut
        )
        time = moment.addingTimeInterval(190)
        data = codexMarker(time)
        monitor.refresh()
        XCTAssertEqual(verifier.codexState, .timedOut)
        monitor.configure(enabled: false)
    }

    func testStopAllResetsAndRemovesOldSubscriptions() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        var time = moment
        var content: Data?
        let monitor = CodexTurnMonitor(read: { _ in content }, now: { time })
        monitor.configure(enabled: true)
        monitor.connectDirectory(folder)
        let verifier = AgentHookVerifier(now: { time })
        verifier.bind(codex: monitor, claude: ClaudeHookMonitor())
        verifier.start(codex: monitor)
        verifier.stopAll()
        time = moment.addingTimeInterval(4)
        content = codexMarker(time)
        monitor.refresh()
        XCTAssertEqual(verifier.codexState, .notStarted)
        XCTAssertEqual(verifier.claudeState, .notStarted)
        monitor.configure(enabled: false)
    }

    func testOnlyExistingMarkersNoSensitiveDataInVerification() {
        XCTAssertNil(AgentHookMarker.codex(.off))
        XCTAssertNil(AgentHookMarker.codex(.unavailable))
        XCTAssertNil(AgentHookMarker.claude(.unconnected))
        let marker = AgentHookMarker.claude(
            .observed(event: .responseStopped, timestamp: moment)
        )
        XCTAssertEqual(marker?.kind, "Stop")
        XCTAssertEqual(marker?.timestamp, moment)
    }
}
