import SwiftUI

/// Local agent status stays separate from Paperclip's authoritative company
/// sessions. Never infers task progress, token usage, or agent approvals.
struct LocalAgentSessionsView: View {
    @ObservedObject var monitor: LocalAgentFeedMonitor
    @State private var referenceTime = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionTitle(text: "Local agents")
                Spacer()
                Text("Read-only")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            switch monitor.status {
            case .disabled:
                Text("Local agent feed is disabled")
                    .foregroundStyle(.secondary)
            case .unconnected:
                Text("Choose a status file in Settings → Connections")
                    .foregroundStyle(.secondary)
            case .unavailable:
                Label("Status file unavailable or invalid", systemImage: "exclamationmark.circle")
                    .foregroundStyle(.orange)
            case .empty:
                Text("No sessions reported by this source")
                    .foregroundStyle(.secondary)
            case let .loaded(sessions):
                ForEach(sessions) { session in
                    HStack(spacing: 8) {
                        Image(systemName: session.state == .running && session.isFresh(at: referenceTime)
                              ? "circle.fill" : "circle")
                            .font(.system(size: 7))
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(session.name)
                                .font(.subheadline.weight(.medium))
                                .lineLimit(1)
                            Text(session.source.label + " · " +
                                 (session.isFresh(at: referenceTime)
                                  ? session.state.rawValue.capitalized : "Stale status"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        Text(session.updatedAt, style: .relative)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .font(.caption)
        .companionCard()
        .onAppear { referenceTime = Date() }
        .onReceive(monitor.$status) { _ in referenceTime = Date() }
        .accessibilityIdentifier("companion.agents.local-feed")
    }
}
