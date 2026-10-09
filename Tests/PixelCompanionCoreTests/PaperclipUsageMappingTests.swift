import Foundation
@testable import PixelCompanionCore
import XCTest

final class PaperclipUsageMappingTests: XCTestCase {
    private let company = PaperclipCompany(id: "qa", name: "Test", status: "active")
    private struct ContextVariant {
        let fields: String
        let used: Int?
        let window: Int?
    }

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

    func testMalformedOptionalContextCountsDoNotDropValidRun() throws {
        let agent = #"{"id":"a","name":"Test","status":"running"}"#
        let unusualUsage = """
        {"id":"valid-run","agentId":"a","status":"running",
         "usageJson":{"model":"runtime-model","provider":"runtime-provider",
                      "inputTokens":230,"cachedInputTokens":21,"outputTokens":55,
                      "contextUsedTokens":{"unexpected":"object"},
                      "contextWindowTokens":"not-an-int"}}
        """
        let decoded = try JSONDecoder().decode(
            PaperclipHeartbeatRunResponse.self, from: Data(unusualUsage.utf8)
        )
        XCTAssertEqual(decoded.id, "valid-run")
        XCTAssertEqual(decoded.status, "running")
        XCTAssertEqual(decoded.usageJson?.model, "runtime-model")
        XCTAssertEqual(decoded.usageJson?.inputTokens, 230)
        XCTAssertNil(decoded.usageJson?.contextUsedTokens)
        XCTAssertNil(decoded.usageJson?.contextWindowTokens)

        let session = try state(agent: agent, run: unusualUsage)
        XCTAssertEqual(session.runID, "valid-run")
        XCTAssertEqual(session.runState, .running)
        XCTAssertEqual(session.inputTokens, 230)
        XCTAssertEqual(session.cachedInputTokens, 21)
        XCTAssertEqual(session.outputTokens, 55)
        XCTAssertNil(session.contextUsedTokens)
        XCTAssertNil(session.contextWindowTokens)
    }

    func testMixedValidMalformedAndNullContextMetricsPreserveOtherCount() throws {
        let agent = #"{"id":"a","name":"Test","status":"running"}"#
        let variants: [ContextVariant] = [
            .init(fields: #""contextUsedTokens":"invalid","contextWindowTokens":8192"#,
                  used: nil, window: 8192),
            .init(fields: #""contextUsedTokens":1024,"contextWindowTokens":{"bad":true}"#,
                  used: 1024, window: nil),
            .init(fields: #""contextUsedTokens":null,"contextWindowTokens":8192"#,
                  used: nil, window: 8192),
            .init(fields: #""contextUsedTokens":1024,"contextWindowTokens":null"#,
                  used: 1024, window: nil)
        ]
        for variant in variants {
            let record = """
            {"id":"mixed-validity","agentId":"a","status":"running",
             "usageJson":{"inputTokens":230,"outputTokens":55,\(variant.fields)}}
            """
            let decoded = try JSONDecoder().decode(
                PaperclipHeartbeatRunResponse.self, from: Data(record.utf8)
            )
            XCTAssertEqual(decoded.id, "mixed-validity")
            XCTAssertEqual(decoded.usageJson?.inputTokens, 230)
            XCTAssertEqual(decoded.usageJson?.contextUsedTokens, variant.used)
            XCTAssertEqual(decoded.usageJson?.contextWindowTokens, variant.window)
            let mapped = try state(agent: agent, run: record)
            XCTAssertEqual(mapped.runID, "mixed-validity")
            XCTAssertEqual(mapped.inputTokens, 230)
            XCTAssertEqual(mapped.contextUsedTokens, variant.used)
            XCTAssertEqual(mapped.contextWindowTokens, variant.window)
        }
    }

    func testRequiredRunMetadataRemainsStrictWithMalformedContext() {
        let malformed = """
        {"id":"invalid","agentId":123,"status":"running",
         "usageJson":{"inputTokens":200,"contextUsedTokens":"bad"}}
        """
        XCTAssertThrowsError(
            try JSONDecoder().decode(PaperclipHeartbeatRunResponse.self, from: Data(malformed.utf8))
        )
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
