import Foundation
import PixelCompanionCore

/// Remember observed active runs across temporary unknown/missing telemetry; never infer live runs.
struct CompanionNoticeDetector {
    private struct TrackedRun {
        var observedActive: Bool
        var notified: Bool
        var lastPoll: Int
    }

    private var connectorName: String?
    private var seenApprovalIDs: Set<String> = []
    private var tracked: [String: TrackedRun] = [:]
    private var poll = 0

    mutating func reset() {
        connectorName = nil
        seenApprovalIDs.removeAll()
        tracked.removeAll()
        poll = 0
    }

    mutating func observe(_ snapshot: ConnectorSnapshot) -> [CompanionNotice] {
        guard snapshot.connectionState == .connected else {
            reset()
            return []
        }
        if connectorName != snapshot.connectorName {
            reset()
            connectorName = snapshot.connectorName
            seenApprovalIDs.formUnion(snapshot.pendingApprovals.map(\.id))
            _ = scanRuns(snapshot.agentSessions, notify: false)
            return []
        }

        let currentIDs = Set(snapshot.pendingApprovals.map(\.id))
        let newApprovals = currentIDs.subtracting(seenApprovalIDs).count
        seenApprovalIDs.formUnion(currentIDs)
        let endings = scanRuns(snapshot.agentSessions, notify: true)
        var notices: [CompanionNotice] = []
        if newApprovals > 0 { notices.append(.approvals(newApprovals)) }
        if endings.completed > 0 { notices.append(.completedRuns(endings.completed)) }
        if endings.failed > 0 { notices.append(.failedRuns(endings.failed)) }
        return notices
    }

    private static func countObservedEnding(
        state: inout TrackedRun,
        runState: AgentSessionSnapshot.RunState,
        notify: Bool,
        completed: inout Int,
        failed: inout Int
    ) {
        guard notify, state.observedActive, !state.notified else { return }
        switch runState {
        case .completed:
            completed += 1
            state.notified = true
        case .failed:
            failed += 1
            state.notified = true
        default: break
        }
    }

    private mutating func scanRuns(
        _ sessions: [AgentSessionSnapshot],
        notify: Bool
    ) -> (completed: Int, failed: Int) {
        poll += 1
        var completed = 0
        var failed = 0
        for session in sessions {
            if let runID = session.runID {
                let key = session.agentID + ":" + runID
                var state = tracked[key] ?? TrackedRun(
                    observedActive: false, notified: false, lastPoll: poll
                )
                if session.isActive { state.observedActive = true }
                Self.countObservedEnding(
                    state: &state, runState: session.runState, notify: notify,
                    completed: &completed, failed: &failed
                )
                state.lastPoll = poll
                tracked[key] = state
            }

            // The most recent selected run may already be a newer active run.
            // An earlier observed-active run can finish between polls, with
            // its terminal state now reported ONLY in the bounded run history.
            // Never notify about historical runs we did not observe active.
            for run in session.recentRuns where run.id != session.runID {
                let historicalKey = session.agentID + ":" + run.id
                guard var historical = tracked[historicalKey] else { continue }
                Self.countObservedEnding(
                    state: &historical, runState: run.state, notify: notify,
                    completed: &completed, failed: &failed
                )
                historical.lastPoll = poll
                tracked[historicalKey] = historical
            }
        }
        // A run can briefly vanish from telemetry; bound retained evidence by polls and count.
        tracked = tracked.filter { poll - $0.value.lastPoll <= 12 }
        if tracked.count > 512 {
            let overflow = tracked.count - 512
            let oldest = tracked.sorted { $0.value.lastPoll < $1.value.lastPoll }.prefix(overflow)
            for item in oldest { tracked.removeValue(forKey: item.key) }
        }
        return (completed, failed)
    }
}
