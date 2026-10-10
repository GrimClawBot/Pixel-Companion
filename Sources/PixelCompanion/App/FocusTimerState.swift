import Foundation

/// An entirely in-memory local utility. It never interacts with agent runtimes.
enum FocusTimerMode: String, CaseIterable, Identifiable {
    case focus
    case shortBreak
    case longBreak

    var id: String { rawValue }

    var title: String {
        switch self {
        case .focus: return "Focus"
        case .shortBreak: return "Short break"
        case .longBreak: return "Long break"
        }
    }

    var duration: Int {
        switch self {
        case .focus: return 25 * 60
        case .shortBreak: return 5 * 60
        case .longBreak: return 15 * 60
        }
    }
}

/// A deadline rather than decrementing a counter prevents timer drift while
/// the menu is closed, the app is inactive, or the Mac is sleeping.
struct FocusTimerState: Equatable {
    enum Phase: Equatable {
        case idle
        case running
        case paused
        case finished
    }

    private(set) var mode: FocusTimerMode = .focus
    private(set) var phase: Phase = .idle
    private(set) var pausedSeconds = FocusTimerMode.focus.duration
    private(set) var deadline: Date?

    func remaining(at now: Date) -> Int {
        guard phase == .running, let deadline else { return pausedSeconds }
        return min(mode.duration, max(0, Int(ceil(deadline.timeIntervalSince(now)))))
    }

    mutating func choose(_ next: FocusTimerMode) {
        mode = next
        reset()
    }

    mutating func start(at now: Date) {
        guard phase != .running else { return }
        if phase == .finished { pausedSeconds = mode.duration }
        guard pausedSeconds > 0 else { return }
        deadline = now.addingTimeInterval(TimeInterval(pausedSeconds))
        phase = .running
    }

    mutating func pause(at now: Date) {
        guard phase == .running else { return }
        advance(to: now)
        guard phase == .running else { return }
        pausedSeconds = remaining(at: now)
        deadline = nil
        phase = .paused
    }

    mutating func advance(to now: Date) {
        guard phase == .running, remaining(at: now) == 0 else { return }
        deadline = nil
        pausedSeconds = 0
        phase = .finished
    }

    mutating func reset() {
        deadline = nil
        pausedSeconds = mode.duration
        phase = .idle
    }

    static func clockLabel(_ seconds: Int) -> String {
        let safe = max(seconds, 0)
        return String(format: "%02d:%02d", safe / 60, safe % 60)
    }
}
