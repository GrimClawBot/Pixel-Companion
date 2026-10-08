import SwiftUI

/// A completion timestamp is not permission, session state, or success.
struct CodexTurnView: View {
    @ObservedObject var monitor: CodexTurnMonitor
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionTitle(text: "Codex turn events")
                Spacer()
                Text("Read-only")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            TimelineView(.periodic(from: .now, by: 15)) { context in
                VStack(alignment: .leading, spacing: 4) {
                    switch monitor.status {
                    case .off:
                        Text("Codex turn events are off")
                            .foregroundStyle(.secondary)
                    case .unconnected:
                        Text("Choose a Codex hook event folder in Connections")
                            .foregroundStyle(.secondary)
                    case .unavailable:
                        Label("No valid turn-completion event available", systemImage: "clock")
                            .foregroundStyle(.secondary)
                    case let .observed(date):
                        Label(
                            LocalAgentEventPresentation.codexLabel(date, now: context.date),
                            systemImage: "checkmark.circle"
                        )
                        Text(date, style: .relative)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Text("A completed turn does not confirm success or current activity.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .font(.caption)
        .companionCard()
        .accessibilityIdentifier("companion.agents.codex-turn")
    }
}
