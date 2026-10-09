import SwiftUI

/// No volume controls: the user changes sound using ordinary macOS controls.
struct OutputVolumeView: View {
    @ObservedObject var monitor: OutputVolumeMonitor

    private var snapshot: OutputVolumeSnapshot { monitor.snapshot }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                SectionTitle(text: "Output volume")
                Spacer(minLength: 0)
                Text("Local only")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if let percentage = snapshot.percentage {
                HStack(spacing: 9) {
                    Image(systemName: snapshot.isMuted == true
                          ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.title3)
                        .accessibilityHidden(true)
                    Text("\(percentage)%")
                        .font(.title2.monospacedDigit().weight(.semibold))
                    Spacer(minLength: 0)
                }
                if let isMuted = snapshot.isMuted {
                    Text(isMuted ? "Muted" : "Not muted")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Mute state unavailable")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Output volume unavailable for this device")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .companionCard()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("companion.utility.output-volume")
    }
}
