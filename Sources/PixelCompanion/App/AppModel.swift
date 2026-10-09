import Combine
import Foundation
import PixelCompanionCore

/// Single source of truth for the UI: owns the connector, steps it on a timer, and publishes the
/// latest snapshot and character mood. Settings are read and written through `SettingsStore`.
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var snapshot: ConnectorSnapshot = .noConnector
    @Published private(set) var mood: CharacterMood = .offline
    @Published private(set) var feedFreshness: FeedFreshness = .notApplicable
    @Published private(set) var agentFeedFreshness: FeedFreshness = .notApplicable
    @Published private(set) var lastSuccessfulPaperclipSync: Date?
    /// Transient navigation shared by the notch and the menu-bar fallback.
    /// Never persisted or sent to Paperclip.
    @Published var selectedDetailTab: CompanionDetailTab = .overview
    @Published private(set) var activeMode: PresentationMode = .menuBar
    @Published private(set) var notchAvailable = false
    @Published private(set) var paperclipCompanies: [PaperclipCompany] = []
    @Published private(set) var notificationStatus = ""
    @Published private(set) var notificationTestStatus: String?
    @Published private(set) var publicGitHubState: GitHubPublicState = .off
    let focusTimer = FocusTimerController()
    let batteryMonitor = BatteryPowerMonitor()
    let outputVolumeMonitor = OutputVolumeMonitor()
    let displayBrightnessMonitor = DisplayBrightnessMonitor()
    let downloadMonitor = DownloadProgressMonitor()
    let fileShelf = TransientFileShelf()
    let clipboardHistory = TransientClipboardHistory()
    let localAgentFeed = LocalAgentFeedMonitor()
    let codexProcessMonitor = CodexProcessMonitor()
    let codexTurnMonitor = CodexTurnMonitor()
    let claudeHookMonitor = ClaudeHookMonitor()
    let localActivityTimeline = LocalAgentActivityTimeline()
    let localAgentAttention = LocalAgentAttention()
    let calendarMonitor = CalendarNextEventMonitor()
    let musicMonitor = MusicNowPlayingMonitor()

    /// Called after the user changes the presentation preference.
    var onPresentationPreferenceChange: (() -> Void)?

    let settings: SettingsStore
    private let notificationManager: CompanionNotificationManager
    private let publicGitHubMonitor: PublicGitHubMonitor
    private let injectedPaperclipConnector: PaperclipConnector?
    private var publicGitHubSubscription: AnyCancellable?
    private var connector: (any Connector)?
    private var stateMachine = CharacterStateMachine()
    private var stepTimer: Timer?
    private var powerObserver: NSObjectProtocol?

    init(
        settings: SettingsStore,
        notificationManager: CompanionNotificationManager? = nil,
        publicGitHubMonitor: PublicGitHubMonitor? = nil,
        injectedPaperclipConnector: PaperclipConnector? = nil
    ) {
        self.settings = settings
        self.notificationManager = notificationManager ?? CompanionNotificationManager()
        self.publicGitHubMonitor = publicGitHubMonitor ?? PublicGitHubMonitor()
        self.injectedPaperclipConnector = injectedPaperclipConnector
        notificationStatus = self.notificationManager.statusText
        localActivityTimeline.bind(codex: codexTurnMonitor, claude: claudeHookMonitor)
        localAgentAttention.bind(timeline: localActivityTimeline) { [weak self] alert in
            self?.notificationManager.deliverLocalAgent(alert)
        }
        publicGitHubSubscription = self.publicGitHubMonitor.$state.sink { [weak self] next in
            self?.publicGitHubState = next
        }
        self.notificationManager.onChange = { [weak self] in
            guard let self else { return }
            self.notificationStatus = self.notificationManager.statusText
            self.notificationTestStatus = self.notificationManager.testStatus
        }
    }

    deinit {
        stepTimer?.invalidate()
        if let powerObserver {
            NotificationCenter.default.removeObserver(powerObserver)
        }
    }

    // MARK: Settings
    var connectorID: ConnectorID {
        get { settings.connectorID }
        set {
            guard newValue != settings.connectorID else { return }
            objectWillChange.send()
            settings.connectorID = newValue
            rebuildConnector()
            scheduleStepTimer()
            if isPaperclipConnector { refreshConnector() }
        }
    }

    var presentation: PresentationPreference {
        get { settings.presentation }
        set {
            guard newValue != settings.presentation else { return }
            objectWillChange.send()
            settings.presentation = newValue
            onPresentationPreferenceChange?()
        }
    }

    var mockConnectionState: ConnectionState {
        get { settings.mockConnectionState }
        set {
            guard newValue != settings.mockConnectionState else { return }
            objectWillChange.send()
            settings.mockConnectionState = newValue
            mockConnector?.simulatedConnectionState = newValue
            capture()
        }
    }

    var mockStepInterval: TimeInterval {
        get { settings.mockStepInterval }
        set {
            objectWillChange.send()
            settings.mockStepInterval = newValue
            if isMockConnector { scheduleStepTimer() }
        }
    }

    var notificationsEnabled: Bool {
        get { notificationManager.enabled }
        set {
            guard newValue != notificationManager.enabled else { return }
            objectWillChange.send()
            // Update the published snapshot from the latest atomic connector
            // evidence BEFORE enabling and establishing the notification baseline.
            // The previous UI snapshot may still show a run that ended while an
            // onChange callback was queued; that must not replay on opt-in.
            if newValue && isPaperclipConnector { capture() }
            notificationManager.setEnabled(newValue)
            notificationManager.observe(snapshot, isPaperclip: isPaperclipConnector)
        }
    }

    var notificationPermissionNeedsRequest: Bool {
        notificationManager.permission == .needsPermission
    }

    func requestNotificationPermission() {
        notificationManager.requestPermission()
    }

    var canSendTestNotification: Bool {
        notificationManager.canSendTest
    }

    func sendTestNotification() async {
        await notificationManager.sendTestNotification()
    }

    var canSimulateQAEvent: Bool {
        notificationManager.canSimulateQAEvent
    }

    func simulateQAEvent(_ scenario: CompanionQAScenario) {
        notificationManager.simulateQAEvent(scenario)
    }

    func refreshNotificationPermission() {
        notificationManager.refreshPermission()
    }

    var conserveEnergy: Bool {
        get { settings.conserveEnergy }
        set {
            guard newValue != settings.conserveEnergy else { return }
            objectWillChange.send()
            settings.conserveEnergy = newValue
            scheduleStepTimer()
        }
    }

    var githubPublicRepository: String { settings.githubPublicRepository }

    func applyGitHubPublicRepository(_ value: String) {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized != settings.githubPublicRepository else { return }
        settings.githubPublicRepository = normalized
        publicGitHubMonitor.configure(normalized)
    }

    var paperclipBaseURL: String { settings.paperclipBaseURL }

    func applyPaperclipBaseURL(_ newValue: String) {
        guard isPaperclipConnector else { return }
        let normalized = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let current = settings.paperclipBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized != current {
            objectWillChange.send()
            settings.paperclipBaseURL = normalized
            settings.paperclipCompanyID = ""
            paperclipCompanies = []
            rebuildConnector(preservePaperclipCompanies: false)
        }
        refreshConnector()
    }

    var paperclipCompanyID: String {
        get { settings.paperclipCompanyID }
        set {
            guard newValue != settings.paperclipCompanyID else { return }
            objectWillChange.send()
            settings.paperclipCompanyID = newValue
            if isPaperclipConnector {
                rebuildConnector(preservePaperclipCompanies: true)
                refreshConnector()
            }
        }
    }

    var isMockConnector: Bool { mockConnector != nil }
    var isPaperclipConnector: Bool { connectorID == .paperclip }

    func refreshConnector() {
        connector?.refresh()
        capture()
    }

    // MARK: Lifecycle
    /// Rewinds the mock script to its first step. Local only; nothing outside the app changes.
    func restartScript() {
        mockConnector?.reset()
        capture()
    }

    func updatePresentation(mode: PresentationMode, notchAvailable: Bool) {
        if activeMode != mode { activeMode = mode }
        if self.notchAvailable != notchAvailable { self.notchAvailable = notchAvailable }
    }

    // MARK: Private
    private var mockConnector: MockConnector? { connector as? MockConnector }
    private var paperclipConnector: PaperclipConnector? { connector as? PaperclipConnector }

    private func rebuildConnector(preservePaperclipCompanies: Bool = false) {
        notificationManager.resetBaseline()
        let previousPaperclipCompanies = preservePaperclipCompanies ? paperclipCompanies : []
        let state = settings.mockConnectionState
        let configuration = PaperclipConfiguration(
            baseURLString: settings.paperclipBaseURL,
            companyID: settings.paperclipCompanyID
        )
        if settings.connectorID == .paperclip, let injectedPaperclipConnector {
            connector = injectedPaperclipConnector
        } else {
            connector = ConnectorRegistry.makeConnector(
                id: settings.connectorID,
                connectionState: state,
                paperclipConfiguration: configuration
            )
        }
        if let paperclipConnector {
            paperclipCompanies = previousPaperclipCompanies
            paperclipConnector.onChange = { [weak self, weak paperclipConnector] in
                Task { @MainActor in
                    guard let self else { return }
                    self.paperclipCompanies = paperclipConnector?.availableCompanies ?? []
                    if self.settings.paperclipCompanyID.isEmpty,
                       let resolvedID = paperclipConnector?.resolvedCompanyID {
                        self.settings.paperclipCompanyID = resolvedID
                    }
                    self.capture()
                }
            }
        } else {
            paperclipCompanies = []
        }
        capture()
    }

    private func step() {
        connector?.refresh()
        capture()
    }

}

extension AppModel {
    private func capture() {
        // A Paperclip capture MUST bind session rows to their own timestamp.
        // Read both once under its lock; never recapture notifications separately.
        let paperclipCapture = paperclipConnector?.capturePresentation()
        var next = paperclipCapture?.snapshot
            ?? ConnectorSnapshot(capturing: connector, sessionLimit: Int.max)
        let syncDate = paperclipCapture?.coreAt
        if lastSuccessfulPaperclipSync != syncDate { lastSuccessfulPaperclipSync = syncDate }
        let health = FeedFreshness.evaluate(
            isPaperclip: isPaperclipConnector,
            state: next.connectionState,
            lastSuccess: syncDate
        )
        if feedFreshness != health { feedFreshness = health }
        let agentHealth = FeedFreshness.evaluate(
            isPaperclip: isPaperclipConnector,
            state: next.connectionState,
            lastSuccess: paperclipCapture?.sessionsAt
        )
        if agentFeedFreshness != agentHealth { agentFeedFreshness = agentHealth }
        // Never publish unverified agent rows to any UI or notification consumer.
        if !agentHealth.canPresentAsLive { next.agentSessions = [] }
        if next != snapshot { snapshot = next }
        _ = stateMachine.update(with: next)
        // A delayed Paperclip poll must not leave a misleading "working" mood.
        let nextMood: CharacterMood = health == .stale ? .offline : stateMachine.mood
        if mood != nextMood { mood = nextMood }
        notificationManager.observe(next, isPaperclip: isPaperclipConnector)
    }
}

extension AppModel {
    func start() {
        notificationManager.start()
        publicGitHubMonitor.configure(settings.githubPublicRepository)
        batteryMonitor.configure(enabled: settings.batteryHUDEnabled)
        outputVolumeMonitor.configure(enabled: settings.outputVolumeHUDEnabled)
        displayBrightnessMonitor.configure(enabled: settings.displayBrightnessHUDEnabled)
        downloadMonitor.configure(enabled: settings.downloadHUDEnabled)
        fileShelf.configure(enabled: settings.fileShelfEnabled)
        clipboardHistory.configure(enabled: settings.clipboardHistoryEnabled)
        localAgentFeed.configure(enabled: settings.localAgentFeedEnabled)
        codexProcessMonitor.configure(enabled: settings.codexPresenceEnabled)
        codexTurnMonitor.configure(enabled: settings.codexTurnEventsEnabled)
        claudeHookMonitor.configure(enabled: settings.claudeHookEventsEnabled)
        reconnectManagedAgentHooksIfEnabled()
        localAgentAttention.configureNotifications(enabled: settings.localAgentAlertsEnabled)
        calendarMonitor.configure(enabled: settings.calendarWidgetEnabled)
        musicMonitor.configure(enabled: settings.musicWidgetEnabled)
        rebuildConnector()
        if powerObserver == nil {
            powerObserver = NotificationCenter.default.addObserver(
                forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.scheduleStepTimer()
                    self?.batteryMonitor.refresh()
                }
            }
        }
        scheduleStepTimer()
        if isPaperclipConnector { refreshConnector() }
    }

    /// Called by macOS on wake; only requests existing read-only connector state.
    func didWake() {
        focusTimer.refresh()
        batteryMonitor.refresh()
        outputVolumeMonitor.refresh()
        displayBrightnessMonitor.refresh()
        downloadMonitor.refresh()
        localAgentFeed.refresh()
        codexProcessMonitor.refresh()
        codexTurnMonitor.refresh()
        claudeHookMonitor.refresh()
        calendarMonitor.refresh()
        musicMonitor.refresh()
        scheduleStepTimer()
        if isPaperclipConnector { refreshConnector() }
    }

    fileprivate func scheduleStepTimer() {
        stepTimer?.invalidate()
        let interval = CompanionRefreshCadence.interval(
            isMock: isMockConnector,
            mockInterval: settings.mockStepInterval,
            paperclipInterval: SettingsStore.paperclipRefreshInterval,
            conserveEnergy: settings.conserveEnergy,
            lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled
        )
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            // Scheduled on the main run loop below, so this always runs on the main thread.
            MainActor.assumeIsolated { self?.step() }
        }
        RunLoop.main.add(timer, forMode: .common)
        stepTimer = timer
    }
}
