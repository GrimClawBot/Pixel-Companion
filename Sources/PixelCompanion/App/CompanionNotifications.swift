import Foundation
import PixelCompanionCore
import UserNotifications

/// Static content excludes agent, task, and connector data.
enum CompanionNotice: Equatable {
    case approvals(Int)
    case completedRuns(Int)
    case failedRuns(Int)
    case test

    var title: String {
        switch self {
        case .approvals: return "Approval needed"
        case .completedRuns: return "Agent run completed"
        case .failedRuns: return "Agent run failed"
        case .test: return "Pixel Companion test"
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
        case .test:
            return "This is a local test notification."
        }
    }
}

/// Remember observed active runs across temporary unknown/missing telemetry; never infer live runs.
struct CompanionNoticeDetector {
    private struct TrackedRun {
        var observedActive: Bool
        var notified: Bool
        var lastPoll: Int
    }

    private var connectorName: String?
    private var seenApprovalIDs: Set<String> = []
    private var tracked: [String: TrackedRun] = [:]
    private var poll = 0

    mutating func reset() {
        connectorName = nil
        seenApprovalIDs.removeAll()
        tracked.removeAll()
        poll = 0
    }

    mutating func observe(_ snapshot: ConnectorSnapshot) -> [CompanionNotice] {
        guard snapshot.connectionState == .connected else {
            reset()
            return []
        }
        if connectorName != snapshot.connectorName {
            reset()
            connectorName = snapshot.connectorName
            seenApprovalIDs.formUnion(snapshot.pendingApprovals.map(\.id))
            _ = scanRuns(snapshot.agentSessions, notify: false)
            return []
        }

        let currentIDs = Set(snapshot.pendingApprovals.map(\.id))
        let newApprovals = currentIDs.subtracting(seenApprovalIDs).count
        seenApprovalIDs.formUnion(currentIDs)
        let endings = scanRuns(snapshot.agentSessions, notify: true)
        var notices: [CompanionNotice] = []
        if newApprovals > 0 { notices.append(.approvals(newApprovals)) }
        if endings.completed > 0 { notices.append(.completedRuns(endings.completed)) }
        if endings.failed > 0 { notices.append(.failedRuns(endings.failed)) }
        return notices
    }

    private mutating func scanRuns(
        _ sessions: [AgentSessionSnapshot],
        notify: Bool
    ) -> (completed: Int, failed: Int) {
        poll += 1
        var completed = 0
        var failed = 0
        for session in sessions {
            guard let runID = session.runID else { continue }
            let key = session.agentID + ":" + runID
            var state = tracked[key] ?? TrackedRun(observedActive: false, notified: false, lastPoll: poll)
            if session.isActive { state.observedActive = true }
            if notify && state.observedActive && !state.notified {
                switch session.runState {
                case .completed:
                    completed += 1
                    state.notified = true
                case .failed:
                    failed += 1
                    state.notified = true
                default: break
                }
            }
            state.lastPoll = poll
            tracked[key] = state
        }
        // A run can briefly vanish from telemetry; bound retained evidence by polls and count.
        tracked = tracked.filter { poll - $0.value.lastPoll <= 12 }
        if tracked.count > 512 {
            let overflow = tracked.count - 512
            let oldest = tracked.sorted { $0.value.lastPoll < $1.value.lastPoll }.prefix(overflow)
            for item in oldest { tracked.removeValue(forKey: item.key) }
        }
        return (completed, failed)
    }
}

enum CompanionAuthorization {
    case authorized
    case denied
    case notDetermined
}

@MainActor
protocol CompanionNoticeCenter: AnyObject {
    func authorization() async -> CompanionAuthorization
    func requestPermission() async -> Bool
    func deliver(_ notice: CompanionNotice)
    func submitTest() async throws
}

@MainActor
final class SystemCompanionNoticeCenter: NSObject, CompanionNoticeCenter, UNUserNotificationCenterDelegate {
    override init() {
        super.init()
        // SwiftPM/XCTest processes have no app bundle and cannot register with Notification Center.
        guard Bundle.main.bundleURL.pathExtension.lowercased() == "app" else { return }
        // macOS otherwise suppresses banners while the app is foreground/active.
        UNUserNotificationCenter.current().delegate = self
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func authorization() async -> CompanionAuthorization {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return .authorized
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        @unknown default: return .denied
        }
    }

    func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound])) ?? false
    }

    private func request(for notice: CompanionNotice) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = notice.title
        content.body = notice.body
        content.sound = .default
        return UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
    }

    func deliver(_ notice: CompanionNotice) {
        UNUserNotificationCenter.current().add(request(for: notice)) { error in
            if let error {
                NSLog("Pixel Companion: macOS notification submission failed: %@", error.localizedDescription)
            }
        }
    }

    func submitTest() async throws {
        try await UNUserNotificationCenter.current().add(request(for: .test))
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
    private let center: any CompanionNoticeCenter
    private let isBundled: Bool
    private let isQABuild: Bool
    private var detector = CompanionNoticeDetector()
    private var pending: [CompanionNotice] = []
    private var authorizationGeneration = 0
    private(set) var enabled: Bool
    private(set) var permission: PermissionState = .off
    private(set) var testStatus: String?
    private var submittingTest = false
    private var testGeneration = 0
    var onChange: (() -> Void)?

    init(
        defaults: UserDefaults = .standard,
        center: (any CompanionNoticeCenter)? = nil,
        isBundled: Bool = Bundle.main.bundleURL.pathExtension.lowercased() == "app",
        isQABuild: Bool = CompanionBuildInfo.qaUpdate != nil
    ) {
        self.defaults = defaults
        self.center = center ?? SystemCompanionNoticeCenter()
        self.isBundled = isBundled
        self.isQABuild = isQABuild
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
        refreshPermission()
    }

    func setEnabled(_ value: Bool) {
        guard value != enabled else { return }
        enabled = value
        defaults.set(value, forKey: Self.preferenceKey)
        resetBaseline()
        testGeneration += 1
        submittingTest = false
        testStatus = nil
        if value {
            requestPermission()
        } else {
            authorizationGeneration += 1
            setPermission(.off)
        }
    }

    func requestPermission() {
        guard enabled else { return }
        guard isBundled else { setPermission(.unavailable); return }
        authorizationGeneration += 1
        let generation = authorizationGeneration
        setPermission(.checking)
        Task { [weak self] in
            guard let self else { return }
            let allowed = await self.center.requestPermission()
            guard self.enabled && generation == self.authorizationGeneration else { return }
            self.setPermission(allowed ? .ready : .denied)
        }
    }

    /// Refresh on app activation, including return from the macOS System Settings pane.
    func refreshPermission() {
        guard enabled else { setPermission(.off); return }
        guard isBundled else { setPermission(.unavailable); return }
        // Never invalidate an in-flight permission prompt when the app gains focus.
        guard permission != .checking else { return }
        authorizationGeneration += 1
        let generation = authorizationGeneration
        if permission == .off { setPermission(.checking) }
        Task { [weak self] in
            guard let self else { return }
            let status = await self.center.authorization()
            guard self.enabled && generation == self.authorizationGeneration else { return }
            switch status {
            case .authorized: self.setPermission(.ready)
            case .denied: self.setPermission(.denied)
            case .notDetermined: self.setPermission(.needsPermission)
            }
        }
    }

    func observe(_ snapshot: ConnectorSnapshot, isPaperclip: Bool) {
        guard enabled && isPaperclip else {
            resetBaseline()
            return
        }
        let notices = detector.observe(snapshot)
        switch permission {
        case .ready:
            notices.forEach { center.deliver($0) }
        case .checking:
            pending.append(contentsOf: notices)
            if pending.count > 24 { pending.removeFirst(pending.count - 24) }
        case .off, .denied, .unavailable, .needsPermission:
            break
        }
    }

    /// Explicit local QA action; works without Paperclip and never sends runtime commands.
    var canSendTest: Bool {
        enabled && isBundled && permission == .ready && !submittingTest
    }

    func sendTestNotification() async {
        guard canSendTest else { return }
        let generation = testGeneration
        submittingTest = true
        testStatus = "Submitting local test notification…"
        onChange?()
        let result: String
        do {
            try await center.submitTest()
            result = "macOS accepted the test. If no banner appears, check Notification Center and Focus."
        } catch {
            result = "macOS rejected the notification: \(error.localizedDescription)"
        }
        // Disabling, re-enabling or losing authorization invalidates in-flight results.
        guard generation == testGeneration && enabled && permission == .ready else { return }
        testStatus = result
        submittingTest = false
        onChange?()
    }

    var canSimulateQAEvent: Bool {
        isQABuild && canSendTest
    }

    func simulateQAEvent(_ scenario: CompanionQAScenario) {
        guard canSimulateQAEvent else { return }
        // Isolated detector: never mutates the live Paperclip notification baseline.
        scenario.notices().forEach { center.deliver($0) }
        testStatus = "Requested local simulated \(scenario.label) alert. No Paperclip changes."
        onChange?()
    }

    func resetBaseline() {
        detector.reset()
        pending.removeAll()
    }

    private func setPermission(_ value: PermissionState) {
        if value != .ready {
            testGeneration += 1
            submittingTest = false
            testStatus = nil
        }
        let wasReady = permission == .ready
        permission = value
        if value == .ready && !wasReady {
            pending.forEach { center.deliver($0) }
            pending.removeAll()
        } else if value != .checking && value != .ready {
            pending.removeAll()
        }
        onChange?()
    }
}
