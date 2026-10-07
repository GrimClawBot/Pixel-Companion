import Foundation

/// A connector the user can pick in settings.
public struct ConnectorOption: Identifiable, Hashable, Sendable {
    public let id: ConnectorID
    public let displayName: String
    public let summary: String

    public init(id: ConnectorID, displayName: String, summary: String) {
        self.id = id
        self.displayName = displayName
        self.summary = summary
    }
}

public extension ConnectorID {
    /// No connector at all; the app shows the offline character.
    static let disabled = ConnectorID(rawValue: "disabled")
    static let mockDemo = ConnectorID(rawValue: "mock.demo")
    static let mockQuiet = ConnectorID(rawValue: "mock.quiet")
    static let paperclip = ConnectorID(rawValue: "paperclip")
}

/// Every connector the app can create. Real connectors remain optional and use the same
/// read-only capability protocols as the mock implementations.
public enum ConnectorRegistry {
    public static let options: [ConnectorOption] = [
        ConnectorOption(id: .mockDemo, displayName: "Mock: demo loop", summary: "Cycles through every character state"),
        ConnectorOption(id: .mockQuiet, displayName: "Mock: quiet", summary: "Connected, nothing running"),
        ConnectorOption(id: .paperclip, displayName: "Paperclip", summary: "Read-only live agent runtime"),
        ConnectorOption(id: .disabled, displayName: "None", summary: "Run without a connector")
    ]

    public static let defaultID = ConnectorID.mockDemo

    /// Whether `id` is one of `options`.
    static func isRegistered(_ id: ConnectorID) -> Bool {
        options.contains { $0.id == id }
    }

    /// Builds the connector for `id`; `nil` for `.disabled` or an unknown identifier.
    public static func makeConnector(
        id: ConnectorID,
        connectionState: ConnectionState,
        paperclipConfiguration: PaperclipConfiguration = PaperclipConfiguration()
    ) -> (any Connector)? {
        switch id {
        case .mockDemo:
            return MockConnector(
                id: id, displayName: "Mock: demo loop", script: .demo, connectionState: connectionState
            )
        case .mockQuiet:
            return MockConnector(id: id, displayName: "Mock: quiet", script: .quiet, connectionState: connectionState)
        case .paperclip:
            return PaperclipConnector(configuration: paperclipConfiguration)
        default:
            return nil
        }
    }
}
