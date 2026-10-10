import Combine
import Darwin
import Foundation

/// Provider-neutral, read-only status transport. This is NOT an agent
/// transcript reader and must never treat task/log data as status.
enum LocalAgentSource: String, Codable, CaseIterable {
    case codex
    case claudeCode = "claude-code"
    case hermes
    case custom

    var label: String {
        switch self {
        case .codex: return "Codex"
        case .claudeCode: return "Claude Code"
        case .hermes: return "Hermes"
        case .custom: return "Local agent"
        }
    }
}

enum LocalAgentState: String, Codable {
    case running
    case waiting
    case idle
    case completed
    case failed
}

struct LocalAgentSession: Equatable, Identifiable {
    let id: String
    let source: LocalAgentSource
    let name: String
    let state: LocalAgentState
    let updatedAt: Date

    func isFresh(at now: Date) -> Bool {
        let age = now.timeIntervalSince(updatedAt)
        return age >= -30 && age <= 120
    }
}

enum LocalAgentFeedStatus: Equatable {
    case disabled
    case unconnected
    case unavailable
    case empty
    case loaded([LocalAgentSession])
}

private struct LocalFeedEnvelope: Decodable {
    let schemaVersion: Int
    let sessions: [LocalFeedRow]
}

private struct LocalFeedRow: Decodable {
    let id: String
    let source: LocalAgentSource
    let name: String
    let state: LocalAgentState
    let updatedAt: String
}

enum LocalAgentFeedParser {
    static let maximumBytes = 65_536
    static let maximumSessions = 12

    static func parse(_ data: Data, now: Date = Date()) -> LocalAgentFeedStatus {
        guard !data.isEmpty, data.count <= maximumBytes,
              let envelope = try? JSONDecoder().decode(LocalFeedEnvelope.self, from: data),
              envelope.schemaVersion == 1,
              envelope.sessions.count <= maximumSessions else { return .unavailable }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let noFractions = ISO8601DateFormatter()
        noFractions.formatOptions = [.withInternetDateTime]
        var ids = Set<String>()
        var result: [LocalAgentSession] = []
        for row in envelope.sessions {
            guard (1...80).contains(row.id.count),
                  row.id.unicodeScalars.allSatisfy({ scalar in
                      CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")
                          .contains(scalar)
                  }),
                  ids.insert(row.id).inserted,
                  let name = cleanedName(row.name),
                  let date = formatter.date(from: row.updatedAt)
                    ?? noFractions.date(from: row.updatedAt),
                  date.timeIntervalSince(now) <= 30 else { return .unavailable }
            result.append(LocalAgentSession(
                id: row.id, source: row.source, name: name,
                state: row.state, updatedAt: date
            ))
        }
        return result.isEmpty ? .empty : .loaded(result)
    }

    private static func cleanedName(_ text: String) -> String? {
        let safe = text.unicodeScalars.filter { scalar in
            let number = scalar.value
            return !CharacterSet.controlCharacters.contains(scalar)
                && !(0x202A...0x202E).contains(number)
                && !(0x2066...0x2069).contains(number)
                && number != 0x200E && number != 0x200F && number != 0x061C
        }
        let name = String(String.UnicodeScalarView(safe))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 64 else { return nil }
        return name
    }
}

/// Read at most 64KiB from ONE explicitly chosen, regular local file. Reject
/// symlinks (including replacements after selection) and nonregular devices.
/// No directory enumeration, path persistence, agent execution or network.
enum LocalAgentFeedFileReader {
    static func read(_ url: URL) -> Data? {
        guard url.isFileURL, !url.hasDirectoryPath else { return nil }
        let descriptor = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        guard descriptor >= 0 else { return nil }
        defer { _ = Darwin.close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0,
              (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG),
              info.st_size > 0,
              info.st_size <= LocalAgentFeedParser.maximumBytes else { return nil }
        var bytes = [UInt8](repeating: 0, count: LocalAgentFeedParser.maximumBytes + 1)
        let count = bytes.withUnsafeMutableBytes { buffer in
            Darwin.read(descriptor, buffer.baseAddress, buffer.count)
        }
        guard count > 0, count <= LocalAgentFeedParser.maximumBytes,
              count == info.st_size else { return nil }
        return Data(bytes.prefix(count))
    }
}

@MainActor
final class LocalAgentFeedMonitor: ObservableObject {
    @Published private(set) var status: LocalAgentFeedStatus = .disabled
    private let read: @Sendable (URL) -> Data?
    private let now: () -> Date
    private var selectedFile: URL?
    private var timer: Timer?
    private var readTask: Task<Void, Never>?
    private var revision: UInt64 = 0
    // Observable to internal diagnostics/tests; never exposes source contents.
    var isReading: Bool { readTask != nil }
    private(set) var enabled = false

    static let refreshInterval: TimeInterval = 10

    init(
        read: @escaping @Sendable (URL) -> Data? = { LocalAgentFeedFileReader.read($0) },
        now: @escaping () -> Date = Date.init
    ) {
        self.read = read
        self.now = now
    }

    var isConnected: Bool { enabled && selectedFile != nil }

    func configure(enabled newValue: Bool) {
        guard enabled != newValue else { return }
        enabled = newValue
        if !newValue { selectedFile = nil }
        restart()
    }

    func connect(_ url: URL) {
        guard enabled, url.isFileURL, !url.hasDirectoryPath else { return }
        selectedFile = url.standardizedFileURL
        restart()
    }

    func disconnect() {
        selectedFile = nil
        restart()
    }

    func refresh() {
        guard enabled, let source = selectedFile, readTask == nil else { return }
        let currentRevision = revision
        let reader = read
        readTask = Task.detached(priority: .utility) { [weak self] in
            let data = reader(source)
            guard !Task.isCancelled else { return }
            await self?.acceptRead(data, source: source, revision: currentRevision)
        }
    }

    private func acceptRead(_ data: Data?, source: URL, revision candidate: UInt64) {
        guard enabled, revision == candidate, selectedFile == source else { return }
        readTask = nil
        status = data.map { LocalAgentFeedParser.parse($0, now: now()) } ?? .unavailable
    }

    private func restart() {
        timer?.invalidate()
        timer = nil
        revision &+= 1
        readTask?.cancel()
        readTask = nil
        guard enabled else { status = .disabled; return }
        guard selectedFile != nil else { status = .unconnected; return }
        status = .unavailable
        refresh()
        let newTimer = Timer(timeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        RunLoop.main.add(newTimer, forMode: .common)
        timer = newTimer
    }
}
