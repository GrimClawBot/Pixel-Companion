import Foundation
import PixelCompanionCore

/// Presentation-only confidence in the Paperclip *poll*, not an agent's actual activity.
enum FeedFreshness: Equatable {
    case notApplicable
    case connecting
    case current
    case stale
    case unavailable

    static func evaluate(
        isPaperclip: Bool,
        state: ConnectionState,
        lastSuccess: Date?,
        now: Date = Date(),
        refreshInterval: TimeInterval = SettingsStore.paperclipRefreshInterval
    ) -> FeedFreshness {
        guard isPaperclip else { return .notApplicable }
        switch state {
        case .error, .disconnected: return .unavailable
        case .connecting: return .connecting
        case .connected:
            guard let lastSuccess else { return .connecting }
            let age = now.timeIntervalSince(lastSuccess)
            return age >= 0 && age <= refreshInterval * 4 ? .current : .stale
        }
    }

    var canPresentAsLive: Bool {
        self == .notApplicable || self == .current
    }

    var warning: String? {
        switch self {
        case .stale: return "Paperclip updates are delayed. Activity may be outdated."
        case .unavailable: return "Paperclip is unavailable. Previously loaded activity may be outdated."
        case .connecting: return "Waiting for a successful Paperclip refresh."
        case .notApplicable, .current: return nil
        }
    }
}
