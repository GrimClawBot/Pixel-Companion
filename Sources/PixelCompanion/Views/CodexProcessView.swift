import SwiftUI

/// Untrusted macOS process metadata is not session telemetry.
struct CodexProcessView: View {
    @ObservedObject var monitor: CodexProcessMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                SectionTitle(text: "Codex on this Mac")
                Spacer(minLength: 0)
                Text("Local only")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            switch monitor.presence {
            case .off:
                Text("Codex process detection is off")
                    .foregroundStyle(.secondary)
            case .unavailable:
                Label("Process information unavailable", systemImage: "exclamationmark.circle")
                    .foregroundStyle(.secondary)
            case .absent:
                Label("No Codex-named process detected", systemImage: "circle")
                    .foregroundStyle(.secondary)
            case let .detected(count):
                Label("Codex-named process detected", systemImage: "checkmark.circle")
                Text("\(count) local process\(count == 1 ? "" : "es") · Session activity unknown")
                    .foregroundStyle(.secondary)
            }
            Text("Process presence is not proof of an active chat or running task.")
                .foregroundStyle(.tertiary)
        }
        .font(.caption)
        .companionCard()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("companion.agents.codex-process")
    }
}
