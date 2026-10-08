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
    @Published private(set) var lastSuccessfulPaperclipSync: Date?
    @Published private(set) var activeMode: PresentationMode = .menuBar
    @Published private(set) var notchAvailable = false
    @Published private(set) var paperclipCompanies: [PaperclipCompany] = []

    /// Called after the user changes the presentation preference.
    var onPresentationPreferenceChange: (() -> Void)?

    private let settings: SettingsStore
    private var connector: (any Connector)?
    private var stateMachine = CharacterStateMachine()
    private var stepTimer: Timer?

    init(settings: SettingsStore) {
        self.settings = settings
    }

    deinit {
        stepTimer?.invalidate()
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

    func start() {
        rebuildConnector()
        scheduleStepTimer()
        if isPaperclipConnector { refreshConnector() }
    }

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
        let previousPaperclipCompanies = preservePaperclipCompanies ? paperclipCompanies : []
        let state = settings.mockConnectionState
        let configuration = PaperclipConfiguration(
            baseURLString: settings.paperclipBaseURL,
            companyID: settings.paperclipCompanyID
        )
        connector = ConnectorRegistry.makeConnector(
            id: settings.connectorID,
            connectionState: state,
            paperclipConfiguration: configuration
        )
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

    private func capture() {
        let next = ConnectorSnapshot(capturing: connector)
        if next != snapshot { snapshot = next }
        let syncDate = paperclipConnector?.lastSuccessfulRefreshAt
        if lastSuccessfulPaperclipSync != syncDate { lastSuccessfulPaperclipSync = syncDate }
        let health = FeedFreshness.evaluate(
            isPaperclip: isPaperclipConnector,
            state: next.connectionState,
            lastSuccess: syncDate
        )
        if feedFreshness != health { feedFreshness = health }
        _ = stateMachine.update(with: next)
        // A delayed Paperclip poll must not leave a misleading "working" mood.
        let nextMood: CharacterMood = health == .stale ? .offline : stateMachine.mood
        if mood != nextMood { mood = nextMood }
    }

    private func scheduleStepTimer() {
        stepTimer?.invalidate()
        let interval = isMockConnector ? settings.mockStepInterval : SettingsStore.paperclipRefreshInterval
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            // Scheduled on the main run loop below, so this always runs on the main thread.
            MainActor.assumeIsolated { self?.step() }
        }
        RunLoop.main.add(timer, forMode: .common)
        stepTimer = timer
    }
}
