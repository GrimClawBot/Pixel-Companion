import PixelCompanionCore
import SwiftUI

/// A derived UI diagnostic, not a server-side incident or a macOS notification.
struct OperationalDiagnostic: Identifiable, Equatable {
    enum Kind: String {
        case failedRun
        case monthlyBudget
        case contextWindow
    }

    enum Severity {
        case critical
        case warning

        var priority: Int { self == .critical ? 2 : 1 }
    }

    let agentID: String
    let agentName: String
    let kind: Kind
    let severity: Severity
    let title: String
    let detail: String

    var id: String { agentID + ":" + kind.rawValue }
}

/// Only a fresh snapshot may produce diagnostics; old issues and cumulative
/// tokens cannot be used to invent current failures or context occupancy.
enum OperationalAttentionPresentation {
    static let previewLimit = 4

    static func diagnostics(
        _ sessions: [AgentSessionSnapshot], isLive: Bool
    ) -> [OperationalDiagnostic] {
        guard isLive else { return [] }

        var rows: [OperationalDiagnostic] = []
        var seen = Set<String>()
        for session in sessions {
            let failures = warnings(for: session)
            for item in failures where seen.insert(item.id).inserted {
                rows.append(item)
            }
        }
        // High severity first; preserve incoming connector order within each severity.
        return rows.enumerated().sorted { lhs, rhs in
            let left = lhs.element.severity.priority
            let right = rhs.element.severity.priority
            return left == right ? lhs.offset < rhs.offset : left > right
        }.map(\.element)
    }

    static func preview(_ rows: [OperationalDiagnostic]) -> [OperationalDiagnostic] {
        Array(rows.prefix(previewLimit))
    }

    private static func warnings(for session: AgentSessionSnapshot) -> [OperationalDiagnostic] {
        var results: [OperationalDiagnostic] = []

        if session.runState == .failed {
            results.append(OperationalDiagnostic(
                agentID: session.agentID,
                agentName: session.agentName,
                kind: .failedRun,
                severity: .critical,
                title: "Latest run failed",
                detail: "Cause not reported here · Inspect run details"
            ))
        }

        if let fraction = AgentUsagePresentation.monthlyBudgetFraction(session),
           fraction >= 0.8 {
            let critical = fraction >= 1
            results.append(OperationalDiagnostic(
                agentID: session.agentID,
                agentName: session.agentName,
                kind: .monthlyBudget,
                severity: critical ? .critical : .warning,
                title: critical ? "Monthly budget reached" : "Monthly budget nearing limit",
                detail: critical
                    ? "Reported monthly spend meets or exceeds budget"
                    : "Reported monthly spend is at least \(fraction >= 0.9 ? 90 : 80)% of budget"
            ))
        }

        if let fraction = AgentUsagePresentation.contextFraction(session),
           fraction >= 0.8 {
            let critical = fraction >= 0.9
            results.append(OperationalDiagnostic(
                agentID: session.agentID,
                agentName: session.agentName,
                kind: .contextWindow,
                severity: critical ? .critical : .warning,
                title: critical ? "Context nearly full" : "Context filling up",
                detail: "Reported context usage · \(Int(fraction * 100))%"
            ))
        }
        return results
    }
}

/// In-panel digest only: no notification submission, mutation or persistence.
struct OperationalAttentionView: View {
    let sessions: [AgentSessionSnapshot]
    let isLive: Bool
    let onSelectAgent: (String) -> Void

    private var diagnostics: [OperationalDiagnostic] {
        OperationalAttentionPresentation.diagnostics(sessions, isLive: isLive)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                SectionTitle(text: "Attention needed")
                Spacer(minLength: 0)
                if isLive {
                    Text("\(diagnostics.count) reported")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            if !isLive {
                Placeholder(text: "Attention signals unavailable until the feed is fresh.")
            } else if diagnostics.isEmpty {
                Text("No latest-run failure or reported usage threshold reached")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(OperationalAttentionPresentation.preview(diagnostics)) { diagnostic in
                    Button {
                        onSelectAgent(diagnostic.agentID)
                    } label: {
                        diagnosticRow(diagnostic)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        "Inspect \(diagnostic.agentName): \(diagnostic.title). \(diagnostic.detail)"
                    )
                    .accessibilityIdentifier("companion.attention." + diagnostic.id)
                }
                if diagnostics.count > OperationalAttentionPresentation.previewLimit {
                    Text(
                        "Showing \(OperationalAttentionPresentation.previewLimit) of " +
                        "\(diagnostics.count) reported signals"
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityIdentifier("companion.operations.attention")
    }

    private func diagnosticRow(_ diagnostic: OperationalDiagnostic) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: diagnostic.severity == .critical
                  ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(diagnostic.severity == .critical ? .red : .orange)
                .frame(width: 16)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(diagnostic.agentName)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Text(diagnostic.title)
                    .font(.caption.weight(.medium))
                Text(diagnostic.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .companionCard()
        .contentShape(RoundedRectangle(cornerRadius: 12))
    }
}
