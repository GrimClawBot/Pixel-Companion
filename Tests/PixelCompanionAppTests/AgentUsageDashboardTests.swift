import Foundation
import PixelCompanionCore
@testable import PixelCompanion
import XCTest

final class AgentUsageDashboardTests: XCTestCase {
    private func fixture(
        spend: Int? = nil, budget: Int? = nil, used: Int? = nil, window: Int? = nil
    ) -> AgentSessionSnapshot {
        AgentSessionSnapshot(
            id: "test", agentID: "agent", agentName: "Worker",
            agentStatus: "idle", runState: .idle,
            monthlySpendCents: spend, monthlyBudgetCents: budget,
            contextUsedTokens: used, contextWindowTokens: window
        )
    }

    func testMissingMetricsCannotLookLikeZeroOrAContextWarning() {
        let session = fixture()
        XCTAssertEqual(AgentUsagePresentation.runTokens(session), "Run tokens not reported")
        XCTAssertEqual(AgentUsagePresentation.monthlySpend(session), "Monthly spend not reported")
        XCTAssertEqual(AgentUsagePresentation.monthlyBudget(session), "Monthly budget not reported")
        XCTAssertNil(AgentUsagePresentation.contextFraction(session))
        XCTAssertNil(AgentUsagePresentation.contextWarning(session))
        XCTAssertTrue(AgentUsagePresentation.contextLabel(session).contains("unavailable"))
    }

    func testMonthlyAgentSpendUsesExactReportedCentsNotRunTokenCost() {
        let sample = fixture(spend: 1234, budget: 5000)
        XCTAssertEqual(AgentUsagePresentation.monthlySpend(sample), "Spent this month · $12.34")
        XCTAssertEqual(AgentUsagePresentation.monthlyBudget(sample), "Monthly budget · $50.00")
        XCTAssertEqual(AgentUsagePresentation.monthlySpend(fixture(spend: 0)), "Spent this month · $0.00")
        XCTAssertEqual(AgentUsagePresentation.monthlyBudget(fixture(budget: 0)), "No monthly budget set")
    }

    func testContextFractionOnlyWhenBothAuthoritativeCountsValid() {
        XCTAssertEqual(AgentUsagePresentation.contextFraction(fixture(used: 5000, window: 10000)), 0.5)
        XCTAssertNil(AgentUsagePresentation.contextFraction(fixture(used: 5)))
        XCTAssertNil(AgentUsagePresentation.contextFraction(fixture(window: 10000)))
        XCTAssertNil(AgentUsagePresentation.contextFraction(fixture(used: 1, window: 0)))
        XCTAssertNil(AgentUsagePresentation.contextFraction(fixture(used: 11, window: 10)))
        XCTAssertNil(AgentUsagePresentation.contextFraction(fixture(used: -1, window: 10)))
    }

    func testContextWarningsHaveRealThresholdsAndNoGuessing() {
        XCTAssertNil(AgentUsagePresentation.contextWarning(fixture(used: 7999, window: 10000)))
        XCTAssertTrue(
            AgentUsagePresentation.contextWarning(fixture(used: 8000, window: 10000))?.contains("80%") == true
        )
        XCTAssertTrue(
            AgentUsagePresentation.contextWarning(fixture(used: 9000, window: 10000))?.contains("nearly full") == true
        )
        XCTAssertNil(AgentUsagePresentation.contextWarning(fixture(used: 9000)))
    }

    func testReportedRunTokenCountsNotBlendedWithMonthlySpend() {
        let sample = AgentSessionSnapshot(
            id: "a", agentID: "a", agentName: "Worker",
            agentStatus: "running", runState: .running,
            inputTokens: 1200, cachedInputTokens: 800, outputTokens: 250,
            monthlySpendCents: 199
        )
        let line = AgentUsagePresentation.runTokens(sample)
        XCTAssertTrue(line.contains("1.2K in"))
        XCTAssertTrue(line.contains("800 cached"))
        XCTAssertTrue(line.contains("250 out"))
        XCTAssertEqual(AgentUsagePresentation.monthlySpend(sample), "Spent this month · $1.99")
        XCTAssertNil(AgentUsagePresentation.contextFraction(sample))
    }
}

extension AgentUsageDashboardTests {
    func testActiveFilterPreservesSessionOrderAndAllItems() {
        let idle = AgentSessionSnapshot(
            id: "idle", agentID: "a", agentName: "Idle",
            agentStatus: "idle", runState: .idle
        )
        let running = AgentSessionSnapshot(
            id: "running", agentID: "b", agentName: "Working",
            agentStatus: "running", runState: .running
        )
        let queued = AgentSessionSnapshot(
            id: "queued", agentID: "c", agentName: "Queued",
            agentStatus: "queued", runState: .queued
        )
        let all = [idle, running, queued]
        XCTAssertEqual(AgentUsageScope.all.sessions(all).map(\.id), ["idle", "running", "queued"])
        XCTAssertEqual(AgentUsageScope.active.sessions(all).map(\.id), ["running", "queued"])
        XCTAssertTrue(AgentUsageScope.active.sessions([idle]).isEmpty)
    }

    func testMonthlyBudgetProgressUsesOnlyRealMonthlyNumbers() {
        XCTAssertNil(AgentUsagePresentation.monthlyBudgetFraction(fixture()))
        XCTAssertNil(AgentUsagePresentation.monthlyBudgetFraction(fixture(spend: 500)))
        XCTAssertNil(AgentUsagePresentation.monthlyBudgetFraction(fixture(budget: 1000)))
        XCTAssertNil(AgentUsagePresentation.monthlyBudgetFraction(fixture(spend: 500, budget: 0)))
        XCTAssertNil(AgentUsagePresentation.monthlyBudgetFraction(fixture(spend: -1, budget: 1000)))
        XCTAssertEqual(AgentUsagePresentation.monthlyBudgetFraction(fixture(spend: 200, budget: 1000)), 0.2)
        XCTAssertEqual(AgentUsagePresentation.monthlyBudgetFraction(fixture(spend: 1200, budget: 1000)), 1.2)
    }

    func testMonthlyBudgetWarningThresholdsStaySeparateFromContext() {
        XCTAssertNil(AgentUsagePresentation.monthlyBudgetWarning(fixture(spend: 799, budget: 1000)))
        XCTAssertTrue(
            AgentUsagePresentation.monthlyBudgetWarning(fixture(spend: 800, budget: 1000))?.contains("80%") == true
        )
        XCTAssertTrue(
            AgentUsagePresentation.monthlyBudgetWarning(fixture(spend: 900, budget: 1000))?.contains("90%") == true
        )
        XCTAssertTrue(
            AgentUsagePresentation.monthlyBudgetWarning(fixture(spend: 1000, budget: 1000))?.contains("reached") == true
        )
        XCTAssertTrue(
            AgentUsagePresentation.monthlyBudgetWarning(fixture(spend: 1200, budget: 1000))?.contains("reached") == true
        )
        XCTAssertNil(AgentUsagePresentation.contextWarning(fixture(spend: 1200, budget: 1000)))
    }
}
