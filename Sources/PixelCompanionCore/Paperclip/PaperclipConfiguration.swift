import Foundation

/// Non-secret connection metadata for a Paperclip server.
public struct PaperclipConfiguration: Equatable, Sendable {
    public var baseURLString: String
    public var companyID: String

    public init(baseURLString: String = "", companyID: String = "") {
        self.baseURLString = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        self.companyID = companyID.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var baseURL: URL? {
        guard !baseURLString.isEmpty else { return nil }
        guard var components = URLComponents(string: baseURLString) else { return nil }
        guard let scheme = components.scheme?.lowercased() else { return nil }
        guard ["http", "https"].contains(scheme), components.host?.isEmpty == false else { return nil }
        guard components.user == nil, components.password == nil else { return nil }
        guard components.query == nil, components.fragment == nil else { return nil }

        components.path = components.path.replacingOccurrences(
            of: "/+$",
            with: "",
            options: .regularExpression
        )
        return components.url
    }

    public var validationError: String? {
        if baseURLString.isEmpty { return nil }
        if baseURL == nil {
            return "Enter a valid http:// or https:// Paperclip base URL without credentials, query, or fragment."
        }
        return nil
    }
}

public struct PaperclipCompany: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let status: String

    public init(id: String, name: String, status: String) {
        self.id = id
        self.name = name
        self.status = status
    }
}

struct PaperclipRemoteState {
    let companies: [PaperclipCompany]
    let companyID: String?
    let companyName: String?
    let activity: [ActivityEvent]
    let approvals: [ApprovalRequest]
    let usage: UsageSnapshot?
}

enum PaperclipServiceError: LocalizedError {
    case invalidConfiguration
    case http(Int)
    case invalidResponse
    case companyNotFound

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            return "Paperclip connection settings are invalid."
        case let .http(status):
            return "Paperclip returned HTTP \(status)."
        case .invalidResponse:
            return "Paperclip returned an unreadable response."
        case .companyNotFound:
            return "The selected Paperclip company was not found."
        }
    }
}

protocol PaperclipServiceProtocol: AnyObject {
    func fetch(
        configuration: PaperclipConfiguration,
        completion: @escaping (Result<PaperclipRemoteState, Error>) -> Void
    )
}
