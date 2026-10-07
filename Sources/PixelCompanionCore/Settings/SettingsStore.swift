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
