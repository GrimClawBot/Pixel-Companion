import Foundation
import PixelCompanionCore
import UserNotifications

/// Privacy-safe notices: text never contains task, identity, session, or connector data.
enum CompanionNotice: Equatable {
    case approvals(Int)
    case completedRuns(Int)
    case failedRuns(Int)

    var title: String {
        switch self {
        case .approvals: return "Approval needed"
        case .completedRuns: return "Agent run completed"
        case .failedRuns: return "Agent run failed"
        }
    }

    var body: String {
        switch self {
        case let .approvals(count):
            return count == 1 ? "A new request needs review." : "\(count) new requests need review."
        case let .completedRuns(count):
            return count == 1 ? "An agent finished its run." : "\(count) agent runs finished."
        case let .failedRuns(count):
            return count == 1 ? "An agent run needs attention." : "\(count) agent runs need attention."
        }
    }
}

/// Pure, testable transition policy. No notice on the first connected snapshot.
struct CompanionNoticeDetector {
    private var previous: ConnectorSnapshot?
    private var seenApprovalIDs: Set<String> = []

    mutating func reset() {
        previous = nil
        seenApprovalIDs.removeAll()
    }

    mutating func observe(_ snapshot: ConnectorSnapshot) -> [CompanionNotice] {
        guard snapshot.connectionState == .connected else {
            reset()
            return []
        }
        guard let old = previous, old.connectorName == snapshot.connectorName else {
            reset()
            previous = snapshot
            seenApprovalIDs.formUnion(snapshot.pendingApprovals.map(\.id))
            return []
        }
        previous = snapshot

        let newApprovals = snapshot.pendingApprovals.filter {
            !seenApprovalIDs.contains($0.id)
        }.count
        seenApprovalIDs.formUnion(snapshot.pendingApprovals.map(\.id))

        let oldRuns = Dictionary(
            old.agentSessions.map { ($0.agentID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var completed = 0
        var failed = 0
        for session in snapshot.agentSessions {
            guard let previousRun = oldRuns[session.agentID],
                  let runID = session.runID,
                  runID == previousRun.runID,
                  previousRun.isActive else { continue }
            switch session.runState {
            case .completed: completed += 1
            case .failed: failed += 1
            default: break
            }
        }
        var notices: [CompanionNotice] = []
        if newApprovals > 0 { notices.append(.approvals(newApprovals)) }
        if completed > 0 { notices.append(.completedRuns(completed)) }
        if failed > 0 { notices.append(.failedRuns(failed)) }
        return notices
    }
}

@MainActor
final class CompanionNotificationManager {
    enum PermissionState {
        case off
        case checking
        case ready
        case denied
        case unavailable
        case needsPermission
    }

    private static let preferenceKey = "pixelCompanion.notificationsEnabled"

    private let defaults: UserDefaults
    private var detector = CompanionNoticeDetector()
    private(set) var enabled: Bool
    private(set) var permission: PermissionState = .off
    var onChange: (() -> Void)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        enabled = defaults.bool(forKey: Self.preferenceKey)
    }

    var statusText: String {
        switch permission {
        case .off: return "Off — nothing is sent to Notification Center."
        case .checking: return "Checking macOS notification permission…"
        case .ready: return "Enabled for new Paperclip events."
        case .denied: return "Denied by macOS. Allow notifications in System Settings."
        case .unavailable: return "Requires an installed macOS .app bundle; swift run is unsupported."
        case .needsPermission: return "macOS permission is required to show notifications."
        }
    }

    func start() {
        guard enabled else { return }
        guard isBundled else { setPermission(.unavailable); return }
        setPermission(.checking)
        Task { [weak self] in
            let current = await UNUserNotificationCenter.current().notificationSettings()
            guard let self, self.enabled else { return }
            switch current.authorizationStatus {
            case .authorized, .provisional, .ephemeral: self.setPermission(.ready)
            case .denied: self.setPermission(.denied)
            case .notDetermined: self.setPermission(.needsPermission)
            @unknown default: self.setPermission(.denied)
            }
        }
    }

    func setEnabled(_ value: Bool) {
        guard value != enabled else { return }
        enabled = value
        defaults.set(value, forKey: Self.preferenceKey)
        detector.reset()
        if value {
            requestPermission()
        } else {
            setPermission(.off)
        }
    }

    func requestPermission() {
        guard enabled else { return }
        guard isBundled else { setPermission(.unavailable); return }
        setPermission(.checking)
        Task { [weak self] in
            let approved = (try? await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])) ?? false
            guard let self, self.enabled else { return }
            self.setPermission(approved ? .ready : .denied)
        }
    }

    func observe(_ snapshot: ConnectorSnapshot, isPaperclip: Bool) {
        guard enabled && isPaperclip else {
            detector.reset()
            return
        }
        let notices = detector.observe(snapshot)
        guard permission == .ready else { return }
        for notice in notices {
            let content = UNMutableNotificationContent()
            content.title = notice.title
            content.body = notice.body
            content.sound = .default
            let request = UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: nil
            )
            UNUserNotificationCenter.current().add(request)
        }
    }

    func resetBaseline() {
        detector.reset()
    }

    private var isBundled: Bool {
        Bundle.main.bundleURL.pathExtension.lowercased() == "app"
    }

    private func setPermission(_ value: PermissionState) {
        permission = value
        onChange?()
    }
}
