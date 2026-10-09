import Combine
import EventKit
import Foundation

/// An explicitly permissioned, read-only calendar source. No app startup
/// can trigger an OS calendar permission dialog.
@MainActor
final class CalendarNextEventMonitor: ObservableObject {
    @Published private(set) var access: CalendarAccessState = .notRequested
    @Published private(set) var nextEvent: CalendarNextEvent?
    @Published private(set) var requestingAccess = false

    private lazy var eventStore = EKEventStore()
    private var refreshTimer: Timer?
    private(set) var enabled = false

    func configure(enabled newValue: Bool) {
        guard enabled != newValue else { return }
        enabled = newValue
        if newValue {
            refresh()
        } else {
            stopTimer()
            nextEvent = nil
            access = .notRequested
        }
    }

    func refresh() {
        guard enabled else { return }
        let status = EKEventStore.authorizationStatus(for: .event)
        access = Self.accessState(from: status)
        guard access == .authorized else {
            nextEvent = nil
            stopTimer()
            return
        }

        let now = Date()
        let from = Calendar.current.startOfDay(for: now)
        guard let until = Calendar.current.date(
            byAdding: .day, value: CalendarEventPresentation.lookAheadDays, to: from
        ) else {
            nextEvent = nil
            return
        }

        let predicate = eventStore.predicateForEvents(
            withStart: from, end: until, calendars: nil
        )
        let candidates = eventStore.events(matching: predicate).map { event in
            CalendarNextEvent(
                title: event.title, start: event.startDate, end: event.endDate,
                isAllDay: event.isAllDay
            )
        }
        nextEvent = CalendarEventPresentation.next(from: candidates, now: now)
        startTimerIfNeeded()
    }

    /// Can only be reached from the user's explicit Grant Calendar Access button.
    func requestAccess() async {
        guard enabled, !requestingAccess, access == .notRequested else { return }
        // Swift-run is not packaged with the usage description; avoid a macOS
        // privacy process termination in development environments.
        guard Bundle.main.object(
            forInfoDictionaryKey: "NSCalendarsFullAccessUsageDescription"
        ) != nil else {
            access = .unavailable
            return
        }
        requestingAccess = true
        defer { requestingAccess = false }
        do {
            _ = try await eventStore.requestFullAccessToEvents()
        } catch {
            // Do not reveal Calendar private details or promise authorization.
            access = .denied
        }
        refresh()
    }

    static func accessState(from status: EKAuthorizationStatus) -> CalendarAccessState {
        switch status {
        case .fullAccess: return .authorized
        case .notDetermined: return .notRequested
        case .denied: return .denied
        case .restricted: return .restricted
        case .writeOnly: return .unavailable
        @unknown default: return .unavailable
        }
    }

    private func startTimerIfNeeded() {
        guard refreshTimer == nil else { return }
        let timer = Timer(
            timeInterval: CalendarEventPresentation.refreshInterval,
            repeats: true
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    private func stopTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
}
