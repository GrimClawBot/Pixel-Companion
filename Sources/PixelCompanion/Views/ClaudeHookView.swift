import SwiftUI

/// Displays only a scrubbed Claude Code milestone, never a chat transcript.
struct ClaudeHookView: View {
    @ObservedObject var monitor: ClaudeHookMonitor
    @State private var referenceTime = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionTitle(text: "Claude Code events")
                Spacer(minLength: 0)
                Text("Read-only")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            switch monitor.status {
            case .off:
                Text("Claude Code events are off")
                    .foregroundStyle(.secondary)
            case .unconnected:
                Text("Choose an event folder in Settings → Connections")
                    .foregroundStyle(.secondary)
            case .unavailable:
                Label("No valid Claude Code event available", systemImage: "clock")
                    .foregroundStyle(.secondary)
            case let .observed(event, timestamp):
                Label(
                    event.label + (ClaudeHookParser.isRecent(timestamp, at: referenceTime)
                        ? "" : " (previous event, not live)"),
                    systemImage: "clock.arrow.circlepath"
                )
                Text(timestamp, style: .relative)
                    .foregroundStyle(.secondary)
            }
            Text("Events do not prove current activity, task success, or permission approval.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .font(.caption)
        .companionCard()
        .onAppear { referenceTime = Date() }
        .onReceive(monitor.$status) { _ in referenceTime = Date() }
        .accessibilityIdentifier("companion.agents.claude-hook")
    }
}
