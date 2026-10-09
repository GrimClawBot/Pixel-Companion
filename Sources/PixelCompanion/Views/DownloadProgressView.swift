import SwiftUI

/// Shows reported download progress only, not arbitrary downloads on the Mac.
struct DownloadProgressView: View {
    @ObservedObject var monitor: DownloadProgressMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionTitle(text: "Downloads")
                Spacer()
                Image(systemName: "arrow.down.circle")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            switch monitor.state {
            case .noSource:
                Text("No download integration connected")
                    .foregroundStyle(.secondary)
            case .idle:
                Text("No active download reported")
                    .foregroundStyle(.secondary)
            case let .active(percent):
                if let percent {
                    ProgressView(value: Double(percent), total: 100) {
                        Text("Download in progress")
                    } currentValueLabel: {
                        Text("\(percent)%").monospacedDigit()
                    }
                    .accessibilityLabel("Reported download progress")
                } else {
                    ProgressView {
                        Text("Download in progress · size not reported")
                    }
                }
            case .finished:
                Label("Download completed", systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
        .companionCard()
        .accessibilityIdentifier("companion.utility.download-progress")
    }
}
