import PixelCompanionCore
import SwiftUI

/// Honest context guidance, never a fake session or an action that submits a chat.
struct ContextHealthSummaryView: View {
    let reportedUsed: Int?
    let reportedWindow: Int?

    private var health: ContextHealth {
        ContextHealth(
            reportedUsed: reportedUsed,
            reportedWindow: reportedWindow,
            confidence: .providerReported
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(health.recommendation.label)
                    .font(.caption.weight(.medium))
                Spacer(minLength: 0)
                Text(health.confidence.label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if let fraction = health.fraction {
                Text("Context · \(Int(fraction * 100))% of reported window")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                if health.recommendation >= .freshSessionRecommended {
                    Text("No new-chat or handoff action is available from this read-only connector.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text("Context-window figures not supplied by the runtime.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("companion.context.health")
    }
}
