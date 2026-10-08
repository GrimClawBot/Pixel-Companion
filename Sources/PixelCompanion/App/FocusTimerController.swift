import Combine
import Foundation

/// A single low-cost UI timer is active only during an explicitly started
/// local focus session. It does not issue macOS notifications or background jobs.
@MainActor
final class FocusTimerController: ObservableObject {
    @Published private(set) var state = FocusTimerState()
    private var ticker: Timer?

    func choose(_ mode: FocusTimerMode) {
        cancelTicker()
        state.choose(mode)
    }

    func toggle() {
        let now = Date()
        if state.phase == .running {
            state.pause(at: now)
            cancelTicker()
        } else {
            state.start(at: now)
            updateTicker()
        }
    }

    func reset() {
        cancelTicker()
        state.reset()
    }

    /// Called on macOS wake and when displaying a long-idle panel.
    func refresh() {
        state.advance(to: Date())
        updateTicker()
    }

    func stop() {
        cancelTicker()
        state.reset()
    }

    private func updateTicker() {
        if state.phase != .running {
            cancelTicker()
        } else if ticker == nil {
            let ticker = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }
            RunLoop.main.add(ticker, forMode: .common)
            self.ticker = ticker
        }
    }

    private func cancelTicker() {
        ticker?.invalidate()
        ticker = nil
    }
}
