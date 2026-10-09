import Foundation

/// Sanitized, ephemeral read-only metadata. No track IDs, artwork, playlists,
/// library data, user identifiers or playback history are retained.
struct MusicNowPlayingSnapshot: Equatable, Sendable {
    enum PlaybackState: String, Sendable {
        case playing
        case paused
        case stopped
    }

    let playback: PlaybackState
    let title: String?
    let artist: String?
    let album: String?

    static func validated(fields: [String]) -> MusicNowPlayingSnapshot? {
        guard fields.count == 4,
              let playback = PlaybackState(rawValue: fields[0]) else { return nil }
        return MusicNowPlayingSnapshot(
            playback: playback,
            title: playback == .stopped ? nil : clean(fields[1]),
            artist: playback == .stopped ? nil : clean(fields[2]),
            album: playback == .stopped ? nil : clean(fields[3])
        )
    }

    private static func clean(_ text: String) -> String? {
        // Untrusted Apple Event strings may contain newlines, terminal controls,
        // invisible formatting, or Unicode direction overrides. Never let a
        // track title reshape the compact status UI or impersonate another label.
        let safeScalars = text.unicodeScalars.filter { scalar in
            let code = scalar.value
            let isDirectionalControl = (0x202A...0x202E).contains(code)
                || (0x2066...0x2069).contains(code)
                || code == 0x200E || code == 0x200F || code == 0x061C
            return !CharacterSet.controlCharacters.contains(scalar)
                && !isDirectionalControl
        }
        let trimmed = String(String.UnicodeScalarView(safeScalars))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        // Bound visible metadata only after sanitization, preserving graphemes.
        return String(trimmed.prefix(160))
    }

    func displayedTitle(showTitles: Bool) -> String {
        guard showTitles else { return "Track details hidden" }
        return title ?? "Track title not reported"
    }
}

enum MusicConnectionState: Equatable {
    case disabled
    case notConnected
    case musicNotRunning
    case connecting
    case playing
    case paused
    case stopped
    case permissionUnavailable
    case failed

    var description: String {
        switch self {
        case .disabled: return "Apple Music integration is disabled."
        case .notConnected: return "Connect to Music explicitly to read playback state."
        case .musicNotRunning: return "Apple Music is not open. Open it yourself, then connect."
        case .connecting: return "Checking Apple Music Automation permission…"
        case .playing: return "Playing"
        case .paused: return "Paused"
        case .stopped: return "Music playback stopped"
        case .permissionUnavailable:
            return "Apple Music access wasn't granted. Check System Settings → Privacy & Security → Automation."
        case .failed: return "Apple Music playback information is unavailable."
        }
    }
}
