import Foundation
@testable import PixelCompanion
import XCTest

@MainActor
final class LocalAgentActivityTimelineTests: XCTestCase {
    private let epoch = Date(timeIntervalSince1970: 1_800_000_000)

    func testDisabledSourcesHaveNoTimeline() {
        let timeline = LocalAgentActivityTimeline(now: { self.epoch })
        timeline.receive(codex: .off)
        timeline.receive(claude: .off)
        XCTAssertTrue(timeline.events.isEmpty)
        XCTAssertTrue(timeline.visible(at: epoch).isEmpty)
    }

    func testCombinesAndOrdersTwoIndependentSourcesNewestFirst() {
        let timeline = LocalAgentActivityTimeline(now: { self.epoch })
        timeline.receive(codex: .observed(epoch.addingTimeInterval(-12)))
        timeline.receive(claude: .observed(
            event: .promptSubmitted, timestamp: epoch.addingTimeInterval(-4)
        ))
        XCTAssertEqual(timeline.events.map(\.source), [.claudeCode, .codex])
        XCTAssertEqual(timeline.events[0].label, "Prompt submitted")
        XCTAssertEqual(timeline.events[1].label, "Turn finished (outcome unknown)")
    }

    func testRepeatedPolledMarkersDoNotGenerateDuplicateRows() {
        let timeline = LocalAgentActivityTimeline(now: { self.epoch })
        let marker = CodexTurnStatus.observed(epoch.addingTimeInterval(-1))
        timeline.receive(codex: marker)
        timeline.receive(codex: marker)
        timeline.receive(codex: marker)
        XCTAssertEqual(timeline.events.count, 1)
    }

    func testBothProvidersCanHaveSameTimestampWithoutCollision() {
        let timeline = LocalAgentActivityTimeline(now: { self.epoch })
        timeline.receive(codex: .observed(epoch))
        timeline.receive(claude: .observed(event: .responseStopped, timestamp: epoch))
        XCTAssertEqual(timeline.events.count, 2)
        XCTAssertNotEqual(timeline.events[0].id, timeline.events[1].id)
    }

    func testClaudeMilestonesAtSameTimeRemainDistinctIfTypesDiffer() {
        let timeline = LocalAgentActivityTimeline(now: { self.epoch })
        timeline.receive(claude: .observed(event: .sessionStart, timestamp: epoch))
        timeline.receive(claude: .observed(event: .promptSubmitted, timestamp: epoch))
        timeline.receive(claude: .observed(event: .promptSubmitted, timestamp: epoch))
        XCTAssertEqual(timeline.events.count, 2)
    }

    func testSourceFiltersDoNotLeakIntoPaperclip() {
        let timeline = LocalAgentActivityTimeline(now: { self.epoch })
        timeline.receive(codex: .observed(epoch))
        timeline.receive(claude: .observed(event: .responseStopped, timestamp: epoch))
        XCTAssertEqual(timeline.visible(filter: .all, at: epoch).count, 2)
        XCTAssertEqual(
            timeline.visible(filter: .codex, at: epoch).map(\.source), [.codex]
        )
        XCTAssertEqual(
            timeline.visible(filter: .claudeCode, at: epoch).map(\.source), [.claudeCode]
        )
        XCTAssertTrue(LocalAgentActivityFilter.allCases.allSatisfy { !$0.label.isEmpty })
    }

    func testDisableOneSourceErasesOnlyItsOwnHistory() {
        let timeline = LocalAgentActivityTimeline(now: { self.epoch })
        timeline.receive(codex: .observed(epoch))
        timeline.receive(claude: .observed(event: .sessionStart, timestamp: epoch))
        timeline.receive(codex: .off)
        XCTAssertEqual(timeline.events.map(\.source), [.claudeCode])
        timeline.receive(claude: .off)
        XCTAssertTrue(timeline.events.isEmpty)
    }

    func testUnavailableAndDisconnectedSourcesPurgeStoredMarkers() {
        let timeline = LocalAgentActivityTimeline(now: { self.epoch })
        timeline.receive(codex: .observed(epoch))
        timeline.receive(codex: .unavailable)
        XCTAssertTrue(timeline.events.isEmpty)
        timeline.receive(claude: .observed(event: .sessionEnd, timestamp: epoch))
        timeline.receive(claude: .unconnected)
        XCTAssertTrue(timeline.events.isEmpty)
    }

    func testPreviouslyStaleMarkerIsNotAddedAsFreshEvent() {
        let timeline = LocalAgentActivityTimeline(now: { self.epoch })
        timeline.receive(codex: .observed(epoch.addingTimeInterval(-121)))
        timeline.receive(claude: .observed(
            event: .sessionStart, timestamp: epoch.addingTimeInterval(-999)
        ))
        XCTAssertTrue(timeline.events.isEmpty)
    }

    func testVisibleNeverShowsEventsOlderThanRetentionWindow() {
        let timeline = LocalAgentActivityTimeline(now: { self.epoch })
        timeline.receive(codex: .observed(epoch))
        XCTAssertEqual(timeline.visible(at: epoch).count, 1)
        XCTAssertTrue(
            timeline.visible(at: epoch.addingTimeInterval(
                LocalAgentActivityTimeline.retentionInterval + 1
            )).isEmpty
        )
    }

    func testBoundedRetentionCannotGrowUnbounded() {
        let timeline = LocalAgentActivityTimeline(now: { self.epoch })
        for offset in 0..<50 {
            timeline.receive(claude: .observed(
                event: .promptSubmitted,
                timestamp: epoch.addingTimeInterval(Double(-offset))
            ))
        }
        XCTAssertEqual(timeline.events.count, LocalAgentActivityTimeline.maximumEvents)
        XCTAssertEqual(timeline.events.first?.timestamp, epoch)
        XCTAssertEqual(timeline.events.last?.timestamp, epoch.addingTimeInterval(-19))
    }

    func testOnlyUntrustedFutureTimestampsAreRejected() {
        let timeline = LocalAgentActivityTimeline(now: { self.epoch })
        timeline.receive(codex: .observed(epoch.addingTimeInterval(31)))
        XCTAssertTrue(timeline.events.isEmpty)
        timeline.receive(codex: .observed(epoch.addingTimeInterval(30)))
        XCTAssertEqual(timeline.events.count, 1)
        XCTAssertTrue(timeline.visible(at: epoch.addingTimeInterval(31)).isEmpty == false)
    }

    func testRealMonitorSubscriptionsFollowOptInAndDisconnect() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("PC44-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let iso = ISO8601DateFormatter().string(from: epoch)
        let codexData = Data(
            """
            {"schemaVersion":1,"event":"agent-turn-complete","lastCompletedAt":"\(iso)"}
            """.utf8
        )
        let claudeData = Data(
            """
            {"schemaVersion":1,"event":"Stop","observedAt":"\(iso)"}
            """.utf8
        )
        let codex = CodexTurnMonitor(read: { _ in codexData }, now: { self.epoch })
        let claude = ClaudeHookMonitor(read: { _ in claudeData }, now: { self.epoch })
        let timeline = LocalAgentActivityTimeline(now: { self.epoch })
        timeline.bind(codex: codex, claude: claude)
        XCTAssertTrue(timeline.events.isEmpty)
        codex.configure(enabled: true)
        codex.connectDirectory(folder)
        claude.configure(enabled: true)
        claude.connectDirectory(folder)
        XCTAssertEqual(timeline.events.count, 2)
        codex.refresh()
        claude.refresh()
        XCTAssertEqual(timeline.events.count, 2)
        codex.configure(enabled: false)
        XCTAssertEqual(timeline.events.map(\.source), [.claudeCode])
        claude.disconnect()
        XCTAssertTrue(timeline.events.isEmpty)
        claude.configure(enabled: false)
    }
}
