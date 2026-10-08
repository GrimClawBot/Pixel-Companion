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
            TimelineView(.periodic(from: .now, by: 30)) { context in
                let visible = attention.latest.filter {
                    LocalAgentEventPresentation.attentionIsVisible(
                        $0.timestamp, at: context.date
                    )
                }
                if visible.isEmpty {
                    Text("No local Codex or Claude Code completion signals in this session.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(visible) { event in
                            attentionRow(event, now: context.date)
                        }
                    }
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

    private func attentionRow(_ event: LocalAgentActivityEvent, now: Date) -> some View {
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
                Text(
                    LocalAgentEventPresentation.attentionTimingLabel(
                        event.timestamp, at: now
                    )
                )
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
            Text(event.timestamp, style: .relative)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}
