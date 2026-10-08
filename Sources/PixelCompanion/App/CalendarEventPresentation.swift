import Foundation

/// Sanitized event summary held only in RAM. No attendee, location, calendar
/// identifier, notes or event identifier is needed to display the next event.
struct CalendarNextEvent: Equatable {
    let title: String?
    let start: Date
    let end: Date
    let isAllDay: Bool
}

enum CalendarAccessState: Equatable {
    case notRequested
    case authorized
    case denied
    case restricted
    case unavailable

    var explanation: String {
        switch self {
        case .notRequested: return "Calendar access is off. Grant access to see your next event."
        case .authorized: return "Calendar access granted."
        case .denied: return "Calendar access denied. You can change it in System Settings."
        case .restricted: return "Calendar access is restricted on this Mac."
        case .unavailable: return "Full Calendar read access is unavailable."
        }
    }
}

/// Presentation and temporal selection can be tested without EventKit or
/// reading anyone's real calendar.
enum CalendarEventPresentation {
    static let lookAheadDays = 7
    static let refreshInterval: TimeInterval = 120

    static func next(
        from candidates: [CalendarNextEvent], now: Date
    ) -> CalendarNextEvent? {
        let eligible = candidates.filter {
            $0.end > now && ($0.start >= now || $0.isAllDay)
        }
        return eligible.sorted {
            // Next future event wins over an already-running all-day event.
            let firstUpcoming = $0.start >= now
            let secondUpcoming = $1.start >= now
            if firstUpcoming != secondUpcoming { return firstUpcoming }
            if $0.start != $1.start { return $0.start < $1.start }
            return $0.end < $1.end
        }.first
    }

    static func displayTitle(
        for event: CalendarNextEvent, showTitles: Bool
    ) -> String {
        guard showTitles,
              let title = event.title?.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty else { return "Calendar event" }
        return title
    }
}
