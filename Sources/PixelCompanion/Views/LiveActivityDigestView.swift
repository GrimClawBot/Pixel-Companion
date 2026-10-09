import PixelCompanionCore
import SwiftUI

/// One priority signal in the glance UI, with bounded secondary signals in the
/// expanded view. Nothing here creates approvals or invents progress.
struct LiveActivityDigestView: View {
    let snapshot: ConnectorSnapshot
    let isLive: Bool

    private var signals: [CompanionLiveSignal] {
        CompanionLiveActivityResolver.signals(for: snapshot, isLive: isLive)
    }

    var body: some View {
        if let primary = signals.first {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    SectionTitle(text: "Live activity")
                    Spacer(minLength: 0)
                    Text("Verified source")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                signalRow(primary)
                if signals.count > 1 {
                    Text("\(signals.count - 1) other reported signals")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityIdentifier("companion.live-activities")
        }
    }

    private func signalRow(_ signal: CompanionLiveSignal) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: signal.kind.characterMood.symbolName)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(signal.kind.displayName)
                    .font(.caption.weight(.semibold))
                Text(signal.title)
                    .font(.caption2)
                    .lineLimit(2)
                    .foregroundStyle(.secondary)
                if let progress = signal.progress {
                    Text("\(progress.current) / \(progress.total) reported")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .companionCard()
        .accessibilityElement(children: .combine)
    }
}
