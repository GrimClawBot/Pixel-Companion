import Combine
import Foundation

/// Codex notify only reports a TURN ENDED, not successful task completion.
/// It cannot establish whether a session is currently active.
enum CodexTurnStatus: Equatable {
    case off
    case unconnected
    case unavailable
    case observed(Date)
}

enum CodexTurnParser {
    static let maximumBytes = 2_048

    private struct Payload: Decodable {
        let schemaVersion: Int
        let event: String
        let lastCompletedAt: String
    }

    static func parse(_ data: Data, now: Date = Date()) -> CodexTurnStatus {
        guard !data.isEmpty, data.count <= maximumBytes,
              let payload = try? JSONDecoder().decode(Payload.self, from: data),
              payload.schemaVersion == 1, payload.event == "agent-turn-complete" else {
            return .unavailable
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        guard let date = formatter.date(from: payload.lastCompletedAt)
            ?? plain.date(from: payload.lastCompletedAt),
              date.timeIntervalSince(now) <= 30 else { return .unavailable }
        return .observed(date)
    }

    static func isRecent(_ date: Date, at now: Date) -> Bool {
        let age = now.timeIntervalSince(date)
        return age >= -30 && age <= 120
    }
}

/// Polls one explicitly selected normal JSON file; never accesses Codex
/// history, configuration, prompts, messages, CLI or process arguments.
@MainActor
final class CodexTurnMonitor: ObservableObject {
    @Published private(set) var status: CodexTurnStatus = .off
    private let read: (URL) -> Data?
    private let now: () -> Date
    private var fileURL: URL?
    private var timer: Timer?
    private(set) var enabled = false

    static let refreshInterval: TimeInterval = 15

    init(
        read: @escaping (URL) -> Data? = LocalAgentFeedFileReader.read,
        now: @escaping () -> Date = Date.init
    ) {
        self.read = read
        self.now = now
    }

    var isConnected: Bool { enabled && fileURL != nil }

    func configure(enabled newValue: Bool) {
        guard enabled != newValue else { return }
        enabled = newValue
        if !newValue { fileURL = nil }
        restart()
    }

    static let eventFilename = "pixel-companion-codex-turn.json"

    /// Choosing a directory works even before the first hook notification
    /// creates the event file. No directory contents are enumerated.
    func connectDirectory(_ directory: URL) {
        guard enabled, directory.isFileURL,
              (try? directory.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
        else { return }
        fileURL = directory.standardizedFileURL.appendingPathComponent(Self.eventFilename)
        restart()
    }

    func disconnect() {
        fileURL = nil
        restart()
    }

    func refresh() {
        guard enabled, let fileURL else { return }
        guard let data = read(fileURL) else { status = .unavailable; return }
        status = CodexTurnParser.parse(data, now: now())
    }

    private func restart() {
        timer?.invalidate()
        timer = nil
        guard enabled else { status = .off; return }
        guard fileURL != nil else { status = .unconnected; return }
        refresh()
        let ticker = Timer(timeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        RunLoop.main.add(ticker, forMode: .common)
        timer = ticker
    }
}
