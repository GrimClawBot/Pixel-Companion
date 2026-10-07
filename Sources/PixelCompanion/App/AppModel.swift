import Combine
import Foundation
import PixelCompanionCore

/// Single source of truth for the UI: owns the connector, steps it on a timer, and publishes the
/// latest snapshot and character mood. Settings are read and written through `SettingsStore`.
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var snapshot: ConnectorSnapshot = .noConnector
    @Published private(set) var mood: CharacterMood = .offline
    @Published private(set) var activeMode: PresentationMode = .menuBar
    @Published private(set) var notchAvailable = false

    /// Called after the user changes the presentation preference.
    var onPresentationPreferenceChange: (() -> Void)?

    private let settings: SettingsStore
    private var connector: (any Connector)?
    private var stateMachine = CharacterStateMachine()
    private var stepTimer: Timer?

    init(settings: SettingsStore) {
        self.settings = settings
    }

    // MARK: Settings

    var connectorID: ConnectorID {
        get { settings.connectorID }
        set {
            guard newValue != settings.connectorID else { return }
            objectWillChange.send()
            settings.connectorID = newValue
            rebuildConnector()
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
            scheduleStepTimer()
        }
    }

    var isMockConnector: Bool { mockConnector != nil }

    // MARK: Lifecycle

    func start() {
        rebuildConnector()
        scheduleStepTimer()
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

    private func rebuildConnector() {
        let state = settings.mockConnectionState
        connector = ConnectorRegistry.makeConnector(id: settings.connectorID, connectionState: state)
        capture()
    }

    private func step() {
        connector?.refresh()
        capture()
    }

    private func capture() {
        let next = ConnectorSnapshot(capturing: connector)
        if next != snapshot { snapshot = next }
        if stateMachine.update(with: next) != nil { mood = stateMachine.mood }
    }

    private func scheduleStepTimer() {
        stepTimer?.invalidate()
        let timer = Timer(timeInterval: settings.mockStepInterval, repeats: true) { [weak self] _ in
            // Scheduled on the main run loop below, so this always runs on the main thread.
            MainActor.assumeIsolated { self?.step() }
        }
        RunLoop.main.add(timer, forMode: .common)
        stepTimer = timer
    }
}
