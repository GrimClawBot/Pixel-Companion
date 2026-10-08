import SwiftUI

/// Optional local utility, subordinate to the primary agent status cards.
struct DisplayBrightnessView: View {
    @ObservedObject var monitor: DisplayBrightnessMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                SectionTitle(text: "Display brightness")
                Spacer(minLength: 0)
                Text("Local only")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if let percentage = monitor.snapshot.percentage {
                HStack(spacing: 9) {
                    Image(systemName: "sun.max")
                        .font(.title3)
                        .accessibilityHidden(true)
                    Text("\(percentage)%")
                        .font(.title2.monospacedDigit().weight(.semibold))
                    Spacer(minLength: 0)
                }
                Text("Reported display brightness")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Brightness unavailable for this display setup")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .companionCard()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("companion.utility.display-brightness")
    }
}
