import Foundation
@testable import PixelCompanion
import XCTest

@MainActor
final class LocalConnectionHealthTests: XCTestCase {
    private let reference = Date(timeIntervalSince1970: 1_800_000_000)

    func testAllSourcesOffByDefault() {
        let rows = LocalConnectionHealth.snapshot(
            process: .off, codex: .off, claude: .off,
            feed: .disabled, now: reference
        )
        XCTAssertEqual(rows.count, 4)
        XCTAssertEqual(Set(rows.map(\.id)).count, 4)
        XCTAssertTrue(rows.allSatisfy { $0.kind == .off })
        XCTAssertTrue(rows.allSatisfy { !$0.accessibilitySummary.isEmpty })
    }

    func testEnabledButUnconnectedNeedsSetup() {
        XCTAssertEqual(
            LocalConnectionHealth.codexTurn(.unconnected, now: reference).kind, .needsSetup
        )
        XCTAssertEqual(
            LocalConnectionHealth.claudeHook(.unconnected, now: reference).kind, .needsSetup
        )
        XCTAssertEqual(
            LocalConnectionHealth.localFeed(.unconnected, now: reference).kind, .needsSetup
        )
    }

    func testCodexProcessDetectionNeverClaimsSessionActivity() {
        let detected = LocalConnectionHealth.codexProcess(.detected(count: 1))
        XCTAssertEqual(detected.kind, .detected)
        XCTAssertTrue(detected.detail.contains("not verified"))
        XCTAssertEqual(LocalConnectionHealth.codexProcess(.absent).kind, .notDetected)
        XCTAssertEqual(LocalConnectionHealth.codexProcess(.unavailable).kind, .unavailable)
    }

    func testCodexMarkerStopsLookingRecentAfter120Seconds() {
        let status = CodexTurnStatus.observed(reference)
        XCTAssertEqual(LocalConnectionHealth.codexTurn(status, now: reference).kind, .recent)
        XCTAssertEqual(
            LocalConnectionHealth.codexTurn(
                status, now: reference.addingTimeInterval(120)
            ).kind, .recent
        )
        let old = LocalConnectionHealth.codexTurn(
            status, now: reference.addingTimeInterval(121)
        )
        XCTAssertEqual(old.kind, .historical)
        XCTAssertTrue(old.detail.contains("not evidence"))
    }

    func testClaudeMilestonesNeverProveRunningOrTaskSuccess() {
        let status = ClaudeHookStatus.observed(event: .sessionStart, timestamp: reference)
        let fresh = LocalConnectionHealth.claudeHook(status, now: reference)
        XCTAssertEqual(fresh.kind, .recent)
        XCTAssertTrue(fresh.detail.contains("not verified"))
        let old = LocalConnectionHealth.claudeHook(
            status, now: reference.addingTimeInterval(121)
        )
        XCTAssertEqual(old.kind, .historical)
        XCTAssertTrue(old.detail.contains("not a live signal"))
    }

    func testValidEmptyStatusIsNotFabricatedLiveTelemetry() {
        let row = LocalConnectionHealth.localFeed(.empty, now: reference)
        XCTAssertEqual(row.kind, .empty)
        XCTAssertTrue(row.detail.contains("no sessions"))
        XCTAssertEqual(
            LocalConnectionHealth.localFeed(.unavailable, now: reference).kind, .unavailable
        )
    }

    func testMixedSessionFreshnessReportsCountsWithoutIdentity() {
        let sessions = [
            LocalAgentSession(
                id: "fresh", source: .codex, name: "Codex",
                state: .idle, updatedAt: reference
            ),
            LocalAgentSession(
                id: "stale", source: .hermes, name: "Hermes",
                state: .waiting, updatedAt: reference.addingTimeInterval(-121)
            )
        ]
        let row = LocalConnectionHealth.localFeed(.loaded(sessions), now: reference)
        XCTAssertEqual(row.kind, .recent)
        XCTAssertTrue(row.detail.contains("1 of 2"))
        XCTAssertFalse(row.detail.contains("Hermes"))
        XCTAssertEqual(
            LocalConnectionHealth.localFeed(
                .loaded(sessions), now: reference.addingTimeInterval(121)
            ).kind, .historical
        )
    }

    func testUnavailableNotMistakenForNotConnected() {
        XCTAssertEqual(
            LocalConnectionHealth.codexTurn(.unavailable, now: reference).kind,
            .unavailable
        )
        XCTAssertEqual(
            LocalConnectionHealth.claudeHook(.unavailable, now: reference).kind,
            .unavailable
        )
        XCTAssertNotEqual(
            LocalConnectionHealth.codexTurn(.unavailable, now: reference).kind,
            LocalConnectionHealth.codexTurn(.unconnected, now: reference).kind
        )
    }

    func testRefreshWhileAllSourcesOffNeverReadsAnything() {
        var processCalls = 0
        let codexProbe = MonitorReadProbe(bytes: nil)
        let claudeProbe = MonitorReadProbe(bytes: nil)
        let feedProbe = MonitorReadProbe(bytes: nil)
        let process = CodexProcessMonitor(readNames: {
            processCalls += 1
            return ["codex"]
        })
        let codex = CodexTurnMonitor(read: { codexProbe.read($0) })
        let claude = ClaudeHookMonitor(read: { claudeProbe.read($0) })
        let feed = LocalAgentFeedMonitor(read: { feedProbe.read($0) })
        process.refresh()
        codex.refresh()
        claude.refresh()
        feed.refresh()
        XCTAssertEqual(processCalls, 0)
        XCTAssertEqual(codexProbe.count, 0)
        XCTAssertEqual(claudeProbe.count, 0)
        XCTAssertEqual(feedProbe.count, 0)
    }

    func testProcessPresenceRefreshDoesNotEnableAnySource() {
        var calls = 0
        let monitor = CodexProcessMonitor(readNames: {
            calls += 1
            return []
        })
        monitor.configure(enabled: true)
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(
            LocalConnectionHealth.codexProcess(monitor.presence).kind, .notDetected
        )
        monitor.configure(enabled: false)
        XCTAssertEqual(LocalConnectionHealth.codexProcess(monitor.presence).kind, .off)
    }

    func testSnapshotIsSideEffectFree() {
        let codex = CodexTurnMonitor()
        let claude = ClaudeHookMonitor()
        let feed = LocalAgentFeedMonitor()
        let process = CodexProcessMonitor()
        let rows = LocalConnectionHealth.snapshot(
            process: process.presence, codex: codex.status,
            claude: claude.status, feed: feed.status, now: reference
        )
        XCTAssertEqual(rows.map(\.kind), [.off, .off, .off, .off])
        XCTAssertFalse(codex.enabled)
        XCTAssertFalse(claude.enabled)
        XCTAssertFalse(feed.enabled)
        XCTAssertFalse(process.enabled)
    }

    func testHealthTextDoesNotExposePrivateFields() {
        let rows = LocalConnectionHealth.snapshot(
            process: .detected(count: 5), codex: .observed(reference),
            claude: .observed(event: .responseFailed, timestamp: reference),
            feed: .empty, now: reference
        )
        let descriptions = rows.map(\.accessibilitySummary).joined(separator: "\n")
        for forbidden in ["/Users/", "thread-id", "transcript", "token", "approval"] {
            XCTAssertFalse(descriptions.contains(forbidden))
        }
    }
}
