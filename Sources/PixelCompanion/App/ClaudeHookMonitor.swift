import Combine
import Foundation

/// The hook event is an observed milestone, never proof of active work,
/// completion of a task, or permission to execute an agent action.
enum ClaudeHookEvent: String, CaseIterable {
    case sessionStart = "SessionStart"
    case promptSubmitted = "UserPromptSubmit"
    case responseStopped = "Stop"
    case responseFailed = "StopFailure"
    case sessionEnd = "SessionEnd"

    var label: String {
        switch self {
        case .sessionStart: return "Session started or resumed"
        case .promptSubmitted: return "Prompt submitted"
        case .responseStopped: return "Response finished"
        case .responseFailed: return "Response ended with API error"
        case .sessionEnd: return "Session ended"
        }
    }
}

enum ClaudeHookStatus: Equatable {
    case off
    case unconnected
    case unavailable
    case observed(event: ClaudeHookEvent, timestamp: Date)
}

enum ClaudeHookParser {
    static let maximumBytes = 2_048

    static func parse(_ data: Data, now: Date = Date()) -> ClaudeHookStatus {
        guard !data.isEmpty, data.count <= maximumBytes,
              let object = try? JSONSerialization.jsonObject(with: data),
              let payload = object as? [String: Any],
              Set(payload.keys) == ["schemaVersion", "event", "observedAt"],
              let version = payload["schemaVersion"] as? Int, version == 1,
              let raw = payload["event"] as? String,
              let event = ClaudeHookEvent(rawValue: raw),
              let timestamp = payload["observedAt"] as? String else {
            return .unavailable
        }
        let millis = ISO8601DateFormatter()
        millis.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let seconds = ISO8601DateFormatter()
        seconds.formatOptions = [.withInternetDateTime]
        guard let eventTime = millis.date(from: timestamp) ?? seconds.date(from: timestamp),
              eventTime.timeIntervalSince(now) <= 30 else {
            return .unavailable
        }
        return .observed(event: event, timestamp: eventTime)
    }

    static func isRecent(_ date: Date, at now: Date) -> Bool {
        let age = now.timeIntervalSince(date)
        return age >= -30 && age <= 120
    }
}

/// A single, manually selected folder, only polled while the user has
/// enabled the feature. Never scans ~/.claude or reads conversation material.
@MainActor
final class ClaudeHookMonitor: ObservableObject {
    @Published private(set) var status: ClaudeHookStatus = .off
    private let read: (URL) -> Data?
    private let now: () -> Date
    private var fileURL: URL?
    private var timer: Timer?
    private(set) var enabled = false

    static let eventFilename = "pixel-companion-claude-event.json"
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
        status = ClaudeHookParser.parse(data, now: now())
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
