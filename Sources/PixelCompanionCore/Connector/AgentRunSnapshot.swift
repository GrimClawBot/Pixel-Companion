import Foundation

/// One verified recent Paperclip run, attributed by structured agentId.
/// Historical tasks are matched by the run's issueId to the current issue snapshot.
public struct AgentRunSnapshot: Identifiable, Hashable, Sendable {
    public let id: String
    public let state: AgentSessionSnapshot.RunState
    /// Structured issue ID reported on the run, not guessed from the title.
    public let issueID: String?
    public let taskTitle: String?
    public let model: String?
    public let provider: String?
    public let inputTokens: Int?
    public let cachedInputTokens: Int?
    public let outputTokens: Int?
    public let startedAt: Date?
    public let finishedAt: Date?
    public let updatedAt: Date?

    public init(
        id: String,
        state: AgentSessionSnapshot.RunState,
        issueID: String? = nil,
        taskTitle: String? = nil,
        model: String? = nil,
        provider: String? = nil,
        inputTokens: Int? = nil,
        cachedInputTokens: Int? = nil,
        outputTokens: Int? = nil,
        startedAt: Date? = nil,
        finishedAt: Date? = nil,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.state = state
        self.issueID = issueID
        self.taskTitle = taskTitle
        self.model = model
        self.provider = provider
        self.inputTokens = inputTokens
        self.cachedInputTokens = cachedInputTokens
        self.outputTokens = outputTokens
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.updatedAt = updatedAt
    }
}
