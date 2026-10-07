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

struct PaperclipAgentResponse: Decodable, Sendable {
    let id: String
    let name: String
    let title: String?
    let status: String
    let lastHeartbeatAt: String?
    let updatedAt: String?
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
}
