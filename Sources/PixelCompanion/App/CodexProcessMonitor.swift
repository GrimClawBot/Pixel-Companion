import Combine
import Darwin
import Foundation

/// Presence does not imply an active run: Codex may keep a background
/// app-server process alive while no conversation is in progress.
enum CodexProcessPresence: Equatable {
    case off
    case unavailable
    case absent
    case detected(count: Int)
}

/// Pure process metadata matching. No process arguments, paths, transcripts,
/// file descriptors or command invocations are inspected.
enum CodexProcessClassification {
    static func count(names: [String]) -> Int {
        min(names.filter { $0 == "codex" }.count, 64)
    }
}

/// BSD sysctl is used rather than macOS private libproc methods.
/// This reads process *names only*, and filters to the current user's UID.
/// A process name cannot establish the publisher, conversation or run status.
enum CodexProcessReader {
    static func readNames() -> [String]? {
        var query: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL]
        var requiredBytes = 0
        guard sysctl(&query, u_int(query.count), nil, &requiredBytes, nil, 0) == 0,
              requiredBytes > 0 else { return nil }

        // Bound resource usage, even on a Mac with unusual process counts.
        let stride = MemoryLayout<kinfo_proc>.stride
        let count = min(requiredBytes / stride + 32, 16_384)
        var records = [kinfo_proc](repeating: kinfo_proc(), count: count)
        var actualBytes = records.count * stride
        let status = records.withUnsafeMutableBufferPointer { buffer in
            sysctl(&query, u_int(query.count), buffer.baseAddress, &actualBytes, nil, 0)
        }
        guard status == 0, actualBytes % stride == 0 else { return nil }

        let userID = getuid()
        return records.prefix(actualBytes / stride).compactMap { record in
            guard record.kp_eproc.e_ucred.cr_uid == userID,
                  record.kp_proc.p_stat != 0 else { return nil }
            let nameBytes = withUnsafeBytes(of: record.kp_proc.p_comm) { bytes in
                Array(bytes.prefix(while: { $0 != 0 }))
            }
            return String(bytes: nameBytes, encoding: .utf8)
        }
    }
}

@MainActor
final class CodexProcessMonitor: ObservableObject {
    @Published private(set) var presence: CodexProcessPresence = .off
    private let readNames: () -> [String]?
    private var timer: Timer?
    private(set) var enabled = false

    static let refreshInterval: TimeInterval = 15

    init(readNames: @escaping () -> [String]? = CodexProcessReader.readNames) {
        self.readNames = readNames
    }

    func configure(enabled newValue: Bool) {
        guard enabled != newValue else { return }
        enabled = newValue
        timer?.invalidate()
        timer = nil
        if newValue {
            refresh()
            let newTimer = Timer(timeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
            RunLoop.main.add(newTimer, forMode: .common)
            timer = newTimer
        } else {
            presence = .off
        }
    }

    func refresh() {
        guard enabled else { return }
        guard let names = readNames() else {
            presence = .unavailable
            return
        }
        let detected = CodexProcessClassification.count(names: names)
        presence = detected == 0 ? .absent : .detected(count: detected)
    }
}
