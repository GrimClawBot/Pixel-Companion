import Foundation

/// Where the companion lives.
public enum PresentationPreference: String, CaseIterable, Sendable {
    /// The notch when the active display has one, otherwise the menu bar.
    case automatic
    case notch
    case menuBar

    public var displayName: String {
        switch self {
        case .automatic: return "Automatic"
        case .notch: return "Notch"
        case .menuBar: return "Menu bar"
        }
    }
}

/// Local, `UserDefaults`-backed preferences. Holds no secrets: nothing here is sensitive.
public final class SettingsStore {
    public enum Key: String, CaseIterable {
        case connectorID = "pixelCompanion.connectorID"
        case presentation = "pixelCompanion.presentation"
        case mockConnectionState = "pixelCompanion.mockConnectionState"
        case mockStepInterval = "pixelCompanion.mockStepInterval"
        case paperclipBaseURL = "pixelCompanion.paperclipBaseURL"
        case paperclipCompanyID = "pixelCompanion.paperclipCompanyID"
        case githubPublicRepository = "pixelCompanion.githubPublicRepository"
        case conserveEnergy = "pixelCompanion.conserveEnergy"
        case focusTimerEnabled = "pixelCompanion.focusTimerEnabled"
        case batteryHUDEnabled = "pixelCompanion.batteryHUDEnabled"
        case outputVolumeHUDEnabled = "pixelCompanion.outputVolumeHUDEnabled"
        case displayBrightnessHUDEnabled = "pixelCompanion.displayBrightnessHUDEnabled"
        case downloadHUDEnabled = "pixelCompanion.downloadHUDEnabled"
        case fileShelfEnabled = "pixelCompanion.fileShelfEnabled"
        case calendarWidgetEnabled = "pixelCompanion.calendarWidgetEnabled"
        case calendarShowTitles = "pixelCompanion.calendarShowTitles"
        case musicWidgetEnabled = "pixelCompanion.musicWidgetEnabled"
        case musicShowTrackDetails = "pixelCompanion.musicShowTrackDetails"
    }

    public static let stepIntervalRange: ClosedRange<TimeInterval> = 1...30
    public static let defaultStepInterval: TimeInterval = 4
    public static let paperclipRefreshInterval: TimeInterval = 5

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The chosen connector. A stored identifier that is not in `ConnectorRegistry.options` (for
    /// example one written by a newer build, or a removed connector) reads as the default.
    public var connectorID: ConnectorID {
        get {
            guard
                let stored = defaults.string(forKey: Key.connectorID.rawValue).map(ConnectorID.init(rawValue:)),
                ConnectorRegistry.isRegistered(stored)
            else {
                return ConnectorRegistry.defaultID
            }
            return stored
        }
        set { defaults.set(newValue.rawValue, forKey: Key.connectorID.rawValue) }
    }

    public var presentation: PresentationPreference {
        get { enumValue(.presentation) ?? .automatic }
        set { defaults.set(newValue.rawValue, forKey: Key.presentation.rawValue) }
    }

    public var mockConnectionState: ConnectionState {
        get { enumValue(.mockConnectionState) ?? .connected }
        set { defaults.set(newValue.rawValue, forKey: Key.mockConnectionState.rawValue) }
    }

    /// Seconds between mock steps, clamped to `stepIntervalRange`.
    public var mockStepInterval: TimeInterval {
        get {
            guard let stored = defaults.object(forKey: Key.mockStepInterval.rawValue) as? Double else {
                return Self.defaultStepInterval
            }
            return Self.clampedInterval(stored)
        }
        set { defaults.set(Self.clampedInterval(newValue), forKey: Key.mockStepInterval.rawValue) }
    }

    /// Base URL for an optional Paperclip instance. This is connection metadata, not a secret.
    public var paperclipBaseURL: String {
        get { defaults.string(forKey: Key.paperclipBaseURL.rawValue) ?? "" }
        set {
            let value = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            defaults.set(value, forKey: Key.paperclipBaseURL.rawValue)
        }
    }

    /// Selected Paperclip company identifier. Empty means "discover companies first".
    public var paperclipCompanyID: String {
        get { defaults.string(forKey: Key.paperclipCompanyID.rawValue) ?? "" }
        set {
            let value = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            defaults.set(value, forKey: Key.paperclipCompanyID.rawValue)
        }
    }

    /// Optional public GitHub owner/repo; nonsecret and disconnected by default.
    public var githubPublicRepository: String {
        get { defaults.string(forKey: Key.githubPublicRepository.rawValue) ?? "" }
        set {
            defaults.set(
                newValue.trimmingCharacters(in: .whitespacesAndNewlines),
                forKey: Key.githubPublicRepository.rawValue
            )
        }
    }

    /// Default on: follow macOS Low Power Mode to reduce Paperclip polling.
    public var conserveEnergy: Bool {
        get { (defaults.object(forKey: Key.conserveEnergy.rawValue) as? Bool) ?? true }
        set { defaults.set(newValue, forKey: Key.conserveEnergy.rawValue) }
    }

    /// Standalone focus utility is disabled by default and holds no session data on disk.
    public var focusTimerEnabled: Bool {
        get { (defaults.object(forKey: Key.focusTimerEnabled.rawValue) as? Bool) ?? false }
        set { defaults.set(newValue, forKey: Key.focusTimerEnabled.rawValue) }
    }

    /// Purely local power-source indicator. Disabled unless explicitly enabled.
    public var batteryHUDEnabled: Bool {
        get { (defaults.object(forKey: Key.batteryHUDEnabled.rawValue) as? Bool) ?? false }
        set { defaults.set(newValue, forKey: Key.batteryHUDEnabled.rawValue) }
    }

    /// Read-only default output volume is disabled by default. No audio data is saved.
    public var outputVolumeHUDEnabled: Bool {
        get { (defaults.object(forKey: Key.outputVolumeHUDEnabled.rawValue) as? Bool) ?? false }
        set { defaults.set(newValue, forKey: Key.outputVolumeHUDEnabled.rawValue) }
    }

    /// Public IOKit display brightness read-only HUD, disabled by default.
    public var displayBrightnessHUDEnabled: Bool {
        get { (defaults.object(forKey: Key.displayBrightnessHUDEnabled.rawValue) as? Bool) ?? false }
        set { defaults.set(newValue, forKey: Key.displayBrightnessHUDEnabled.rawValue) }
    }

    /// Only registered, reviewed sources can supply download progress.
    public var downloadHUDEnabled: Bool {
        get { (defaults.object(forKey: Key.downloadHUDEnabled.rawValue) as? Bool) ?? false }
        set { defaults.set(newValue, forKey: Key.downloadHUDEnabled.rawValue) }
    }

    /// Explicitly selected ephemeral file references; never persisted.
    public var fileShelfEnabled: Bool {
        get { (defaults.object(forKey: Key.fileShelfEnabled.rawValue) as? Bool) ?? false }
        set { defaults.set(newValue, forKey: Key.fileShelfEnabled.rawValue) }
    }

    /// Calendar access itself is always controlled by macOS, never by a preference.
    public var calendarWidgetEnabled: Bool {
        get { (defaults.object(forKey: Key.calendarWidgetEnabled.rawValue) as? Bool) ?? false }
        set { defaults.set(newValue, forKey: Key.calendarWidgetEnabled.rawValue) }
    }

    /// Event titles are sensitive; show only after a separate explicit opt-in.
    public var calendarShowTitles: Bool {
        get { (defaults.object(forKey: Key.calendarShowTitles.rawValue) as? Bool) ?? false }
        set { defaults.set(newValue, forKey: Key.calendarShowTitles.rawValue) }
    }

    /// Music.app Automation requires a separate explicit Connect action.
    public var musicWidgetEnabled: Bool {
        get { (defaults.object(forKey: Key.musicWidgetEnabled.rawValue) as? Bool) ?? false }
        set { defaults.set(newValue, forKey: Key.musicWidgetEnabled.rawValue) }
    }

    /// Track details are sensitive and hidden until separately enabled.
    public var musicShowTrackDetails: Bool {
        get { (defaults.object(forKey: Key.musicShowTrackDetails.rawValue) as? Bool) ?? false }
        set { defaults.set(newValue, forKey: Key.musicShowTrackDetails.rawValue) }
    }

    /// Removes every stored preference so the defaults apply again.
    public func reset() {
        Key.allCases.forEach { defaults.removeObject(forKey: $0.rawValue) }
    }

    private func enumValue<Value: RawRepresentable>(_ key: Key) -> Value? where Value.RawValue == String {
        defaults.string(forKey: key.rawValue).flatMap(Value.init(rawValue:))
    }

    private static func clampedInterval(_ value: TimeInterval) -> TimeInterval {
        guard value.isFinite else { return defaultStepInterval }
        return min(max(value, stepIntervalRange.lowerBound), stepIntervalRange.upperBound)
    }
}
