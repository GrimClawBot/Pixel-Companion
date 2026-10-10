import Combine
import Foundation

/// A deliberately narrow opt-in adapter API; no OS-wide downloads scan exists.
/// Sources supply byte counts only: no URLs, filenames, cookies or file paths.
struct DownloadProgressReport: Equatable, Sendable {
    let receivedBytes: Int64
    let expectedBytes: Int64?
}

protocol DownloadProgressSource {
    func currentTransfer() -> DownloadProgressReport?
}

enum DownloadProgressState: Equatable {
    case noSource
    case idle
    case active(percent: Int?)
    case finished

    static func validated(_ report: DownloadProgressReport?) -> DownloadProgressState {
        guard let report else { return .idle }
        guard report.receivedBytes >= 0 else { return .idle }
        guard let total = report.expectedBytes else { return .active(percent: nil) }
        guard total > 0, report.receivedBytes <= total else { return .idle }
        if report.receivedBytes == total { return .finished }
        let percentage = Int((Double(report.receivedBytes) / Double(total) * 100).rounded())
        return .active(percent: min(percentage, 99))
    }
}

/// No registered provider is present by default, so no phantom downloads or
/// polling occur. A later reviewed connector can explicitly register a source.
@MainActor
final class DownloadProgressMonitor: ObservableObject {
    @Published private(set) var state: DownloadProgressState = .noSource
    private var source: (any DownloadProgressSource)?
    private var timer: Timer?
    private(set) var enabled = false

    static let refreshInterval: TimeInterval = 5

    func register(source newSource: (any DownloadProgressSource)?) {
        source = newSource
        reconfigureTimer()
    }

    func configure(enabled newValue: Bool) {
        guard enabled != newValue else { return }
        enabled = newValue
        reconfigureTimer()
    }

    func refresh() {
        guard enabled else { return }
        state = source.map { .validated($0.currentTransfer()) } ?? .noSource
    }

    private func reconfigureTimer() {
        timer?.invalidate()
        timer = nil
        guard enabled else {
            state = .noSource
            return
        }
        refresh()
        guard source != nil else { return }
        let ticker = Timer(timeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        RunLoop.main.add(ticker, forMode: .common)
        timer = ticker
    }
}
