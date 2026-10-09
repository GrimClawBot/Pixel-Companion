import Foundation
import PixelCompanionCore
@testable import PixelCompanion
import XCTest

final class AgentSessionMonitorTests: XCTestCase {
    private func session(
        _ state: AgentSessionSnapshot.RunState,
        start: Date? = nil,
        finish: Date? = nil,
        contextUsed: Int? = nil,
        contextWindow: Int? = nil,
        inputTokens: Int? = nil
    ) -> AgentSessionSnapshot {
        AgentSessionSnapshot(
            id: "session-1", agentID: "agent-1", agentName: "Atlas",
            agentStatus: state.rawValue, runState: state,
            inputTokens: inputTokens, contextUsedTokens: contextUsed,
            contextWindowTokens: contextWindow,
            startedAt: start, finishedAt: finish
        )
    }

    func testOnlyConfirmedRunningShowsIndeterminateActivity() {
        for state in AgentSessionSnapshot.RunState.allCases {
            let value = session(state)
            XCTAssertEqual(
                AgentSessionMonitorPresentation.showsRunningIndicator(value, reduceMotion: false),
                state == .running, state.rawValue
            )
            XCTAssertFalse(
                AgentSessionMonitorPresentation.showsRunningIndicator(value, reduceMotion: true),
                state.rawValue
            )
        }
    }

    func testPhaseDoesNotInventRunCompletionOrPromoteUnknownToLive() {
        XCTAssertTrue(AgentSessionMonitorPresentation.phase(session(.running))
            .contains("completion not reported"))
        XCTAssertTrue(AgentSessionMonitorPresentation.phase(session(.queued))
            .contains("waiting to start"))
        XCTAssertEqual(AgentSessionMonitorPresentation.phase(session(.completed)), "Completed")
        XCTAssertEqual(AgentSessionMonitorPresentation.phase(session(.failed)), "Failed")
        XCTAssertEqual(AgentSessionMonitorPresentation.phase(session(.cancelled)), "Cancelled")
        XCTAssertEqual(AgentSessionMonitorPresentation.phase(session(.idle)), "No active run")
        XCTAssertEqual(AgentSessionMonitorPresentation.phase(session(.unknown)),
                       "Run state unconfirmed")
    }

    func testDurationRequiresTerminalStateAndChronologicallyValidTimestamps() {
        let start = Date(timeIntervalSince1970: 1_000)
        let finish = start.addingTimeInterval(3_745)
        for state in [
            AgentSessionSnapshot.RunState.completed, .failed, .cancelled
        ] {
            XCTAssertEqual(
                AgentSessionMonitorPresentation.reportedDuration(
                    session(state, start: start, finish: finish)
                ), 3_745
            )
        }
        for state in [
            AgentSessionSnapshot.RunState.running, .queued, .idle, .unknown
        ] {
            XCTAssertNil(AgentSessionMonitorPresentation.reportedDuration(
                session(state, start: start, finish: finish)
            ))
        }
        XCTAssertNil(AgentSessionMonitorPresentation.reportedDuration(
            session(.completed, start: finish, finish: start)
        ))
        XCTAssertNil(AgentSessionMonitorPresentation.reportedDuration(
            session(.completed, start: start)
        ))
        XCTAssertNil(AgentSessionMonitorPresentation.reportedDuration(
            session(.completed, finish: finish)
        ))
    }

    func testDurationFormattingDoesNotImplyPercentage() {
        XCTAssertEqual(AgentSessionMonitorPresentation.durationLabel(0), "0s")
        XCTAssertEqual(AgentSessionMonitorPresentation.durationLabel(59), "59s")
        XCTAssertEqual(AgentSessionMonitorPresentation.durationLabel(61), "1m 1s")
        XCTAssertEqual(AgentSessionMonitorPresentation.durationLabel(3_745), "1h 2m")
    }

    func testContextOnlyUsesReportedOccupancyNotCumulativeTokens() {
        let unavailable = session(.running, inputTokens: 25_000)
        XCTAssertNil(AgentUsagePresentation.contextFraction(unavailable))
        XCTAssertEqual(
            AgentSessionMonitorPresentation.contextStatus(unavailable),
            "Context window not reported"
        )
        XCTAssertEqual(
            AgentSessionMonitorPresentation.contextStatus(
                session(.running, contextUsed: 500, contextWindow: 1_000)
            ), "Context reported · 50% used"
        )
        XCTAssertEqual(
            AgentSessionMonitorPresentation.contextStatus(
                session(.running, contextUsed: 850, contextWindow: 1_000)
            ), "Context above 80% · 85%"
        )
        XCTAssertEqual(
            AgentSessionMonitorPresentation.contextStatus(
                session(.running, contextUsed: 900, contextWindow: 1_000)
            ), "Context nearly full · 90%"
        )
    }

    func testInvalidContextCountersAreUnavailable() {
        for (used, window) in [(1_001, 1_000), (-1, 1_000), (20, 0)] {
            let value = session(.running, contextUsed: used, contextWindow: window)
            XCTAssertNil(AgentUsagePresentation.contextFraction(value))
            XCTAssertEqual(
                AgentSessionMonitorPresentation.contextStatus(value),
                "Context window not reported"
            )
        }
    }
}
