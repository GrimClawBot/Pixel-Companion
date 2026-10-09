import SwiftUI

/// Source-reported local JSON telemetry only. This panel does not scan
/// machines, ping servers, assert remote host trust or perform any actions.
/// The sole gate that lets source-reported metrics enter the rendered view.
/// Tests exercise the same state the SwiftUI rows consume at the 120s boundary.
struct LocalInfrastructureHostDisplay {
    let isFresh: Bool
    let visibleMetrics: LocalInfrastructureHost?

    init(host: LocalInfrastructureHost, now: Date) {
        isFresh = host.isFresh(at: now)
        visibleMetrics = isFresh ? host : nil
    }
}

struct LocalInfrastructureView: View {
    @ObservedObject var monitor: LocalInfrastructureMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                SectionTitle(text: "Infrastructure · local report")
                Spacer(minLength: 0)
                Label("Read-only", systemImage: "eye")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            TimelineView(.periodic(from: .now, by: 30)) { context in
                content(at: context.date)
            }
            Text("Host readings are supplied by your selected JSON file, " +
                 "not independently measured or verified by Pixel Companion.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityIdentifier("companion.infrastructure.local")
    }

    @ViewBuilder private func content(at now: Date) -> some View {
        switch monitor.status {
        case .disabled:
            Text("Local infrastructure reports disabled.")
                .foregroundStyle(.secondary)
        case .unconnected:
            Placeholder(text: "Select a trusted local infrastructure report in Settings → Connections.")
        case .unavailable:
            Placeholder(text: "Infrastructure report missing, invalid or unreadable. No live health verified.")
        case .empty:
            Placeholder(text: "The selected report contains no hosts.")
        case let .loaded(hosts):
            ForEach(hosts) { host in
                hostRow(host, now: now)
            }
        }
    }

    private func hostRow(_ host: LocalInfrastructureHost, now: Date) -> some View {
        let display = LocalInfrastructureHostDisplay(host: host, now: now)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: display.isFresh ? "server.rack" : "clock.badge.exclamationmark")
                    .foregroundStyle(display.isFresh ? .primary : .secondary)
                    .accessibilityHidden(true)
                Text(host.name)
                    .font(.callout.weight(.semibold))
                    .lineLimit(2)
                Spacer(minLength: 0)
                Text(display.isFresh ? "Recent report" : "Stale report")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            if let visible = display.visibleMetrics {
                metrics(visible)
            } else {
                Text("Metrics withheld because the source timestamp is not fresh.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text("Reported " + host.observedAt.formatted(date: .abbreviated, time: .shortened))
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("Host ID · " + host.id)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .companionCard()
        .accessibilityIdentifier("companion.infrastructure.host." + host.id)
    }

    @ViewBuilder private func metrics(_ host: LocalInfrastructureHost) -> some View {
        if let cpu = host.cpuPercent {
            LabeledContent("CPU · reported", value: String(format: "%.1f%%", cpu))
        }
        if let fraction = host.memoryFraction {
            LabeledContent("Memory · reported", value: String(format: "%.1f%% used", fraction * 100))
        }
        if let fraction = host.diskFraction {
            LabeledContent("Disk · reported", value: String(format: "%.1f%% used", fraction * 100))
        }
        if let temp = host.temperatureCelsius {
            LabeledContent("Temperature · reported", value: String(format: "%.1f °C", temp))
        }
        if let rate = host.receiveBytesPerSecond {
            LabeledContent("Network receive · reported", value: rateLabel(rate))
        }
        if let rate = host.transmitBytesPerSecond {
            LabeledContent("Network transmit · reported", value: rateLabel(rate))
        }
        if let deployment = host.deployment {
            LabeledContent("Deployment · " + deployment.name, value: deployment.state.rawValue)
        }
        if host.cpuPercent == nil && host.memoryFraction == nil &&
            host.diskFraction == nil && host.temperatureCelsius == nil &&
            host.receiveBytesPerSecond == nil && host.transmitBytesPerSecond == nil &&
            host.deployment == nil {
            Text("No host metrics supplied in this report.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func rateLabel(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) + "/s"
    }
}
