import SwiftUI

/// Uses existing monitor publishers only. No extra polling, file selection,
/// permissions, credentials, hook installation, process scans or connector calls.
struct LocalConnectionHealthSettings: View {
    @ObservedObject var process: CodexProcessMonitor
    @ObservedObject var codex: CodexTurnMonitor
    @ObservedObject var claude: ClaudeHookMonitor
    @ObservedObject var feed: LocalAgentFeedMonitor

    var body: some View {
        Section {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                VStack(alignment: .leading, spacing: 12) {
                    let items = LocalConnectionHealth.snapshot(
                        process: process.presence, codex: codex.status,
                        claude: claude.status, feed: feed.status, now: context.date
                    )
                    ForEach(items) { item in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: item.kind.symbol)
                                .frame(width: 17)
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text(item.title)
                                        .font(.subheadline.weight(.medium))
                                    Spacer(minLength: 0)
                                    Text(item.kind.title)
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(.secondary)
                                }
                                Text(item.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(item.accessibilitySummary)
                        .accessibilityIdentifier("companion.health." + item.id)
                    }
                }
            }
            Button("Refresh enabled sources") {
                process.refresh()
                codex.refresh()
                claude.refresh()
                feed.refresh()
            }
            .controlSize(.small)
            .accessibilityIdentifier("companion.health.refresh")
        } header: {
            Text("Local agent connection health")
        } footer: {
            Text("Local read-only signals. A process or recent hook event " +
                 "doesn't prove a session is active or that a task succeeded. " +
                 "Status files and hook integrations require your separate setup.")
        }
    }
}
