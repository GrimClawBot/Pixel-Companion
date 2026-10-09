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

    func testFreshExistingCodexMarkerDoesNotProveNewDelivery() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        var time = moment
        let probe = LockedLocalReportReader(codexMarker(time))
        let monitor = CodexTurnMonitor(read: { probe.read($0) }, now: { time })
        monitor.configure(enabled: true)
        monitor.connectDirectory(folder)
        await awaitLocalReport { !monitor.isRefreshing }
        let verifier = AgentHookVerifier(now: { time })
        verifier.bind(codex: monitor, claude: ClaudeHookMonitor())
        verifier.start(codex: monitor)
        await awaitLocalReport { verifier.isCodexArmed }
        XCTAssertEqual(verifier.codexState, .waiting(moment))
        monitor.refresh()
        await awaitLocalReport { !monitor.isRefreshing }
        XCTAssertEqual(verifier.codexState, .waiting(moment))
        time = moment.addingTimeInterval(10)
        probe.set(codexMarker(time))
        monitor.refresh()
        await awaitLocalReport { verifier.codexState == .observed(time) }
        XCTAssertEqual(verifier.codexState, .observed(time))
        monitor.configure(enabled: false)
    }

    func testFirstMarkerAfterPreviouslyMissingFileCounts() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        var time = moment
        let probe = LockedLocalReportReader()
        let monitor = CodexTurnMonitor(read: { probe.read($0) }, now: { time })
        monitor.configure(enabled: true)
        monitor.connectDirectory(folder)
        await awaitLocalReport { !monitor.isRefreshing }
        let verifier = AgentHookVerifier(now: { time })
        verifier.bind(codex: monitor, claude: ClaudeHookMonitor())
        verifier.start(codex: monitor)
        await awaitLocalReport { verifier.isCodexArmed }
        XCTAssertEqual(verifier.codexState, .waiting(moment))
        time = moment.addingTimeInterval(5)
        probe.set(codexMarker(time))
        monitor.refresh()
        await awaitLocalReport { verifier.codexState == .observed(time) }
        XCTAssertEqual(verifier.codexState, .observed(time))
        monitor.configure(enabled: false)
    }

    func testNoReadsBeforeStartBeyondExistingMonitorBehavior() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let probe = LockedLocalReportReader()
        let monitor = CodexTurnMonitor(
            read: { probe.read($0) }, now: { self.moment }
        )
        let verifier = AgentHookVerifier(now: { self.moment })
        verifier.bind(codex: monitor, claude: ClaudeHookMonitor())
        XCTAssertEqual(probe.calls, 0)
        verifier.start(codex: monitor)
        if monitor.isConnected {
            await awaitLocalReport { verifier.isCodexArmed }
        }
        XCTAssertEqual(verifier.codexState, .needsSetup)
        XCTAssertEqual(probe.calls, 0)
        monitor.configure(enabled: true)
        monitor.connectDirectory(folder)
        await awaitLocalReport { monitor.status == .unavailable && !monitor.isRefreshing }
        let existingReads = probe.calls
        verifier.start(codex: monitor)
        if monitor.isConnected {
            await awaitLocalReport { verifier.isCodexArmed }
        }
        await awaitLocalReport { probe.calls == existingReads + 1 }
        monitor.configure(enabled: false)
    }

    func testStaleAtArmTimeDoesNotCountAsNewEvenIfFileChanges() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let stale = moment.addingTimeInterval(-130)
        let probe = LockedLocalReportReader(codexMarker(stale))
        let monitor = CodexTurnMonitor(read: { probe.read($0) }, now: { self.moment })
        monitor.configure(enabled: true)
        monitor.connectDirectory(folder)
        await awaitLocalReport { !monitor.isRefreshing }
        let verifier = AgentHookVerifier(now: { self.moment })
        verifier.bind(codex: monitor, claude: ClaudeHookMonitor())
        verifier.start(codex: monitor)
        if monitor.isConnected {
            await awaitLocalReport { verifier.isCodexArmed }
        }
        probe.set(codexMarker(moment.addingTimeInterval(-40)))
        monitor.refresh()
        await awaitLocalReport { !monitor.isRefreshing }
        XCTAssertEqual(verifier.codexState, .waiting(moment))
        monitor.configure(enabled: false)
    }

    func testSameSecondIdenticalEventCannotCountTwice() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let data = codexMarker(moment)
        let probe = LockedLocalReportReader(data)
        let monitor = CodexTurnMonitor(read: { probe.read($0) }, now: { self.moment })
        monitor.configure(enabled: true)
        monitor.connectDirectory(folder)
        await awaitLocalReport { !monitor.isRefreshing }
        let verifier = AgentHookVerifier(now: { self.moment })
        verifier.bind(codex: monitor, claude: ClaudeHookMonitor())
        verifier.start(codex: monitor)
        if monitor.isConnected {
            await awaitLocalReport { verifier.isCodexArmed }
        }
        for _ in 0..<4 { monitor.refresh() }
        await awaitLocalReport { !monitor.isRefreshing }
        XCTAssertEqual(verifier.codexState, .waiting(moment))
        monitor.configure(enabled: false)
    }

    func testClaudeDifferentMilestoneTimestampAfterArmCanCount() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        var time = moment
        let probe = LockedLocalReportReader(claudeMarker("SessionStart", moment))
        let monitor = ClaudeHookMonitor(read: { probe.read($0) }, now: { time })
        monitor.configure(enabled: true)
        monitor.connectDirectory(folder)
        await awaitLocalReport { !monitor.isRefreshing }
        let verifier = AgentHookVerifier(now: { time })
        verifier.bind(codex: CodexTurnMonitor(), claude: monitor)
        verifier.start(claude: monitor)
        await awaitLocalReport { verifier.isClaudeArmed }
        time = time.addingTimeInterval(3)
        probe.set(claudeMarker("Stop", time))
        monitor.refresh()
        await awaitLocalReport { verifier.claudeState == .observed(time) }
        XCTAssertEqual(verifier.claudeState, .observed(time))
        monitor.configure(enabled: false)
    }

    func testCodexAndClaudeChecksRemainIndependent() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        var time = moment
        let codexProbe = LockedLocalReportReader(codexMarker(time))
        let claudeProbe = LockedLocalReportReader(claudeMarker("SessionStart", time))
        let codex = CodexTurnMonitor(read: { codexProbe.read($0) }, now: { time })
        let claude = ClaudeHookMonitor(read: { claudeProbe.read($0) }, now: { time })
        codex.configure(enabled: true)
        claude.configure(enabled: true)
        codex.connectDirectory(folder)
        claude.connectDirectory(folder)
        await awaitLocalReport { !codex.isRefreshing && !claude.isRefreshing }
        let verifier = AgentHookVerifier(now: { time })
        verifier.bind(codex: codex, claude: claude)
        verifier.start(codex: codex)
        verifier.start(claude: claude)
        await awaitLocalReport { verifier.isCodexArmed && verifier.isClaudeArmed }
        time = moment.addingTimeInterval(5)
        codexProbe.set(codexMarker(time))
        codex.refresh()
        await awaitLocalReport { verifier.codexState == .observed(time) }
        XCTAssertEqual(verifier.codexState, .observed(time))
        XCTAssertEqual(verifier.claudeState, .waiting(moment))
        claudeProbe.set(claudeMarker("Stop", time))
        claude.refresh()
        await awaitLocalReport { verifier.claudeState == .observed(time) }
        XCTAssertEqual(verifier.claudeState, .observed(time))
        codex.configure(enabled: false)
        claude.configure(enabled: false)
    }

    func testDisconnectClearsObservedResult() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        var time = moment
        let probe = LockedLocalReportReader(codexMarker(time))
        let monitor = CodexTurnMonitor(read: { probe.read($0) }, now: { time })
        monitor.configure(enabled: true)
        monitor.connectDirectory(folder)
        await awaitLocalReport { !monitor.isRefreshing }
        let verifier = AgentHookVerifier(now: { time })
        verifier.bind(codex: monitor, claude: ClaudeHookMonitor())
        verifier.start(codex: monitor)
        if monitor.isConnected {
            await awaitLocalReport { verifier.isCodexArmed }
        }
        time = moment.addingTimeInterval(2)
        probe.set(codexMarker(time))
        monitor.refresh()
        await awaitLocalReport { verifier.codexState == .observed(time) }
        XCTAssertEqual(verifier.codexState, .observed(time))
        monitor.disconnect()
        XCTAssertEqual(verifier.codexState, .needsSetup)
        monitor.configure(enabled: false)
    }

    func testTimeoutRefusesLateMarkersAndDisplaysTimeout() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        var time = moment
        let probe = LockedLocalReportReader()
        let monitor = CodexTurnMonitor(read: { probe.read($0) }, now: { time })
        monitor.configure(enabled: true)
        monitor.connectDirectory(folder)
        await awaitLocalReport { !monitor.isRefreshing }
        let verifier = AgentHookVerifier(now: { time })
        verifier.bind(codex: monitor, claude: ClaudeHookMonitor())
        verifier.start(codex: monitor)
        if monitor.isConnected {
            await awaitLocalReport { verifier.isCodexArmed }
        }
        XCTAssertEqual(
            verifier.state(for: .codex, at: time.addingTimeInterval(180)),
            .waiting(moment)
        )
        XCTAssertEqual(
            verifier.state(for: .codex, at: time.addingTimeInterval(181)),
            .timedOut
        )
        time = moment.addingTimeInterval(190)
        probe.set(codexMarker(time))
        monitor.refresh()
        await awaitLocalReport { monitor.status == .observed(time) }
        await awaitLocalReport { verifier.codexState == .timedOut }
        XCTAssertEqual(verifier.codexState, .timedOut)
        monitor.configure(enabled: false)
    }

}

extension AgentHookVerificationTests {
    func testCodexPreexistingMarkerCannotPassBeforeAsyncBaseline() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        var time = moment
        let blocked = DelayedBaselineReader(codexMarker(moment))
        defer { blocked.release() }
        let monitor = CodexTurnMonitor(read: { blocked.read($0) }, now: { time })
        monitor.configure(enabled: true)
        monitor.connectDirectory(folder)
        await awaitLocalReport { blocked.started }
        let verifier = AgentHookVerifier(now: { time })
        verifier.bind(codex: monitor, claude: ClaudeHookMonitor())
        verifier.start(codex: monitor)
        XCTAssertFalse(verifier.isCodexArmed)
        XCTAssertEqual(verifier.codexState, .waiting(moment))
        blocked.release()
        await awaitLocalReport { verifier.isCodexArmed }
        XCTAssertEqual(verifier.codexState, .waiting(moment))
        monitor.refresh()
        await awaitLocalReport { !monitor.isRefreshing }
        XCTAssertEqual(verifier.codexState, .waiting(moment))
        time = moment.addingTimeInterval(5)
        blocked.set(codexMarker(time))
        monitor.refresh()
        await awaitLocalReport { verifier.codexState == .observed(time) }
        monitor.configure(enabled: false)
    }

    func testClaudePreexistingMarkerCannotPassBeforeAsyncBaseline() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        var time = moment
        let blocked = DelayedBaselineReader(claudeMarker("Stop", moment))
        defer { blocked.release() }
        let monitor = ClaudeHookMonitor(read: { blocked.read($0) }, now: { time })
        monitor.configure(enabled: true)
        monitor.connectDirectory(folder)
        await awaitLocalReport { blocked.started }
        let verifier = AgentHookVerifier(now: { time })
        verifier.bind(codex: CodexTurnMonitor(), claude: monitor)
        verifier.start(claude: monitor)
        XCTAssertFalse(verifier.isClaudeArmed)
        XCTAssertEqual(verifier.claudeState, .waiting(moment))
        blocked.release()
        await awaitLocalReport { verifier.isClaudeArmed }
        XCTAssertEqual(verifier.claudeState, .waiting(moment))
        monitor.refresh()
        await awaitLocalReport { !monitor.isRefreshing }
        XCTAssertEqual(verifier.claudeState, .waiting(moment))
        time = moment.addingTimeInterval(5)
        blocked.set(claudeMarker("Stop", time))
        monitor.refresh()
        await awaitLocalReport { verifier.claudeState == .observed(time) }
        monitor.configure(enabled: false)
    }

    func testStopAllResetsAndRemovesOldSubscriptions() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        var time = moment
        let probe = LockedLocalReportReader()
        let monitor = CodexTurnMonitor(read: { probe.read($0) }, now: { time })
        monitor.configure(enabled: true)
        monitor.connectDirectory(folder)
        await awaitLocalReport { !monitor.isRefreshing }
        let verifier = AgentHookVerifier(now: { time })
        verifier.bind(codex: monitor, claude: ClaudeHookMonitor())
        verifier.start(codex: monitor)
        if monitor.isConnected {
            await awaitLocalReport { verifier.isCodexArmed }
        }
        verifier.stopAll()
        time = moment.addingTimeInterval(4)
        probe.set(codexMarker(time))
        monitor.refresh()
        await awaitLocalReport { monitor.status == .observed(time) }
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
