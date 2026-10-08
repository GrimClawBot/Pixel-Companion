import Foundation
import PixelCompanionCore
@testable import PixelCompanion
import XCTest

final class OperationalAttentionTests: XCTestCase {
    private func agent(
        _ name: String,
        state: AgentSessionSnapshot.RunState = .idle,
        spent: Int? = nil,
        budget: Int? = nil,
        used: Int? = nil,
        window: Int? = nil,
        inputTokens: Int? = nil
    ) -> AgentSessionSnapshot {
        AgentSessionSnapshot(
            id: "latest-\(name)", agentID: name, agentName: name,
            agentStatus: state.rawValue, runState: state,
            inputTokens: inputTokens,
            monthlySpendCents: spent, monthlyBudgetCents: budget,
            contextUsedTokens: used, contextWindowTokens: window
        )
    }

    private func signals(
        _ agents: [AgentSessionSnapshot], live: Bool = true
    ) -> [OperationalDiagnostic] {
        OperationalAttentionPresentation.diagnostics(agents, isLive: live)
    }

    func testFailedLatestRunIsARealCriticalDiagnosticWithoutInventingCause() throws {
        let items = signals([
            agent("atlas", state: .failed),
            agent("completed", state: .completed),
            agent("unknown", state: .unknown),
            agent("cancelled", state: .cancelled),
            agent("queued", state: .queued)
        ])
        let only = try XCTUnwrap(items.first)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(only.kind, .failedRun)
        XCTAssertEqual(only.severity, .critical)
        XCTAssertEqual(only.agentID, "atlas")
        XCTAssertTrue(only.detail.contains("Cause not reported"))
        XCTAssertEqual(only.id, "atlas:failedRun")
    }

    func testMonthlyBudgetUsesReportedValuesAndCorrectThresholds() throws {
        let items = signals([
            agent("below", spent: 799, budget: 1_000),
            agent("warning80", spent: 800, budget: 1_000),
            agent("warning90", spent: 900, budget: 1_000),
            agent("critical", spent: 1_500, budget: 1_000)
        ])
        XCTAssertEqual(items.map(\.agentID), ["critical", "warning80", "warning90"])
        XCTAssertEqual(items.map(\.kind), Array(repeating: .monthlyBudget, count: 3))
        XCTAssertEqual(items[0].severity, .critical)
        XCTAssertEqual(items[1].severity, .warning)
        XCTAssertEqual(items[2].severity, .warning)
        XCTAssertTrue(items[0].title.contains("reached"))
        XCTAssertTrue(items[2].detail.contains("90%"))
    }

    func testContextWindowRequiresRealValidOccupancy() {
        let items = signals([
            agent("80", used: 800, window: 1_000),
            agent("90", used: 900, window: 1_000),
            agent("100", used: 1_000, window: 1_000),
            agent("invalid", used: 1_500, window: 1_000),
            agent("no-window", used: nil, window: nil, inputTokens: 950_000),
            agent("negative", used: -1, window: 1_000),
            agent("zero-window", used: 100, window: 0),
            agent("below", used: 799, window: 1_000)
        ])
        XCTAssertEqual(items.map(\.agentID), ["90", "100", "80"])
        XCTAssertEqual(items.map(\.severity), [.critical, .critical, .warning])
        XCTAssertTrue(items.allSatisfy { $0.kind == .contextWindow })
        XCTAssertTrue(items[0].detail.contains("90%"))
        XCTAssertTrue(items[1].detail.contains("100%"))
    }

    func testDeduplicationUsesStableAgentAndDiagnosticType() {
        let duplicated = agent("same", state: .failed, spent: 2_000, budget: 1_000)
        let items = signals([duplicated, duplicated])
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(Set(items.map(\.id)).count, 2)
        XCTAssertEqual(items.map(\.kind), [.failedRun, .monthlyBudget])
    }

    func testSeverityOrderingAndCappedPreviewAreStable() {
        let agents = [
            agent("warning-a", spent: 850, budget: 1_000),
            agent("fail", state: .failed),
            agent("critical-budget", spent: 1_000, budget: 1_000),
            agent("warning-b", used: 850, window: 1_000),
            agent("critical-context", used: 910, window: 1_000),
            agent("warning-c", spent: 810, budget: 1_000)
        ]
        let items = signals(agents)
        XCTAssertEqual(
            items.map(\.agentID),
            ["fail", "critical-budget", "critical-context", "warning-a", "warning-b", "warning-c"]
        )
        XCTAssertEqual(OperationalAttentionPresentation.preview(items).map(\.agentID),
                       ["fail", "critical-budget", "critical-context", "warning-a"])
        XCTAssertEqual(OperationalAttentionPresentation.previewLimit, 4)
        XCTAssertEqual(items.count, 6)
    }

    func testStaleAndDisconnectedSuppressAllLiveDiagnostics() {
        let data = [agent("atlas", state: .failed, spent: 1_000, budget: 1_000)]
        XCTAssertEqual(signals(data).count, 2)
        XCTAssertTrue(signals(data, live: false).isEmpty)
        XCTAssertTrue(signals([]).isEmpty)
    }

    func testZeroOrMissingBudgetDoesNotCreateFalseFinancialWarning() {
        let data = [
            agent("zero", spent: 1_000, budget: 0),
            agent("unreported", spent: nil, budget: 1_000),
            agent("negative", spent: -1, budget: 1_000)
        ]
        XCTAssertTrue(signals(data).isEmpty)
    }
}
