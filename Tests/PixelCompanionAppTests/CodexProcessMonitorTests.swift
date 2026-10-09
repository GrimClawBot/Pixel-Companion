import Foundation
import PixelCompanionCore
@testable import PixelCompanion
import XCTest

final class CodexProcessMonitorTests: XCTestCase {
    func testExactProcessNamesOnly() {
        XCTAssertEqual(CodexProcessClassification.count(names: []), 0)
        XCTAssertEqual(
            CodexProcessClassification.count(
                names: ["codex", "Codex", "codex-helper", "codexBar", "codex", "xcode"]
            ),
            2
        )
    }

    func testProcessCountBounded() {
        XCTAssertEqual(
            CodexProcessClassification.count(names: Array(repeating: "codex", count: 1_000)),
            64
        )
    }

    @MainActor
    func testNeverReadsUntilOptIn() {
        var calls = 0
        let monitor = CodexProcessMonitor(readNames: {
            calls += 1
            return ["codex"]
        })
        monitor.refresh()
        XCTAssertEqual(calls, 0)
        XCTAssertEqual(monitor.presence, .off)
        XCTAssertEqual(CodexProcessMonitor.refreshInterval, 15)
    }

    @MainActor
    func testEnableDetectsAndDisableClears() {
        var calls = 0
        let monitor = CodexProcessMonitor(readNames: {
            calls += 1
            return ["codex", "unrelated"]
        })
        monitor.configure(enabled: true)
        XCTAssertEqual(monitor.presence, .detected(count: 1))
        XCTAssertEqual(calls, 1)
        monitor.configure(enabled: false)
        XCTAssertEqual(monitor.presence, .off)
        monitor.refresh()
        XCTAssertEqual(calls, 1)
    }

    @MainActor
    func testUnavailableAndAbsenceNeverInventActivity() {
        var result: [String]?
        let monitor = CodexProcessMonitor(readNames: { result })
        monitor.configure(enabled: true)
        XCTAssertEqual(monitor.presence, .unavailable)
        result = ["other"]
        monitor.refresh()
        XCTAssertEqual(monitor.presence, .absent)
        result = ["codex"]
        monitor.refresh()
        XCTAssertEqual(monitor.presence, .detected(count: 1))
        monitor.configure(enabled: false)
    }

    @MainActor
    func testRedundantEnableDoesNotDuplicatePollingOrImmediateRead() {
        var reads = 0
        let monitor = CodexProcessMonitor(readNames: {
            reads += 1
            return ["codex"]
        })
        monitor.configure(enabled: true)
        monitor.configure(enabled: true)
        XCTAssertEqual(reads, 1)
        monitor.configure(enabled: false)
    }

    func testPublicMacOSProbeIsBoundedAndOptional() {
        // macOS is allowed to deny enumeration; neither a result nor nil
        // can be reinterpreted as proof of session activity.
        if let names = CodexProcessReader.readNames() {
            XCTAssertLessThanOrEqual(CodexProcessClassification.count(names: names), 64)
            // Other processes can legitimately contain whitespace/punctuation.
            XCTAssertLessThanOrEqual(names.count, 16_384)
            XCTAssertTrue(names.allSatisfy { $0.utf8.count <= 16 })
            print("PC041_MAC_CODEX_PROCESS_COUNT=\(CodexProcessClassification.count(names: names))")
        }
    }

    func testStandaloneCodexPreferenceOffByDefault() {
        let suite = "CodexMonitor-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(defaults: defaults)
        XCTAssertFalse(settings.codexPresenceEnabled)
        settings.codexPresenceEnabled = true
        XCTAssertTrue(SettingsStore(defaults: defaults).codexPresenceEnabled)
        XCTAssertFalse(settings.localAgentFeedEnabled)
        settings.reset()
        XCTAssertFalse(settings.codexPresenceEnabled)
    }
}
