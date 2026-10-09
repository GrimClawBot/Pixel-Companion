import Foundation
@testable import PixelCompanionCore
import XCTest

final class PaperclipRunHistoryMappingTests: XCTestCase {
    private let company = PaperclipCompany(id: "company", name: "QA", status: "active")

    private func input(
        agents: [String] = [
            #"{"id":"a","name":"Atlas","status":"idle"}"#,
            #"{"id":"b","name":"Emma","status":"idle"}"#
        ],
        runs: [String],
        issues: [String] = []
    ) throws -> PaperclipMappingInput {
        let decoder = JSONDecoder()
        return try PaperclipMappingInput(
            companies: [company], company: company,
            dashboard: .init(costs: .init(monthSpendCents: 0, monthBudgetCents: 0)),
            agents: agents.map { try decoder.decode(
                PaperclipAgentResponse.self, from: Data($0.utf8)
            ) },
            issues: issues.map { try decoder.decode(
                PaperclipIssueResponse.self, from: Data($0.utf8)
            ) },
            approvals: [],
            runs: runs.map { try decoder.decode(
                PaperclipHeartbeatRunResponse.self, from: Data($0.utf8)
            ) }
        )
    }

    private func agent(
        _ agentID: String, in input: PaperclipMappingInput
    ) throws -> AgentSessionSnapshot {
        try XCTUnwrap(PaperclipMapper.map(input).agentSessions.first { $0.agentID == agentID })
    }

    private func run(_ id: String, agent: String, time: Int) -> String {
        """
        {"id":"\(id)","agentId":"\(agent)","status":"completed",
         "updatedAt":"2026-10-07T\(String(format: "%02d", time)):00:00Z"}
        """
    }

    func testHistoryIsAgentIsolatedSortedAndCappedAtFive() throws {
        let runs = (1...9).map { run("a-\($0)", agent: "a", time: $0) }
            + [run("b-1", agent: "b", time: 10)]
        let input = try input(runs: runs)
        let atlas = try agent("a", in: input)
        let emma = try agent("b", in: input)

        XCTAssertEqual(atlas.recentRuns.map(\.id), ["a-9", "a-8", "a-7", "a-6", "a-5"])
        XCTAssertEqual(emma.recentRuns.map(\.id), ["b-1"])
        XCTAssertTrue(atlas.recentRuns.allSatisfy { $0.state == .completed })
    }

    func testDuplicateRunIDsCannotAppearTwice() throws {
        let input = try input(runs: [
            run("duplicate", agent: "a", time: 9),
            run("duplicate", agent: "a", time: 8),
            run("unique", agent: "a", time: 7)
        ])
        XCTAssertEqual(
            try agent("a", in: input).recentRuns.map(\.id),
            ["duplicate", "unique"]
        )
    }

    func testRunIssueIdAndUsageRemainReportedOnly() throws {
        let input = try input(
            runs: [
                """
                {"id":"attributed","agentId":"a","status":"running",
                 "contextSnapshot":{"issueId":"issue-1"},
                 "usageJson":{"model":"run-model","provider":"provider",
                  "inputTokens":450,"cachedInputTokens":30,"outputTokens":20},
                 "startedAt":"2026-10-07T08:00:00Z"}
                """,
                """
                {"id":"other","agentId":"b","status":"failed",
                 "contextSnapshot":{"issueId":"issue-1"}}
                """
            ],
            issues: [
                """
                {"id":"issue-1","identifier":"PX-22","title":"Ship card","status":"in_progress"}
                """
            ]
        )
        let run = try XCTUnwrap(agent("a", in: input).recentRuns.first)
        XCTAssertEqual(run.id, "attributed")
        XCTAssertEqual(run.taskTitle, "PX-22 · Ship card")
        XCTAssertEqual(run.issueID, "issue-1")
        XCTAssertEqual(run.model, "run-model")
        XCTAssertEqual(run.provider, "provider")
        XCTAssertEqual(run.inputTokens, 450)
        XCTAssertEqual(run.cachedInputTokens, 30)
        XCTAssertEqual(run.outputTokens, 20)
        XCTAssertEqual(run.state, .running)
        XCTAssertNotNil(run.startedAt)
        XCTAssertNil(run.finishedAt)
        XCTAssertEqual(try agent("b", in: input).recentRuns.first?.state, .failed)
    }

    func testMissingOrNegativeUsageStaysUnavailableAndUnknownNeverBecomesLive() throws {
        let input = try input(runs: [
            """
            {"id":"unknown","agentId":"a","status":"unknown",
             "usageJson":{"inputTokens":-1,"cachedInputTokens":-5,"outputTokens":-8}}
            """,
            #"{"id":"no-usage","agentId":"a","status":"completed"}"#
        ])
        let history = try agent("a", in: input).recentRuns
        let unconfirmed = try XCTUnwrap(history.first { $0.id == "unknown" })
        XCTAssertEqual(unconfirmed.state, .unknown)
        XCTAssertNil(unconfirmed.inputTokens)
        XCTAssertNil(unconfirmed.cachedInputTokens)
        XCTAssertNil(unconfirmed.outputTokens)
        XCTAssertNil(unconfirmed.updatedAt)
        let empty = try XCTUnwrap(history.first { $0.id == "no-usage" })
        XCTAssertNil(empty.taskTitle)
        XCTAssertNil(empty.issueID)
        XCTAssertNil(empty.model)
    }

    func testRawIssueIdRemainsAvailableEvenIfCurrentIssueIsNotInSample() throws {
        let value = try input(runs: [
            """
            {"id":"historical","agentId":"a","status":"completed",
             "contextSnapshot":{"issueId":"issue-outside-bounded-issues"}}
            """
        ])
        let evidence = try XCTUnwrap(agent("a", in: value).recentRuns.first)
        XCTAssertEqual(evidence.issueID, "issue-outside-bounded-issues")
        XCTAssertNil(evidence.taskTitle)
    }

    func testRunWithOnlyTitleLikeMetadataDoesNotInventIssueId() throws {
        let value = try input(runs: [
            """
            {"id":"not-associated","agentId":"a","status":"completed",
             "contextSnapshot":{"taskId":"issue-1"}}
            """
        ], issues: [
            #"{"id":"issue-1","title":"Same words","status":"done"}"#
        ])
        let evidence = try XCTUnwrap(agent("a", in: value).recentRuns.first)
        XCTAssertNil(evidence.issueID)
        XCTAssertNil(evidence.taskTitle)
    }

    func testNoRunsOrUnmatchedRunDoesNotInventHistory() throws {
        let empty = try agent("a", in: input(runs: []))
        XCTAssertTrue(empty.recentRuns.isEmpty)
        let foreign = try agent("a", in: input(runs: [
            run("foreign", agent: "not-enrolled", time: 1)
        ]))
        XCTAssertTrue(foreign.recentRuns.isEmpty)
    }
}
