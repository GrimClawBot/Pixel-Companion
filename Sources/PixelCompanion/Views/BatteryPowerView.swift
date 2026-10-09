import SwiftUI

/// Standalone, permission-free power information with no historical or
/// unreported values inferred from a missing internal battery.
struct BatteryPowerView: View {
    @ObservedObject var monitor: BatteryPowerMonitor

    private var snapshot: BatteryPowerSnapshot { monitor.snapshot }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                SectionTitle(text: "Battery & Power")
                Spacer(minLength: 0)
                Text("Local only")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if let percentage = snapshot.percentage {
                HStack(spacing: 9) {
                    Image(systemName: snapshot.isCharging == true
                          ? "battery.100percent.bolt" : "battery.100percent")
                        .font(.title3)
                        .accessibilityHidden(true)
                    Text("\(percentage)%")
                        .font(.title2.monospacedDigit().weight(.semibold))
                    Spacer(minLength: 0)
                }
                Text(snapshot.powerLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Battery percentage unavailable on this Mac")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(snapshot.isLowPowerMode ? "Low Power Mode: On" : "Low Power Mode: Off")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .companionCard()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("companion.utility.battery")
    }
}
