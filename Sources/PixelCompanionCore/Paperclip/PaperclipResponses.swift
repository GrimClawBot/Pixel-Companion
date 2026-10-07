import Foundation

struct PaperclipHealthResponse: Decodable, Sendable {
    let status: String
}

struct PaperclipCompanyResponse: Decodable, Sendable {
    let id: String
    let name: String
    let status: String
}

struct PaperclipDashboardResponse: Decodable, Sendable {
    struct Costs: Decodable, Sendable {
        let monthSpendCents: Int
        let monthBudgetCents: Int
    }

    let costs: Costs
}

struct PaperclipAgentAdapterConfig: Decodable, Sendable {
    let model: String?
}

struct PaperclipAIConnectionResponse: Decodable, Sendable {
    let provider: String?
}

struct PaperclipAgentRuntimeConfig: Decodable, Sendable {
    let aiConnection: PaperclipAIConnectionResponse?
}

struct PaperclipAgentResponse: Sendable {
    let id: String
    let name: String
    let role: String?
    let title: String?
    let status: String
    let adapterType: String?
    let adapterConfig: PaperclipAgentAdapterConfig?
    let runtimeConfig: PaperclipAgentRuntimeConfig?
    let lastHeartbeatAt: String?
    let updatedAt: String?
}

extension PaperclipAgentResponse: Decodable {
    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case role
        case title
        case status
        case adapterType
        case adapterConfig
        case runtimeConfig
        case lastHeartbeatAt
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        status = try container.decode(String.self, forKey: .status)

        role = try? container.decode(String.self, forKey: .role)
        title = try? container.decode(String.self, forKey: .title)
        adapterType = try? container.decode(String.self, forKey: .adapterType)
        adapterConfig = try? container.decode(PaperclipAgentAdapterConfig.self, forKey: .adapterConfig)
        runtimeConfig = try? container.decode(PaperclipAgentRuntimeConfig.self, forKey: .runtimeConfig)
        lastHeartbeatAt = try? container.decode(String.self, forKey: .lastHeartbeatAt)
        updatedAt = try? container.decode(String.self, forKey: .updatedAt)
    }
}

struct PaperclipHeartbeatRunResponse: Decodable, Sendable {
    struct Usage: Decodable, Sendable {
        let model: String?
        let provider: String?
        let inputTokens: Int?
        let cachedInputTokens: Int?
        let outputTokens: Int?
        let persistedSessionId: String?
    }

    struct Context: Decodable, Sendable {
        let issueId: String?
        let taskId: String?
    }

    let id: String
    let agentId: String
    let status: String
    let startedAt: String?
    let finishedAt: String?
    let createdAt: String?
    let updatedAt: String?
    let usageJson: Usage?
    let sessionIdBefore: String?
    let sessionIdAfter: String?
    let contextSnapshot: Context?
}

struct PaperclipIssueResponse: Decodable, Sendable {
    let id: String
    let identifier: String?
    let title: String
    let status: String
    let assigneeAgentId: String?
    let lastActivityAt: String?
    let updatedAt: String?
    let createdAt: String?
}

struct PaperclipApprovalResponse: Decodable, Sendable {
    let id: String
    let title: String?
    let type: String?
    let status: String?
    let requestedAt: String?
    let createdAt: String?
}

struct PaperclipMappingInput {
    let companies: [PaperclipCompany]
    let company: PaperclipCompany
    let dashboard: PaperclipDashboardResponse
    let agents: [PaperclipAgentResponse]
    let issues: [PaperclipIssueResponse]
    let approvals: [PaperclipApprovalResponse]
    let runs: [PaperclipHeartbeatRunResponse]
}
