import Foundation
@testable import PixelCompanionCore
import XCTest

final class CanonicalLiveActivityTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func event(
        _ name: String,
        kind: ActivityEvent.Kind = .running,
        signal: CompanionSignalKind? = nil,
        timestamp: Date? = nil,
        sourceID: String? = "paperclip",
        progress: CompanionReportedProgress? = nil
    ) -> ActivityEvent {
        ActivityEvent(
            id: name, kind: kind, title: name, timestamp: timestamp ?? now,
            signal: signal, sourceID: sourceID, entityID: "entity-" + name,
            progress: progress
        )
    }

    private func snapshot(
        current: ActivityEvent? = nil,
        recent: [ActivityEvent] = [],
        approvals: Int = 0,
        connection: ConnectionState = .connected
    ) -> ConnectorSnapshot {
        ConnectorSnapshot(
            connectorName: "Paperclip",
            connectionState: connection,
            currentActivity: current,
            recentActivity: recent,
            pendingApprovals: (0..<approvals).map {
                ApprovalRequest(id: "a\($0)", title: "Approval", requestedAt: now)
            }
        )
    }

    func testCanonicalProgressOnlyAcceptsRealBoundedCounts() {
        XCTAssertEqual(CompanionReportedProgress(current: 0, total: 3)?.current, 0)
        XCTAssertEqual(CompanionReportedProgress(current: 3, total: 3)?.total, 3)
        XCTAssertNil(CompanionReportedProgress(current: -1, total: 3))
        XCTAssertNil(CompanionReportedProgress(current: 4, total: 3))
        XCTAssertNil(CompanionReportedProgress(current: 1, total: 0))
    }

    func testPriorityFollowsFrozenSourceFirstSafetyOrder() {
        let candidates: [(CompanionSignalKind, String)] = [
            (.working, "ordinary"), (.success, "complete"),
            (.agentFailure, "failure"), (.infrastructureAlert, "infra"),
            (.ownerApproval, "owner"), (.securityAlert, "security"),
            (.budgetWarning, "budget"), (.testing, "testing")
        ]
        let feed = candidates.map { event($0.1, signal: $0.0) }
        let ordered = CompanionLiveActivityResolver.signals(
            for: snapshot(recent: feed), isLive: true, now: now
        )
        XCTAssertEqual(ordered.map(\.kind), [
            .securityAlert, .ownerApproval, .infrastructureAlert, .agentFailure,
            .budgetWarning, .testing, .working, .success
        ])
        XCTAssertEqual(ordered[0].schemaVersion, 1)
        XCTAssertEqual(ordered[0].sourceID, "paperclip")
        XCTAssertEqual(ordered[0].entityID, "entity-security")
    }

    func testPendingApprovalOutranksNonSecurityEvents() {
        let sample = snapshot(current: event("work", signal: .testing), approvals: 1)
        let first = CompanionLiveActivityResolver.primary(
            for: sample, isLive: true, now: now
        )
        XCTAssertEqual(first?.kind, .ownerApproval)
        XCTAssertEqual(first?.id, "approval:a0")
        XCTAssertEqual(CharacterStateMachine.mood(for: sample, now: now), .waitingForApproval)
    }

    func testExplicitSecurityOutranksApprovalButConnectionFailureRemainsVisible() {
        let urgent = snapshot(current: event("incident", signal: .securityAlert), approvals: 1)
        XCTAssertEqual(CharacterStateMachine.mood(for: urgent, now: now), .securityAlert)
        let offline = snapshot(
            current: event("incident", signal: .securityAlert), approvals: 1,
            connection: .disconnected
        )
        XCTAssertTrue(CompanionLiveActivityResolver.signals(
            for: offline, isLive: true, now: now
        ).isEmpty)
        XCTAssertEqual(CharacterStateMachine.mood(for: offline, now: now), .offline)
    }

    func testStaleAndOfflineStatesNeverClaimLiveWork() {
        let sample = snapshot(current: event("working", signal: .coding), approvals: 1)
        XCTAssertTrue(CompanionLiveActivityResolver.signals(
            for: sample, isLive: false, now: now
        ).isEmpty)
        XCTAssertTrue(CompanionLiveActivityResolver.signals(
            for: snapshot(connection: .error), isLive: true, now: now
        ).isEmpty)
    }

    func testTerminalCompletionAndTaskFailureDoNotReplayIndefinitely() {
        let older = now.addingTimeInterval(-120)
        let recent = now.addingTimeInterval(-30)
        let sample = snapshot(recent: [
            event("old-success", kind: .completed, signal: .success, timestamp: older),
            event("old-failure", kind: .failed, signal: .failure, timestamp: older),
            event("fresh-success", kind: .completed, signal: .success, timestamp: recent),
            event("active-error", kind: .failed, signal: .agentFailure, timestamp: older)
        ])
        let labels = CompanionLiveActivityResolver.signals(
            for: sample, isLive: true, now: now
        ).map(\.title)
        XCTAssertEqual(labels, ["active-error", "fresh-success"])
    }

    func testUnstructuredTitleNeverTurnsIntoSecurityOrTestClaims() {
        let sample = snapshot(current: event(
            "security breach tests 300/300 passed", kind: .running, signal: nil
        ))
        XCTAssertTrue(CompanionLiveActivityResolver.signals(
            for: sample, isLive: true, now: now
        ).isEmpty)
        XCTAssertEqual(CharacterStateMachine.mood(for: sample, now: now), .working)
    }

    func testDeduplicatesCurrentAndHistoryBySourceIdentity() {
        let duplicate = event("one", signal: .thinking)
        let sample = snapshot(current: duplicate, recent: [duplicate])
        let result = CompanionLiveActivityResolver.signals(
            for: sample, isLive: true, now: now
        )
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].id, "paperclip:one")
    }

    func testExtendedMoodsOnlyFollowExplicitSignals() {
        for kind in [
            CompanionSignalKind.thinking, .coding, .testing, .reviewing,
            .success, .budgetWarning, .infrastructureAlert, .securityAlert
        ] {
            let sample = snapshot(current: event(kind.rawValue, signal: kind))
            XCTAssertEqual(
                CharacterStateMachine.mood(for: sample, now: now),
                kind.characterMood, kind.rawValue
            )
        }
    }

    func testExpiredBackendTaskFailureDoesNotLeaveCharacterStuckInError() {
        let sample = snapshot(current: event(
            "old", kind: .failed, signal: .failure,
            timestamp: now.addingTimeInterval(-180)
        ))
        XCTAssertNil(CompanionLiveActivityResolver.primary(
            for: sample, isLive: true, now: now
        ))
        XCTAssertEqual(CharacterStateMachine.mood(for: sample, now: now), .idle)
        // A current, explicit agent-error state remains visible by design.
        let agent = snapshot(current: event(
            "failed-agent", kind: .failed, signal: .agentFailure,
            timestamp: now.addingTimeInterval(-180)
        ))
        XCTAssertEqual(CharacterStateMachine.mood(for: agent, now: now), .error)
    }

    func testTerminalFutureEventIsNotTreatedAsSuccess() {
        let sample = snapshot(
            current: event("future", kind: .completed, signal: .success,
                           timestamp: now.addingTimeInterval(180))
        )
        XCTAssertNil(CompanionLiveActivityResolver.primary(
            for: sample, isLive: true, now: now
        ))
    }
}
