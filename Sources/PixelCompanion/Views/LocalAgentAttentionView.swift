import SwiftUI

/// Read-only digest; the Activity tab owns the complete in-memory view.
struct LocalAgentAttentionView: View {
    @ObservedObject var attention: LocalAgentAttention
    let openActivity: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                SectionTitle(text: "Local AI attention")
                Spacer(minLength: 0)
                Text("Observed events")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if attention.latest.isEmpty {
                Text("No recent Codex or Claude Code completion signals.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(attention.latest) { event in
                    HStack(spacing: 8) {
                        Image(systemName: "bell.badge")
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(LocalAgentAlert.from(event)?.title ?? event.source.label)
                                .font(.caption.weight(.medium))
                            Text(LocalAgentAlert.from(event)?.detail ?? "Status not verified")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        Text(event.timestamp, style: .relative)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            Button("View local activity", action: openActivity)
                .controlSize(.small)
                .buttonStyle(.borderless)
                .accessibilityIdentifier("companion.attention.open-activity")
        }
        .companionCard()
        .accessibilityIdentifier("companion.overview.local-attention")
    }
}
