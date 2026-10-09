import Foundation

/// Atomically paired Paperclip presentation rows and refresh evidence.
public struct PaperclipPresentationCapture: Sendable {
    public let snapshot: ConnectorSnapshot
    public let coreAt: Date?
    public let sessionsAt: Date?
}
