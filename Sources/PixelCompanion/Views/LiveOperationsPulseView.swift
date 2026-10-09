import PixelCompanionCore
import SwiftUI

/// Group by reported *latest* run state; do not infer ownership of approvals.
enum OperationsPulseCategory: String, CaseIterable, Identifiable {
    case running
    case queued
    case failed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .running: return "Running"
        case .queued: return "Queued"
        case .failed: return "Failed latest run"
        }
    }

    var shortTitle: String {
        switch self {
        case .running: return "Running"
        case .queued: return "Queued"
        case .failed: return "Failed"
        }
    }

    func contains(_ session: AgentSessionSnapshot) -> Bool {
        switch self {
        case .running: return session.runState == .running
        case .queued: return session.runState == .queued
        case .failed: return session.runState == .failed
        }
    }
}

/// Pure derivation from live snapshots only. Pending approvals are company-wide,
/// with no false linkage to agents or task ownership.
struct OperationsPulse {
    let sessions: [AgentSessionSnapshot]
    let pendingApprovalCount: Int
    let isLive: Bool

    func count(_ category: OperationsPulseCategory) -> Int? {
        guard isLive else { return nil }
        return sessions.filter(category.contains).count
    }

    func preview(_ category: OperationsPulseCategory) -> [AgentSessionSnapshot] {
        guard isLive else { return [] }
        return Array(sessions.filter(category.contains).prefix(2))
    }

    var hasReportedWork: Bool {
        OperationsPulseCategory.allCases.contains { (count($0) ?? 0) > 0 }
    }

    var companyWideApprovals: Int? {
        isLive ? max(0, pendingApprovalCount) : nil
    }
}

/// Compact operations overview; every agent shortcut opens the existing inspector.
struct LiveOperationsPulseView: View {
    let sessions: [AgentSessionSnapshot]
    let pendingApprovalCount: Int
    let isLive: Bool
    let onSelectAgent: (String) -> Void
    let onShowApprovals: () -> Void

    private var pulse: OperationsPulse {
        OperationsPulse(
            sessions: sessions, pendingApprovalCount: pendingApprovalCount, isLive: isLive
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                SectionTitle(text: "Live operations")
                Spacer(minLength: 0)
                Label("Read-only", systemImage: "eye")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if !isLive {
                Placeholder(text: "Live operations unavailable until the feed is fresh.")
            } else {
                HStack(spacing: 7) {
                    ForEach(OperationsPulseCategory.allCases) { category in
                        counter(category)
                    }
                }
                if !pulse.hasReportedWork {
                    Text("No running, queued or failed latest runs reported")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(OperationsPulseCategory.allCases) { category in
                    if pulse.count(category) ?? 0 > 0 {
                        SectionTitle(text: category.title)
                        ForEach(pulse.preview(category)) { session in
                            agentShortcut(session)
                        }
                    }
                }
                if let approvals = pulse.companyWideApprovals, approvals > 0 {
                    Button(action: onShowApprovals) {
                        Label(
                            "\(approvals) company-wide pending approvals · View Activity",
                            systemImage: "hand.raised"
                        )
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.orange)
                    .accessibilityIdentifier("companion.operations.approvals")
                }
            }
        }
        .accessibilityIdentifier("companion.operations.pulse")
    }

    private func counter(_ category: OperationsPulseCategory) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(pulse.count(category) ?? 0)")
                .font(.callout.weight(.semibold).monospacedDigit())
            Text(category.shortTitle.uppercased())
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .companionCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(pulse.count(category) ?? 0) agents: \(category.shortTitle.lowercased())"
        )
    }

    private func agentShortcut(_ session: AgentSessionSnapshot) -> some View {
        Button {
            onSelectAgent(session.agentID)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: AgentSessionPresentation.symbol(session.runState))
                    .foregroundStyle(AgentSessionPresentation.tint(session.runState))
                    .frame(width: 16)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.agentName)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                    Text(session.taskTitle ?? "Task not reported")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .contentShape(RoundedRectangle(cornerRadius: 10))
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Inspect " + session.agentName)
        .accessibilityIdentifier("companion.operations.agent." + session.agentID)
    }
}
