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
        let probe = MonitorReadProbe(bytes: codexMarker(time))
        let monitor = CodexTurnMonitor(read: { probe.read($0) }, now: { time })
        monitor.configure(enabled: true)
        monitor.connectDirectory(folder)
        await waitForMonitorStatus { probe.count >= 1 && !monitor.isReading }
        let verifier = AgentHookVerifier(now: { time })
        verifier.bind(codex: monitor, claude: ClaudeHookMonitor())
        verifier.start(codex: monitor)
        await waitForMonitorStatus { probe.count >= 2 && !monitor.isReading }
        XCTAssertEqual(verifier.codexState, .waiting(moment))
        monitor.refresh()
        await waitForMonitorStatus { !monitor.isReading && probe.count >= 3 }
        XCTAssertEqual(verifier.codexState, .waiting(moment))
        time = moment.addingTimeInterval(10)
        probe.setBytes(codexMarker(time))
        monitor.refresh()
        await waitForMonitorStatus { verifier.codexState == .observed(time) }
        XCTAssertEqual(verifier.codexState, .observed(time))
        monitor.configure(enabled: false)
    }

    func testFirstMarkerAfterPreviouslyMissingFileCounts() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        var time = moment
        let probe = MonitorReadProbe(bytes: nil)
        let monitor = CodexTurnMonitor(read: { probe.read($0) }, now: { time })
        monitor.configure(enabled: true)
        monitor.connectDirectory(folder)
        await waitForMonitorStatus { probe.count >= 1 && !monitor.isReading }
        let verifier = AgentHookVerifier(now: { time })
        verifier.bind(codex: monitor, claude: ClaudeHookMonitor())
        verifier.start(codex: monitor)
        await waitForMonitorStatus { probe.count >= 2 && !monitor.isReading }
        XCTAssertEqual(verifier.codexState, .waiting(moment))
        time = moment.addingTimeInterval(5)
        probe.setBytes(codexMarker(time))
        monitor.refresh()
        await waitForMonitorStatus { verifier.codexState == .observed(time) }
        XCTAssertEqual(verifier.codexState, .observed(time))
        monitor.configure(enabled: false)
    }

    func testNoReadsBeforeStartBeyondExistingMonitorBehavior() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let probe = MonitorReadProbe(bytes: nil)
        let monitor = CodexTurnMonitor(
            read: { probe.read($0) }, now: { self.moment }
        )
        let verifier = AgentHookVerifier(now: { self.moment })
        verifier.bind(codex: monitor, claude: ClaudeHookMonitor())
        XCTAssertEqual(probe.count, 0)
        verifier.start(codex: monitor)
        XCTAssertEqual(verifier.codexState, .needsSetup)
        XCTAssertEqual(probe.count, 0)
        monitor.configure(enabled: true)
        monitor.connectDirectory(folder)
        await waitForMonitorStatus { probe.count == 1 && !monitor.isReading }
        let existingReads = probe.count
        verifier.start(codex: monitor)
        // An explicit verification attempts exactly one guarded fresh poll.
        await waitForMonitorStatus { probe.count == existingReads + 1 && !monitor.isReading }
        XCTAssertEqual(probe.count, existingReads + 1)
        monitor.configure(enabled: false)
    }

    func testStaleAtArmTimeDoesNotCountAsNewEvenIfFileChanges() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let stale = moment.addingTimeInterval(-130)
        let probe = MonitorReadProbe(bytes: codexMarker(stale))
        let monitor = CodexTurnMonitor(read: { probe.read($0) }, now: { self.moment })
        monitor.configure(enabled: true)
        monitor.connectDirectory(folder)
        await waitForMonitorStatus { probe.count >= 1 && !monitor.isReading }
        let verifier = AgentHookVerifier(now: { self.moment })
        verifier.bind(codex: monitor, claude: ClaudeHookMonitor())
        verifier.start(codex: monitor)
        probe.setBytes(codexMarker(moment.addingTimeInterval(-40)))
        monitor.refresh()
        XCTAssertEqual(verifier.codexState, .waiting(moment))
        monitor.configure(enabled: false)
    }

    func testSameSecondIdenticalEventCannotCountTwice() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let probe = MonitorReadProbe(bytes: codexMarker(moment))
        let monitor = CodexTurnMonitor(read: { probe.read($0) }, now: { self.moment })
        monitor.configure(enabled: true)
        monitor.connectDirectory(folder)
        await waitForMonitorStatus { probe.count >= 1 && !monitor.isReading }
        let verifier = AgentHookVerifier(now: { self.moment })
        verifier.bind(codex: monitor, claude: ClaudeHookMonitor())
        verifier.start(codex: monitor)
        for _ in 0..<4 { monitor.refresh() }
        XCTAssertEqual(verifier.codexState, .waiting(moment))
        monitor.configure(enabled: false)
    }

    func testClaudeDifferentMilestoneTimestampAfterArmCanCount() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        var time = moment
        let probe = MonitorReadProbe(bytes: claudeMarker("SessionStart", moment))
        let monitor = ClaudeHookMonitor(read: { probe.read($0) }, now: { time })
        monitor.configure(enabled: true)
        monitor.connectDirectory(folder)
        await waitForMonitorStatus { probe.count >= 1 && !monitor.isReading }
        let verifier = AgentHookVerifier(now: { time })
        verifier.bind(codex: CodexTurnMonitor(), claude: monitor)
        verifier.start(claude: monitor)
        await waitForMonitorStatus { probe.count >= 2 && !monitor.isReading }
        time = time.addingTimeInterval(3)
        probe.setBytes(claudeMarker("Stop", time))
        monitor.refresh()
        await waitForMonitorStatus { verifier.claudeState == .observed(time) }
        XCTAssertEqual(verifier.claudeState, .observed(time))
        monitor.configure(enabled: false)
    }

    func testCodexAndClaudeChecksRemainIndependent() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        var time = moment
        let codexProbe = MonitorReadProbe(bytes: codexMarker(time))
        let claudeProbe = MonitorReadProbe(bytes: claudeMarker("SessionStart", time))
        let codex = CodexTurnMonitor(read: { codexProbe.read($0) }, now: { time })
        let claude = ClaudeHookMonitor(read: { claudeProbe.read($0) }, now: { time })
        codex.configure(enabled: true)
        claude.configure(enabled: true)
        codex.connectDirectory(folder)
        claude.connectDirectory(folder)
        await waitForMonitorStatus {
            codexProbe.count > 0 && claudeProbe.count > 0
                && !codex.isReading && !claude.isReading
        }
        let verifier = AgentHookVerifier(now: { time })
        verifier.bind(codex: codex, claude: claude)
        verifier.start(codex: codex)
        verifier.start(claude: claude)
        await waitForMonitorStatus {
            codexProbe.count >= 2 && claudeProbe.count >= 2
                && !codex.isReading && !claude.isReading
        }
        time = moment.addingTimeInterval(5)
        codexProbe.setBytes(codexMarker(time))
        codex.refresh()
        await waitForMonitorStatus { verifier.codexState == .observed(time) }
        XCTAssertEqual(verifier.codexState, .observed(time))
        XCTAssertEqual(verifier.claudeState, .waiting(moment))
        claudeProbe.setBytes(claudeMarker("Stop", time))
        claude.refresh()
        await waitForMonitorStatus { verifier.claudeState == .observed(time) }
        XCTAssertEqual(verifier.claudeState, .observed(time))
        codex.configure(enabled: false)
        claude.configure(enabled: false)
    }

    func testDisconnectClearsObservedResult() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        var time = moment
        let probe = MonitorReadProbe(bytes: codexMarker(time))
        let monitor = CodexTurnMonitor(read: { probe.read($0) }, now: { time })
        monitor.configure(enabled: true)
        monitor.connectDirectory(folder)
        await waitForMonitorStatus { probe.count >= 1 && !monitor.isReading }
        let verifier = AgentHookVerifier(now: { time })
        verifier.bind(codex: monitor, claude: ClaudeHookMonitor())
        verifier.start(codex: monitor)
        await waitForMonitorStatus { probe.count >= 2 && !monitor.isReading }
        time = moment.addingTimeInterval(2)
        probe.setBytes(codexMarker(time))
        monitor.refresh()
        await waitForMonitorStatus { verifier.codexState == .observed(time) }
        XCTAssertEqual(verifier.codexState, .observed(time))
        monitor.disconnect()
        XCTAssertEqual(verifier.codexState, .needsSetup)
        monitor.configure(enabled: false)
    }

    func testTimeoutRefusesLateMarkersAndDisplaysTimeout() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        var time = moment
        let probe = MonitorReadProbe(bytes: nil)
        let monitor = CodexTurnMonitor(read: { probe.read($0) }, now: { time })
        monitor.configure(enabled: true)
        monitor.connectDirectory(folder)
        await waitForMonitorStatus { probe.count >= 1 && !monitor.isReading }
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
        probe.setBytes(codexMarker(time))
        await waitForMonitorStatus { probe.count >= 2 && !monitor.isReading }
        monitor.refresh()
        await waitForMonitorStatus { verifier.codexState == .timedOut }
        XCTAssertEqual(verifier.codexState, .timedOut)
        monitor.configure(enabled: false)
    }

    func testStopAllResetsAndRemovesOldSubscriptions() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        var time = moment
        let probe = MonitorReadProbe(bytes: nil)
        let monitor = CodexTurnMonitor(read: { probe.read($0) }, now: { time })
        monitor.configure(enabled: true)
        monitor.connectDirectory(folder)
        await waitForMonitorStatus { probe.count >= 1 && !monitor.isReading }
        let verifier = AgentHookVerifier(now: { time })
        verifier.bind(codex: monitor, claude: ClaudeHookMonitor())
        verifier.start(codex: monitor)
        verifier.stopAll()
        time = moment.addingTimeInterval(4)
        probe.setBytes(codexMarker(time))
        monitor.refresh()
        XCTAssertEqual(verifier.codexState, .notStarted)
        XCTAssertEqual(verifier.claudeState, .notStarted)
        monitor.configure(enabled: false)
    }

}

@MainActor
final class AgentHookMarkerContractTests: XCTestCase {
    private let moment = Date(timeIntervalSince1970: 1_800_000_000)
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
