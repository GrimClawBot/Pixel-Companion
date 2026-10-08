import Foundation
import PixelCompanionCore

/// Local QA-only event fixture. Uses the production detector, never the Paperclip API.
enum CompanionQAScenario: CaseIterable {
    case newApproval
    case runCompleted
    case runFailed

    var label: String {
        switch self {
        case .newApproval: return "approval"
        case .runCompleted: return "run completed"
        case .runFailed: return "run failed"
        }
    }

    func notices() -> [CompanionNotice] {
        var detector = CompanionNoticeDetector()
        let initial = AgentSessionSnapshot(
            id: "qa-agent", agentID: "qa-agent", agentName: "QA fixture",
            agentStatus: "running", runID: "qa-run", runState: .running
        )
        let baseline = ConnectorSnapshot(
            connectorName: "QA fixture", connectionState: .connected, agentSessions: [initial]
        )
        _ = detector.observe(baseline)
        switch self {
        case .newApproval:
            let changed = ConnectorSnapshot(
                connectorName: "QA fixture", connectionState: .connected,
                pendingApprovals: [ApprovalRequest(
                    id: "qa-approval", title: "QA fixture", requestedAt: .distantPast
                )],
                agentSessions: [initial]
            )
            return detector.observe(changed)
        case .runCompleted, .runFailed:
            let runState: AgentSessionSnapshot.RunState = self == .runCompleted ? .completed : .failed
            let ended = AgentSessionSnapshot(
                id: "qa-agent", agentID: "qa-agent", agentName: "QA fixture",
                agentStatus: runState.rawValue, runID: "qa-run", runState: runState
            )
            let changed = ConnectorSnapshot(
                connectorName: "QA fixture", connectionState: .connected, agentSessions: [ended]
            )
            return detector.observe(changed)
        }
    }
}
