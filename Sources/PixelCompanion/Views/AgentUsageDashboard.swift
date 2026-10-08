import Foundation
import PixelCompanionCore
import SwiftUI

/// Strictly sourced usage. Never derive context occupancy from cumulative run tokens.
enum AgentUsagePresentation {
    static func runTokens(_ session: AgentSessionSnapshot) -> String {
        AgentSessionPresentation.tokenLabel(session).map { "This run · \($0)" }
            ?? "Run tokens not reported"
    }

    static func monthlySpend(_ session: AgentSessionSnapshot) -> String {
        guard let cents = session.monthlySpendCents, cents >= 0 else {
            return "Monthly spend not reported"
        }
        return "Spent this month · \(money(cents))"
    }

    static func monthlyBudget(_ session: AgentSessionSnapshot) -> String {
        guard let cents = session.monthlyBudgetCents else { return "Monthly budget not reported" }
        return cents > 0 ? "Monthly budget · \(money(cents))" : "No monthly budget set"
    }

    static func contextFraction(_ session: AgentSessionSnapshot) -> Double? {
        guard let used = session.contextUsedTokens,
              let window = session.contextWindowTokens,
              used >= 0, window > 0, used <= window else { return nil }
        return Double(used) / Double(window)
    }

    static func contextLabel(_ session: AgentSessionSnapshot) -> String {
        guard let fraction = contextFraction(session),
              let used = session.contextUsedTokens,
              let window = session.contextWindowTokens else {
            return "Context usage unavailable (window not reported)"
        }
        return "Context · \(used.formatted()) / \(window.formatted()) tokens · \(Int(fraction * 100))%"
    }

    static func contextWarning(_ session: AgentSessionSnapshot) -> String? {
        guard let fraction = contextFraction(session) else { return nil }
        if fraction >= 0.9 { return "Context nearly full — consider starting a new session" }
        if fraction >= 0.8 { return "Context above 80% — plan a fresh session" }
        return nil
    }

    private static func money(_ cents: Int) -> String {
        (Double(cents) / 100).formatted(
            .currency(code: "USD").locale(Locale(identifier: "en_US"))
        )
    }
}

/// Read-only usage for each reported agent. Monthly costs are not per-run estimates.
struct AgentUsageCard: View {
    let session: AgentSessionSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(session.agentName).font(.callout.weight(.semibold))
                Spacer(minLength: 0)
                Text(AgentSessionPresentation.stateLabel(session))
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Text(AgentSessionPresentation.runtimeLabel(session) ?? "Model/provider not reported")
                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            Text(AgentUsagePresentation.runTokens(session))
                .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            Text(AgentUsagePresentation.monthlySpend(session))
                .font(.caption2.monospacedDigit())
            Text(AgentUsagePresentation.monthlyBudget(session))
                .font(.caption2).foregroundStyle(.secondary)
            Text(AgentUsagePresentation.contextLabel(session))
                .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            if let fraction = AgentUsagePresentation.contextFraction(session) {
                ProgressView(value: fraction)
                    .progressViewStyle(.linear)
                    .tint(fraction >= 0.9 ? .red : (fraction >= 0.8 ? .orange : .green))
                    .accessibilityLabel("Context utilization")
                    .accessibilityValue("\(Int(fraction * 100)) percent")
            }
            if let warning = AgentUsagePresentation.contextWarning(session) {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2.weight(.medium)).foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }
}
