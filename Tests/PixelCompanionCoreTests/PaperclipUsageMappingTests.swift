import Foundation
@testable import PixelCompanionCore
import XCTest

final class PaperclipUsageMappingTests: XCTestCase {
    private let company = PaperclipCompany(id: "qa", name: "Test", status: "active")

    private func state(agent: String, run: String? = nil) throws -> AgentSessionSnapshot {
        let agent = try JSONDecoder().decode(
            PaperclipAgentResponse.self, from: Data(agent.utf8)
        )
        let runs = try run.map {
            [try JSONDecoder().decode(PaperclipHeartbeatRunResponse.self, from: Data($0.utf8))]
        } ?? []
        let input = PaperclipMappingInput(
            companies: [company], company: company,
            dashboard: PaperclipDashboardResponse(
                costs: .init(monthSpendCents: 0, monthBudgetCents: 0)
            ),
            agents: [agent], issues: [], approvals: [], runs: runs
        )
        return try XCTUnwrap(PaperclipMapper.map(input).agentSessions.first)
    }

    func testLivePaperclipAgentMonthlyFieldsMapWithoutRun() throws {
        let agent = """
        {"id":"a","name":"Test","status":"idle",
         "spentMonthlyCents":2135,"budgetMonthlyCents":15000}
        """
        let session = try state(agent: agent)
        XCTAssertEqual(session.monthlySpendCents, 2135)
        XCTAssertEqual(session.monthlyBudgetCents, 15000)
        XCTAssertNil(session.inputTokens)
        XCTAssertNil(session.contextWindowTokens)
        XCTAssertNil(session.contextUsedTokens)
    }

    func testAbsentAndMalformedFieldsRemainUnavailable() throws {
        let missing = try state(agent: #"{"id":"a","name":"Test","status":"idle"}"#)
        XCTAssertNil(missing.monthlySpendCents)
        XCTAssertNil(missing.monthlyBudgetCents)

        let malformed = try state(
            agent: #"{"id":"a","name":"Test","status":"idle","spentMonthlyCents":"unknown","budgetMonthlyCents":-90}"#
        )
        XCTAssertNil(malformed.monthlySpendCents)
        XCTAssertNil(malformed.monthlyBudgetCents)
    }

    func testRunUsageMappingSupportsExplicitContextCountsOnly() throws {
        let agent = #"{"id":"a","name":"Test","status":"running","spentMonthlyCents":0}"#
        let withContext = """
        {"id":"run-a","agentId":"a","status":"running",
         "usageJson":{"model":"model-a","provider":"provider-a","inputTokens":210,
                      "cachedInputTokens":30,"outputTokens":50,
                      "contextUsedTokens":7000,"contextWindowTokens":8000}}
        """
        let session = try state(agent: agent, run: withContext)
        XCTAssertEqual(session.contextUsedTokens, 7000)
        XCTAssertEqual(session.contextWindowTokens, 8000)
        XCTAssertEqual(session.inputTokens, 210)
        XCTAssertEqual(session.cachedInputTokens, 30)
        XCTAssertEqual(session.monthlySpendCents, 0)

        let withoutContext = """
        {"id":"run-b","agentId":"a","status":"running",
         "usageJson":{"inputTokens":900,"outputTokens":100}}
        """
        let unknown = try state(agent: agent, run: withoutContext)
        XCTAssertNil(unknown.contextWindowTokens)
        XCTAssertNil(unknown.contextUsedTokens)
    }
}
