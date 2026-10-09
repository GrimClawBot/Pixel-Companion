import SwiftUI

/// No generic system-wide media access is claimed. Music.app metadata and
/// Automation consent are both explicitly scoped to the Apple Music provider.
struct MusicNowPlayingView: View {
    @ObservedObject var monitor: MusicNowPlayingMonitor
    let showDetails: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                SectionTitle(text: "Now Playing · Apple Music")
                Spacer(minLength: 0)
                Text("Read-only")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if let snapshot = monitor.snapshot {
                HStack(spacing: 8) {
                    Image(systemName: snapshot.playback == .playing
                          ? "music.note" : "pause.circle")
                        .accessibilityHidden(true)
                    Text(monitor.state.description)
                        .font(.caption.weight(.semibold))
                }
                Text(snapshot.displayedTitle(showTitles: showDetails))
                    .font(.callout.weight(.medium))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if showDetails {
                    if let artist = snapshot.artist {
                        Text(artist)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    if let album = snapshot.album {
                        Text(album)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            } else {
                Text(monitor.state.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if monitor.state != .playing && monitor.state != .paused &&
                monitor.state != .stopped && monitor.state != .connecting {
                Button("Connect to Apple Music…") {
                    monitor.connect()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityIdentifier("companion.music.connect")
            }
            Text("Apple Music app only · No playback commands")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .companionCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("companion.utility.music")
    }
}
