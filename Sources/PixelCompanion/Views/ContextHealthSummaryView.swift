import PixelCompanionCore
import SwiftUI

/// Honest, per-agent context guidance; never submits a chat or changes a session.
struct ContextHealthSummaryView: View {
    let reportedUsed: Int?
    let reportedWindow: Int?
    let evidenceID: String
    @State private var acknowledgedEvidenceKey: String?

    init(reportedUsed: Int?, reportedWindow: Int?, evidenceID: String = "") {
        self.reportedUsed = reportedUsed
        self.reportedWindow = reportedWindow
        self.evidenceID = evidenceID
    }

    private var health: ContextHealth {
        ContextHealth(
            reportedUsed: reportedUsed,
            reportedWindow: reportedWindow,
            confidence: .providerReported
        )
    }

    private var activeEvidenceKey: String? {
        ContextGuidanceAcknowledgement.evidenceKey(health: health, sourceID: evidenceID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
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
                    ForEach(health.reasons, id: \.self) { reason in
                        Text(reason)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if let nextStep = health.nextStep {
                    if let key = activeEvidenceKey, acknowledgedEvidenceKey == key {
                        Text("Continuing for now. Recheck when the reported context changes.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(nextStep)
                            .font(.caption2)
                            .fixedSize(horizontal: false, vertical: true)
                        if let key = activeEvidenceKey {
                            Button("Keep working for now") {
                                acknowledgedEvidenceKey = key
                            }
                            .buttonStyle(.borderless)
                            .controlSize(.small)
                            .accessibilityIdentifier("companion.context.keep-working")
                        }
                    }
                }
                if health.recommendation >= .freshSessionRecommended {
                    Text("Guidance only · This read-only connector cannot create a new chat or handoff.")
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
        // Keep the local acknowledgement button individually accessible.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("companion.context.health")
    }
}

/// Acknowledgements are ephemeral to a single agent/run and the exact observed metric.
/// Moving to another agent or receiving a new measurement restores the suggestion.
enum ContextGuidanceAcknowledgement {
    static func evidenceKey(health: ContextHealth, sourceID: String) -> String? {
        guard health.recommendation >= .freshSessionRecommended,
              let used = health.usedTokens, let window = health.windowTokens else {
            return nil
        }
        return "\(sourceID)|\(used)|\(window)|\(health.recommendation.rawValue)"
    }
}
