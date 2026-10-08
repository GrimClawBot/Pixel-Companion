import SwiftUI

/// A completion timestamp is not permission, session state, or success.
struct CodexTurnView: View {
    @ObservedObject var monitor: CodexTurnMonitor
    @State private var referenceTime = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionTitle(text: "Codex turn events")
                Spacer()
                Text("Read-only")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            switch monitor.status {
            case .off:
                Text("Codex turn events are off")
                    .foregroundStyle(.secondary)
            case .unconnected:
                Text("Choose a Codex hook event file in Connections")
                    .foregroundStyle(.secondary)
            case .unavailable:
                Label("No valid turn-completion event available", systemImage: "clock")
                    .foregroundStyle(.secondary)
            case let .observed(date):
                Label(
                    CodexTurnParser.isRecent(date, at: referenceTime)
                        ? "Turn completion reported" : "Previous turn completion (not live)",
                    systemImage: "checkmark.circle"
                )
                Text(date, style: .relative)
                    .foregroundStyle(.secondary)
            }
            Text("A completed turn does not confirm success or current activity.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .font(.caption)
        .companionCard()
        .onAppear { referenceTime = Date() }
        .onReceive(monitor.$status) { _ in referenceTime = Date() }
        .accessibilityIdentifier("companion.agents.codex-turn")
    }
}
