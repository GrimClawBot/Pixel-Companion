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
    var spentMonthlyCents: Int?
    var budgetMonthlyCents: Int?
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
        case spentMonthlyCents
        case budgetMonthlyCents
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
        spentMonthlyCents = try? container.decode(Int.self, forKey: .spentMonthlyCents)
        budgetMonthlyCents = try? container.decode(Int.self, forKey: .budgetMonthlyCents)
    }
}

struct PaperclipHeartbeatRunResponse: Decodable, Sendable {
    struct Usage: Decodable, Sendable {
        let model: String?
        let provider: String?
        let inputTokens: Int?
        let cachedInputTokens: Int?
        let outputTokens: Int?
        /// Optional, authoritative runtime context metrics; absent in many Paperclip installs.
        var contextUsedTokens: Int?
        var contextWindowTokens: Int?
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

// Only OPTIONAL context metrics may be soft-failed. All other usage
// fields retain Decodable's existing validation behavior, so a malformed
// required run or unrelated usage field cannot silently appear valid.
extension PaperclipHeartbeatRunResponse.Usage {
    private enum CodingKeys: String, CodingKey {
        case model
        case provider
        case inputTokens
        case cachedInputTokens
        case outputTokens
        case contextUsedTokens
        case contextWindowTokens
        case persistedSessionId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        model = try container.decodeIfPresent(String.self, forKey: .model)
        provider = try container.decodeIfPresent(String.self, forKey: .provider)
        inputTokens = try container.decodeIfPresent(Int.self, forKey: .inputTokens)
        cachedInputTokens = try container.decodeIfPresent(Int.self, forKey: .cachedInputTokens)
        outputTokens = try container.decodeIfPresent(Int.self, forKey: .outputTokens)
        // A third-party runtime may encode these optional metrics with an
        // incompatible type. Keep the run, omit only unreliable measurements.
        contextUsedTokens = try? container.decode(Int.self, forKey: .contextUsedTokens)
        contextWindowTokens = try? container.decode(Int.self, forKey: .contextWindowTokens)
        persistedSessionId = try container.decodeIfPresent(String.self, forKey: .persistedSessionId)
    }
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
