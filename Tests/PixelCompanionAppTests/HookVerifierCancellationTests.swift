import Foundation
@testable import PixelCompanion
import XCTest

/// A deliberately stuck local marker read. The test owns the only release
/// signal: neither cancelling a check nor discarding the verifier may block.
private final class StalledMarkerReader: @unchecked Sendable {
    private let lock = NSLock()
    private let gate = DispatchSemaphore(value: 0)
    private var invocations = 0
    let firstStarted: XCTestExpectation
    let payload: Data

    init(firstStarted: XCTestExpectation, payload: Data) {
        self.firstStarted = firstStarted
        self.payload = payload
    }

    func read(_ url: URL) -> Data? {
        lock.lock()
        invocations += 1
        let first = invocations == 1
        lock.unlock()
        if first {
            firstStarted.fulfill()
            gate.wait()
        }
        return payload
    }

    func release() { gate.signal() }

    var calls: Int {
        lock.lock()
        defer { lock.unlock() }
        return invocations
    }
}

@MainActor
private final class WeakVerifierBox {
    weak var value: AgentHookVerifier?
    init(_ verifier: AgentHookVerifier?) { value = verifier }
}

@MainActor
final class HookVerifierCancellationTests: XCTestCase {
    private let moment = Date(timeIntervalSince1970: 1_800_000_000)

    private func fixtureFolder() -> URL {
        // The selected URL itself is not read by the injected reader.
        URL(fileURLWithPath: "/tmp/pc-verifier-synthetic-" + UUID().uuidString, isDirectory: true)
    }

    func testCodexStopReleasesVerifierWhileReadIsStillBlocked() async {
        let started = expectation(description: "Codex background read began")
        let marker = Data(
            #"{"schemaVersion":1,"event":"agent-turn-complete","lastCompletedAt":"2027-01-15T08:00:00Z"}"#.utf8
        )
        let reader = StalledMarkerReader(firstStarted: started, payload: marker)
        defer { reader.release() }
        let monitor = CodexTurnMonitor(read: { reader.read($0) }, now: { self.moment })
        monitor.configure(enabled: true)
        monitor.connectDirectory(fixtureFolder())
        await fulfillment(of: [started], timeout: 3)
        var verifier: AgentHookVerifier? = AgentHookVerifier(now: { self.moment })
        let weakVerifier = WeakVerifierBox(verifier)
        verifier?.bind(codex: monitor, claude: ClaudeHookMonitor())
        verifier?.start(codex: monitor)
        XCTAssertEqual(reader.calls, 1)
        verifier?.stopAll()
        verifier = nil
        XCTAssertNil(weakVerifier.value, "Cancelled check must not retain the verifier")
        XCTAssertEqual(reader.calls, 1, "Start/stop cannot spawn work behind a stuck read")
        reader.release()
        await awaitLocalReport { !monitor.isRefreshing }
        monitor.configure(enabled: false)
    }

    func testClaudeStopReleasesVerifierWhileReadIsStillBlocked() async {
        let started = expectation(description: "Claude background read began")
        let marker = Data(
            #"{"schemaVersion":1,"event":"Stop","observedAt":"2027-01-15T08:00:00Z"}"#.utf8
        )
        let reader = StalledMarkerReader(firstStarted: started, payload: marker)
        defer { reader.release() }
        let monitor = ClaudeHookMonitor(read: { reader.read($0) }, now: { self.moment })
        monitor.configure(enabled: true)
        monitor.connectDirectory(fixtureFolder())
        await fulfillment(of: [started], timeout: 3)
        var verifier: AgentHookVerifier? = AgentHookVerifier(now: { self.moment })
        let weakVerifier = WeakVerifierBox(verifier)
        verifier?.bind(codex: CodexTurnMonitor(), claude: monitor)
        verifier?.start(claude: monitor)
        XCTAssertEqual(reader.calls, 1)
        verifier?.stopAll()
        verifier = nil
        XCTAssertNil(weakVerifier.value, "Cancelled Claude check must not retain the verifier")
        XCTAssertEqual(reader.calls, 1)
        reader.release()
        await awaitLocalReport { !monitor.isRefreshing }
        monitor.configure(enabled: false)
    }

    func testTwentyRetriesQueueOnlyOneNewCodexBaselineRead() async {
        let started = expectation(description: "Codex stale initial reader started")
        let marker = Data(
            #"{"schemaVersion":1,"event":"agent-turn-complete","lastCompletedAt":"2027-01-15T08:00:00Z"}"#.utf8
        )
        let reader = StalledMarkerReader(firstStarted: started, payload: marker)
        defer { reader.release() }
        let monitor = CodexTurnMonitor(read: { reader.read($0) }, now: { self.moment })
        monitor.configure(enabled: true)
        monitor.connectDirectory(fixtureFolder())
        await fulfillment(of: [started], timeout: 3)
        let verifier = AgentHookVerifier(now: { self.moment })
        verifier.bind(codex: monitor, claude: ClaudeHookMonitor())
        for _ in 0..<20 {
            verifier.start(codex: monitor)
            verifier.stop(.codex)
        }
        verifier.start(codex: monitor)
        XCTAssertEqual(reader.calls, 1)
        XCTAssertFalse(verifier.isCodexArmed)
        reader.release()
        await awaitLocalReport { verifier.isCodexArmed }
        XCTAssertEqual(reader.calls, 2, "Only one fresh poll follows old blocked work")
        XCTAssertEqual(verifier.codexState, .waiting(moment))
        verifier.stopAll()
        monitor.configure(enabled: false)
    }

    func testSwitchingCodexFolderCompletesPendingCheckAsNeedsSetup() async {
        let prior = Data(
            #"{"schemaVersion":1,"event":"agent-turn-complete","lastCompletedAt":"2027-01-15T08:00:00Z"}"#.utf8
        )
        let reader = DelayedBaselineReader(prior)
        defer { reader.release() }
        let monitor = CodexTurnMonitor(read: { reader.read($0) }, now: { self.moment })
        monitor.configure(enabled: true)
        monitor.connectDirectory(fixtureFolder())
        await awaitLocalReport { reader.started }
        let verifier = AgentHookVerifier(now: { self.moment })
        verifier.bind(codex: monitor, claude: ClaudeHookMonitor())
        verifier.start(codex: monitor)
        monitor.connectDirectory(fixtureFolder())
        XCTAssertEqual(verifier.codexState, .needsSetup)
        XCTAssertFalse(verifier.isCodexArmed)
        reader.release()
        await awaitLocalReport { !monitor.isRefreshing }
        XCTAssertEqual(verifier.codexState, .needsSetup)
        monitor.configure(enabled: false)
    }

    func testSwitchingClaudeFolderCompletesPendingCheckAsNeedsSetup() async {
        let prior = Data(
            #"{"schemaVersion":1,"event":"Stop","observedAt":"2027-01-15T08:00:00Z"}"#.utf8
        )
        let reader = DelayedBaselineReader(prior)
        defer { reader.release() }
        let monitor = ClaudeHookMonitor(read: { reader.read($0) }, now: { self.moment })
        monitor.configure(enabled: true)
        monitor.connectDirectory(fixtureFolder())
        await awaitLocalReport { reader.started }
        let verifier = AgentHookVerifier(now: { self.moment })
        verifier.bind(codex: CodexTurnMonitor(), claude: monitor)
        verifier.start(claude: monitor)
        monitor.connectDirectory(fixtureFolder())
        XCTAssertEqual(verifier.claudeState, .needsSetup)
        XCTAssertFalse(verifier.isClaudeArmed)
        reader.release()
        await awaitLocalReport { !monitor.isRefreshing }
        XCTAssertEqual(verifier.claudeState, .needsSetup)
        monitor.configure(enabled: false)
    }

    func testAlreadyArmedCodexCheckRejectsNewFolderMarkers() async {
        let data = Data(
            #"{"schemaVersion":1,"event":"agent-turn-complete","lastCompletedAt":"2027-01-15T08:00:00Z"}"#.utf8
        )
        let probe = LockedLocalReportReader(data)
        let monitor = CodexTurnMonitor(read: { probe.read($0) }, now: { self.moment })
        monitor.configure(enabled: true)
        monitor.connectDirectory(fixtureFolder())
        await awaitLocalReport { !monitor.isRefreshing }
        let verifier = AgentHookVerifier(now: { self.moment })
        verifier.bind(codex: monitor, claude: ClaudeHookMonitor())
        verifier.start(codex: monitor)
        await awaitLocalReport { verifier.isCodexArmed }
        monitor.connectDirectory(fixtureFolder())
        XCTAssertFalse(verifier.isCodexArmed)
        XCTAssertEqual(verifier.codexState, .needsSetup)
        await awaitLocalReport { !monitor.isRefreshing }
        XCTAssertEqual(verifier.codexState, .needsSetup)
        monitor.configure(enabled: false)
    }

    func testAlreadyArmedClaudeCheckRejectsNewFolderMarkers() async {
        let data = Data(
            #"{"schemaVersion":1,"event":"Stop","observedAt":"2027-01-15T08:00:00Z"}"#.utf8
        )
        let probe = LockedLocalReportReader(data)
        let monitor = ClaudeHookMonitor(read: { probe.read($0) }, now: { self.moment })
        monitor.configure(enabled: true)
        monitor.connectDirectory(fixtureFolder())
        await awaitLocalReport { !monitor.isRefreshing }
        let verifier = AgentHookVerifier(now: { self.moment })
        verifier.bind(codex: CodexTurnMonitor(), claude: monitor)
        verifier.start(claude: monitor)
        await awaitLocalReport { verifier.isClaudeArmed }
        monitor.connectDirectory(fixtureFolder())
        XCTAssertFalse(verifier.isClaudeArmed)
        XCTAssertEqual(verifier.claudeState, .needsSetup)
        await awaitLocalReport { !monitor.isRefreshing }
        XCTAssertEqual(verifier.claudeState, .needsSetup)
        monitor.configure(enabled: false)
    }

    func testDisconnectDuringBlockedClaudeBaselineNeverArmsCheck() async {
        let started = expectation(description: "Claude selected file reading")
        let marker = Data(
            #"{"schemaVersion":1,"event":"Stop","observedAt":"2027-01-15T08:00:00Z"}"#.utf8
        )
        let reader = StalledMarkerReader(firstStarted: started, payload: marker)
        defer { reader.release() }
        let monitor = ClaudeHookMonitor(read: { reader.read($0) }, now: { self.moment })
        monitor.configure(enabled: true)
        monitor.connectDirectory(fixtureFolder())
        await fulfillment(of: [started], timeout: 3)
        let verifier = AgentHookVerifier(now: { self.moment })
        verifier.bind(codex: CodexTurnMonitor(), claude: monitor)
        verifier.start(claude: monitor)
        monitor.disconnect()
        XCTAssertFalse(verifier.isClaudeArmed)
        XCTAssertEqual(verifier.claudeState, .needsSetup)
        reader.release()
        try? await Task.sleep(for: .milliseconds(90))
        XCTAssertFalse(verifier.isClaudeArmed)
        XCTAssertEqual(verifier.claudeState, .needsSetup)
        monitor.configure(enabled: false)
    }
}
