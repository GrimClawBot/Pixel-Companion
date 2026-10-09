import Combine
import Foundation

/// Generic, opt-in host metrics from a specifically selected local JSON file.
/// All values are source-reported, not verified host sensors or Paperclip health.
struct LocalInfrastructureHost: Equatable, Identifiable {
    enum DeploymentState: String, Decodable {
        case healthy
        case degraded
        case failed
        case unknown
    }

    struct Deployment: Equatable {
        let name: String
        let state: DeploymentState
    }

    let id: String
    let name: String
    let observedAt: Date
    let cpuPercent: Double?
    let memoryUsedBytes: Int64?
    let memoryTotalBytes: Int64?
    let diskUsedBytes: Int64?
    let diskTotalBytes: Int64?
    let temperatureCelsius: Double?
    let receiveBytesPerSecond: Int64?
    let transmitBytesPerSecond: Int64?
    let deployment: Deployment?

    func isFresh(at now: Date) -> Bool {
        let age = now.timeIntervalSince(observedAt)
        return age >= -30 && age <= 120
    }

    var memoryFraction: Double? {
        guard let used = memoryUsedBytes, let total = memoryTotalBytes, total > 0 else { return nil }
        return Double(used) / Double(total)
    }

    var diskFraction: Double? {
        guard let used = diskUsedBytes, let total = diskTotalBytes, total > 0 else { return nil }
        return Double(used) / Double(total)
    }
}

enum LocalInfrastructureStatus: Equatable {
    case disabled
    case unconnected
    case unavailable
    case empty
    case loaded([LocalInfrastructureHost])
}

private struct InfrastructureEnvelope: Decodable {
    let schemaVersion: Int
    let hosts: [InfrastructureRow]
}

private struct InfrastructureRow: Decodable {
    struct DeploymentRow: Decodable {
        let name: String
        let state: LocalInfrastructureHost.DeploymentState
    }

    let id: String
    let name: String
    let observedAt: String
    let cpuPercent: Double?
    let memoryUsedBytes: Int64?
    let memoryTotalBytes: Int64?
    let diskUsedBytes: Int64?
    let diskTotalBytes: Int64?
    let temperatureCelsius: Double?
    let receiveBytesPerSecond: Int64?
    let transmitBytesPerSecond: Int64?
    let deployment: DeploymentRow?
}

enum LocalInfrastructureParser {
    static let maximumBytes = 65_536
    static let maximumHosts = 8

    static func parse(_ data: Data, now: Date = Date()) -> LocalInfrastructureStatus {
        guard !data.isEmpty, data.count <= maximumBytes,
              let envelope = try? JSONDecoder().decode(InfrastructureEnvelope.self, from: data),
              envelope.schemaVersion == 1, envelope.hosts.count <= maximumHosts else {
            return .unavailable
        }

        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        var seen = Set<String>()
        var hosts: [LocalInfrastructureHost] = []
        for row in envelope.hosts {
            guard validID(row.id), seen.insert(row.id).inserted,
                  let name = cleanLabel(row.name),
                  let observed = fractional.date(from: row.observedAt)
                    ?? standard.date(from: row.observedAt),
                  observed.timeIntervalSince(now) <= 30,
                  validPercent(row.cpuPercent),
                  validCapacity(used: row.memoryUsedBytes, total: row.memoryTotalBytes),
                  validCapacity(used: row.diskUsedBytes, total: row.diskTotalBytes),
                  validTemperature(row.temperatureCelsius),
                  validRate(row.receiveBytesPerSecond), validRate(row.transmitBytesPerSecond)
            else { return .unavailable }

            var deployment: LocalInfrastructureHost.Deployment?
            if let reported = row.deployment {
                guard let label = cleanLabel(reported.name) else { return .unavailable }
                deployment = .init(name: label, state: reported.state)
            }
            hosts.append(LocalInfrastructureHost(
                id: row.id, name: name, observedAt: observed,
                cpuPercent: row.cpuPercent,
                memoryUsedBytes: row.memoryUsedBytes, memoryTotalBytes: row.memoryTotalBytes,
                diskUsedBytes: row.diskUsedBytes, diskTotalBytes: row.diskTotalBytes,
                temperatureCelsius: row.temperatureCelsius,
                receiveBytesPerSecond: row.receiveBytesPerSecond,
                transmitBytesPerSecond: row.transmitBytesPerSecond, deployment: deployment
            ))
        }
        return hosts.isEmpty ? .empty : .loaded(hosts)
    }

    private static func validID(_ value: String) -> Bool {
        let allowed = CharacterSet(charactersIn:
            "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-"
        )
        return (1...80).contains(value.count) &&
            value.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    private static func cleanLabel(_ value: String) -> String? {
        let filtered = value.unicodeScalars.filter { scalar in
            let number = scalar.value
            return !CharacterSet.controlCharacters.contains(scalar) &&
                !(0x202A...0x202E).contains(number) &&
                !(0x2066...0x2069).contains(number) &&
                number != 0x061C && number != 0x200E && number != 0x200F
        }
        let label = String(String.UnicodeScalarView(filtered))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return !label.isEmpty && label.count <= 64 ? label : nil
    }

    private static func validPercent(_ number: Double?) -> Bool {
        guard let number else { return true }
        return number.isFinite && (0...100).contains(number)
    }

    private static func validCapacity(used: Int64?, total: Int64?) -> Bool {
        if used == nil && total == nil { return true }
        guard let used, let total else { return false }
        return total > 0 && used >= 0 && used <= total
    }

    private static func validTemperature(_ number: Double?) -> Bool {
        guard let number else { return true }
        return number.isFinite && (-40...150).contains(number)
    }

    private static func validRate(_ value: Int64?) -> Bool {
        guard let value else { return true }
        return (0...1_000_000_000_000).contains(value)
    }
}

/// Same hardened file transport as the existing optional local-agent source:
/// reads one explicit regular file, max 64 KiB; rejects final-path symlinks.
/// File location and host data are never saved or uploaded.
@MainActor
final class LocalInfrastructureMonitor: ObservableObject {
    @Published private(set) var status: LocalInfrastructureStatus = .disabled
    private let read: @Sendable (URL) -> Data?
    private let now: () -> Date
    private var selectedFile: URL?
    private var timer: Timer?
    private var readTask: Task<Void, Never>?
    private var revision: UInt64 = 0
    private(set) var enabled = false

    static let refreshInterval: TimeInterval = 15

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
        // A slow mounted/cloud report must never block SwiftUI or overlap later polls.
        guard enabled, let selectedFile, readTask == nil else { return }
        let currentRevision = revision
        let read = self.read
        readTask = Task.detached(priority: .utility) { [weak self] in
            let data = read(selectedFile)
            // If cancelled while a synchronous filesystem call was waiting, do not
            // deliver any stale result. The generation guard also covers reconnects.
            guard !Task.isCancelled else { return }
            await self?.finishRefresh(data, file: selectedFile, revision: currentRevision)
        }
    }

    private func finishRefresh(_ data: Data?, file: URL, revision candidate: UInt64) {
        guard enabled, revision == candidate, selectedFile == file else { return }
        readTask = nil
        status = data.map { LocalInfrastructureParser.parse($0, now: now()) } ?? .unavailable
    }

    private func restart() {
        timer?.invalidate()
        timer = nil
        revision &+= 1
        readTask?.cancel()
        readTask = nil
        guard enabled else { status = .disabled; return }
        guard selectedFile != nil else { status = .unconnected; return }
        // Clear an old file's health immediately, even if the replacement blocks.
        status = .unavailable
        refresh()
        let newTimer = Timer(timeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        RunLoop.main.add(newTimer, forMode: .common)
        timer = newTimer
    }
}
