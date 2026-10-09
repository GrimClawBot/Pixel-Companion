import Combine
import Foundation
@testable import PixelCompanion
@testable import PixelCompanionCore
import XCTest

private final class ControlledPaperclipService: PaperclipServiceProtocol {
    private(set) var fetchCount = 0
    private var cores: [Int: (Result<PaperclipRemoteState, Error>) -> Void] = [:]
    private var sessions: [Int: (Result<[AgentSessionSnapshot], Error>) -> Void] = [:]

    func fetch(
        configuration: PaperclipConfiguration,
        completion: @escaping (Result<PaperclipRemoteState, Error>) -> Void,
        sessionCompletion: @escaping (Result<[AgentSessionSnapshot], Error>) -> Void
    ) {
        fetchCount += 1
        cores[fetchCount] = completion
        sessions[fetchCount] = sessionCompletion
    }

    func core(_ value: PaperclipRemoteState, fetch: Int) {
        cores.removeValue(forKey: fetch)?(.success(value))
    }

    func sessions(_ value: [AgentSessionSnapshot], fetch: Int) {
        sessions.removeValue(forKey: fetch)?(.success(value))
    }

    func failSessions(fetch: Int) {
        sessions.removeValue(forKey: fetch)?(.failure(URLError(.timedOut)))
    }
}

@MainActor
final class AppModelPaperclipEvidenceTests: XCTestCase {
    private final class RecordingCenter: CompanionNoticeCenter {
        var notices: [CompanionNotice] = []
        func authorization() async -> CompanionAuthorization { .authorized }
        func requestPermission() async -> Bool { true }
        func deliver(_ notice: CompanionNotice) { notices.append(notice) }
        func submitTest() async throws {}
    }

    private struct Fixture {
        let model: AppModel
        let connector: PaperclipConnector
        let service: ControlledPaperclipService
        let center: RecordingCenter
        let defaults: UserDefaults
        let suite: String
    }

    private func fixture(notifications: Bool = false) -> Fixture {
        let name = "PC062-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        defaults.set(notifications, forKey: "pixelCompanion.notificationsEnabled")
        let settings = SettingsStore(defaults: defaults)
        settings.connectorID = .paperclip
        settings.paperclipBaseURL = "https://paperclip.test.invalid"
        settings.paperclipCompanyID = "qa"
        let center = RecordingCenter()
        let service = ControlledPaperclipService()
        let connector = PaperclipConnector(
            configuration: PaperclipConfiguration(
                baseURLString: "https://paperclip.test.invalid", companyID: "qa"
            ), service: service
        )
        let manager = CompanionNotificationManager(
            defaults: defaults, center: center, isBundled: true, isQABuild: false
        )
        let model = AppModel(
            settings: settings,
            notificationManager: manager,
            injectedPaperclipConnector: connector
        )
        model.start()
        return Fixture(
            model: model, connector: connector, service: service,
            center: center, defaults: defaults, suite: name
        )
    }

    private func core(approvals: Int = 1) -> PaperclipRemoteState {
        PaperclipRemoteState(
            companies: [PaperclipCompany(id: "qa", name: "Test Co", status: "active")],
            companyID: "qa", companyName: "Test Co", activity: [],
            approvals: (0..<approvals).map {
                ApprovalRequest(id: "approval-\($0)", title: "Private", requestedAt: Date())
            },
            usage: nil, agentSessions: [],
            tasks: [TaskSnapshot(id: "task", title: "Private task", status: "todo")]
        )
    }

    private func agent(_ id: String, state: AgentSessionSnapshot.RunState = .running) -> AgentSessionSnapshot {
        AgentSessionSnapshot(
            id: id, agentID: id, agentName: "Private agent",
            agentStatus: state.rawValue, runID: id + "-run", runState: state
        )
    }

    private func waitForNotificationPermissionReady(_ model: AppModel) async {
        let ready = expectation(description: "Notification permission confirmed ready")
        // A real publisher signal is more reliable than N Task.yield calls:
        // queued main-actor permission tasks may finish after an arbitrary
        // number of yields on loaded CI machines.
        let observation = model.$notificationStatus.sink { status in
            if status == "Enabled for new Paperclip events." {
                ready.fulfill()
            }
        }
        await fulfillment(of: [ready], timeout: 5)
        observation.cancel()
    }

    func testActualAppModelCapturesAll181AgentsWithoutOldDirectoryLimit() {
        let fixtureState = fixture()
        defer { fixtureState.defaults.removePersistentDomain(forName: fixtureState.suite) }
        XCTAssertEqual(fixtureState.service.fetchCount, 1)
        fixtureState.service.core(core(), fetch: 1)
        let all = (0..<181).map { agent("agent-\($0)") }
        fixtureState.service.sessions(all, fetch: 1)
        fixtureState.model.refreshConnector()
        XCTAssertEqual(fixtureState.model.agentFeedFreshness, .current)
        XCTAssertEqual(fixtureState.model.snapshot.agentSessions.count, 181)
        XCTAssertEqual(fixtureState.model.snapshot.agentSessions.last?.agentID, "agent-180")
        XCTAssertEqual(fixtureState.model.snapshot.pendingApprovals.count, 1)
        XCTAssertEqual(fixtureState.model.snapshot.tasks.count, 1)
    }

    func testActualAppModelGatesStaleSessionsAndRetainsFreshCoreData() {
        let fixtureState = fixture()
        defer { fixtureState.defaults.removePersistentDomain(forName: fixtureState.suite) }
        fixtureState.service.core(core(), fetch: 1)
        fixtureState.model.refreshConnector()
        XCTAssertEqual(fixtureState.model.feedFreshness, .current)
        XCTAssertEqual(fixtureState.model.agentFeedFreshness, .connecting)
        XCTAssertEqual(fixtureState.model.snapshot.agentSessions.count, 0)
        XCTAssertEqual(fixtureState.model.snapshot.pendingApprovals.count, 1)
        XCTAssertEqual(fixtureState.model.snapshot.tasks.count, 1)
        fixtureState.service.sessions([agent("ready")], fetch: 1)
        fixtureState.model.refreshConnector()
        XCTAssertEqual(fixtureState.model.agentFeedFreshness, .current)
        XCTAssertEqual(fixtureState.model.snapshot.agentSessions.map(\.agentID), ["ready"])
        // Session failure does not make independently fresh core tasks disappear.
        fixtureState.service.core(core(approvals: 2), fetch: 2)
        fixtureState.service.failSessions(fetch: 2)
        fixtureState.model.refreshConnector()
        XCTAssertEqual(fixtureState.model.feedFreshness, .current)
        XCTAssertFalse(fixtureState.model.agentFeedFreshness.canPresentAsLive)
        XCTAssertTrue(fixtureState.model.snapshot.agentSessions.isEmpty)
        XCTAssertEqual(fixtureState.model.snapshot.pendingApprovals.count, 2)
        XCTAssertEqual(fixtureState.model.snapshot.tasks.count, 1)
    }

    func testActualAppModelNotificationsDoNotConsumeUnverifiedRuns() async {
        let fixtureState = fixture(notifications: true)
        defer { fixtureState.defaults.removePersistentDomain(forName: fixtureState.suite) }
        await waitForNotificationPermissionReady(fixtureState.model)
        fixtureState.service.core(core(), fetch: 1)
        fixtureState.model.refreshConnector()
        XCTAssertTrue(fixtureState.model.snapshot.agentSessions.isEmpty)
        fixtureState.service.sessions([agent("observed")], fetch: 1)
        fixtureState.model.refreshConnector()
        XCTAssertEqual(fixtureState.model.snapshot.agentSessions.count, 1)
        fixtureState.service.core(core(), fetch: 2)
        fixtureState.service.failSessions(fetch: 2)
        fixtureState.model.refreshConnector()
        XCTAssertTrue(fixtureState.model.snapshot.agentSessions.isEmpty)
        XCTAssertFalse(fixtureState.center.notices.contains(.completedRuns(1)))
        XCTAssertFalse(fixtureState.center.notices.contains(.failedRuns(1)))

        // Recovery with a different observed run is eligible for one
        // completion notice after it was actually observed active.
        fixtureState.service.core(core(), fetch: 3)
        fixtureState.service.sessions([agent("new")], fetch: 3)
        fixtureState.model.refreshConnector()
        XCTAssertEqual(fixtureState.model.snapshot.agentSessions.map(\.agentID), ["new"])
        fixtureState.service.core(core(), fetch: 4)
        fixtureState.service.sessions([agent("new", state: .completed)], fetch: 4)
        fixtureState.model.refreshConnector()
        XCTAssertEqual(fixtureState.model.snapshot.agentSessions.first?.runState, .completed)
        fixtureState.model.refreshConnector()
        XCTAssertEqual(
            fixtureState.center.notices.filter { $0 == .completedRuns(1) }.count, 1
        )
    }

    func testOptInAfterRunAlreadyFinishedDoesNotReplayOldCompletion() async {
        let fixtureState = fixture(notifications: false)
        defer { fixtureState.defaults.removePersistentDomain(forName: fixtureState.suite) }

        fixtureState.service.core(core(), fetch: 1)
        fixtureState.service.sessions([agent("old")], fetch: 1)
        fixtureState.model.refreshConnector()
        XCTAssertEqual(fixtureState.model.snapshot.agentSessions.first?.runState, .running)

        // An old run completes in the connector while AppModel has not yet
        // received the queued onChange publication. Toggling alerts now
        // MUST baseline the terminal state, never the old published running row.
        fixtureState.service.core(core(), fetch: 2)
        fixtureState.service.sessions([agent("old", state: .completed)], fetch: 2)
        XCTAssertEqual(fixtureState.model.snapshot.agentSessions.first?.runState, .running)
        XCTAssertEqual(
            fixtureState.connector.capturePresentation().snapshot.agentSessions.first?.runState,
            .completed
        )

        fixtureState.model.notificationsEnabled = true
        XCTAssertEqual(fixtureState.model.snapshot.agentSessions.first?.runState, .completed)
        await waitForNotificationPermissionReady(fixtureState.model)
        fixtureState.model.refreshConnector()
        XCTAssertFalse(fixtureState.center.notices.contains(.completedRuns(1)))
        XCTAssertFalse(fixtureState.center.notices.contains(.failedRuns(1)))

        // A new run observed only AFTER opting in may notify once.
        fixtureState.service.core(core(), fetch: 3)
        fixtureState.service.sessions([agent("new")], fetch: 3)
        fixtureState.model.refreshConnector()
        fixtureState.service.core(core(), fetch: 4)
        fixtureState.service.sessions([agent("new", state: .completed)], fetch: 4)
        fixtureState.model.refreshConnector()
        fixtureState.model.refreshConnector()
        XCTAssertEqual(
            fixtureState.center.notices.filter { $0 == .completedRuns(1) }.count, 1
        )
    }

    func testNotificationOptOutDoesNotGenerateRunAlertsOnActualAppModel() {
        let fixtureState = fixture(notifications: false)
        defer { fixtureState.defaults.removePersistentDomain(forName: fixtureState.suite) }
        fixtureState.service.core(core(), fetch: 1)
        fixtureState.service.sessions([agent("observed")], fetch: 1)
        fixtureState.model.refreshConnector()
        fixtureState.service.core(core(), fetch: 2)
        fixtureState.service.sessions([agent("observed", state: .completed)], fetch: 2)
        fixtureState.model.refreshConnector()
        XCTAssertEqual(fixtureState.model.snapshot.agentSessions.first?.runState, .completed)
        XCTAssertTrue(fixtureState.center.notices.isEmpty)
    }
}
