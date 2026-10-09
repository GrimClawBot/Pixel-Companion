import Foundation
import PixelCompanionCore
@testable import PixelCompanion
import XCTest

final class AgentsDirectoryFilterTests: XCTestCase {
    private func fixture(
        id: String,
        name: String,
        title: String? = nil,
        task: String? = nil,
        provider: String? = nil,
        model: String? = nil,
        status: AgentSessionSnapshot.RunState = .idle
    ) -> AgentSessionSnapshot {
        AgentSessionSnapshot(
            id: id, agentID: id, agentName: name,
            agentTitle: title, agentStatus: status.rawValue,
            runState: status, taskTitle: task,
            model: model, provider: provider
        )
    }

    func testSearchMatchesEverySupportedFieldIgnoringCaseAndAccents() {
        let values = [
            fixture(id: "1", name: "Émma", title: "Researcher", task: "Analyze evidence",
                    provider: "Anthropic", model: "Claude Opus", status: .running),
            fixture(id: "2", name: "Ethan", title: "Writer", task: "Draft script",
                    provider: "OpenAI", model: "GPT", status: .idle)
        ]
        for query in ["emma", "RESEARCH", "evidence", "ANTHROPIC", "opus", "live"] {
            XCTAssertEqual(
                AgentsDirectoryFilter.results(values, query: query, scope: .all, isLive: true).map(\.id),
                ["1"], query
            )
        }
        XCTAssertEqual(
            AgentsDirectoryFilter.results(values, query: "openai", scope: .all, isLive: true).map(\.id),
            ["2"]
        )
        XCTAssertTrue(
            AgentsDirectoryFilter.results(values, query: "unreported", scope: .all, isLive: true).isEmpty
        )
    }

    func testEmptyAndWhitespaceSearchReturnOriginalOrder() {
        let values = [
            fixture(id: "z", name: "Zeta"),
            fixture(id: "a", name: "Alpha"),
            fixture(id: "m", name: "Middle")
        ]
        for query in ["", "  ", "\n\t"] {
            XCTAssertEqual(
                AgentsDirectoryFilter.results(values, query: query, scope: .all, isLive: true).map(\.id),
                ["z", "a", "m"]
            )
        }
        XCTAssertEqual(
            AgentsDirectoryFilter.results(values, query: "a", scope: .all, isLive: true).map(\.id),
            ["z", "a"]
        )
    }

    func testSearchCombinesWithActiveFilterWithoutTreatingIdleAsActive() {
        let values = [
            fixture(id: "1", name: "Pixel", status: .idle),
            fixture(id: "2", name: "Pixel Alpha", status: .running),
            fixture(id: "3", name: "Pixel Beta", status: .queued),
            fixture(id: "4", name: "Pixel Gamma", status: .completed)
        ]
        XCTAssertEqual(
            AgentsDirectoryFilter.results(values, query: "pixel", scope: .active, isLive: true).map(\.id),
            ["2", "3"]
        )
        XCTAssertEqual(
            AgentsDirectoryFilter.results(values, query: "beta", scope: .active, isLive: true).map(\.id),
            ["3"]
        )
        XCTAssertTrue(
            AgentsDirectoryFilter.results(values, query: "gamma", scope: .active, isLive: true).isEmpty
        )
    }

    func testMissingOptionalValuesAndNoLiveFeedAreSafe() {
        let values = [fixture(id: "1", name: "Worker")]
        XCTAssertTrue(
            AgentsDirectoryFilter.results(values, query: "model", scope: .all, isLive: true).isEmpty
        )
        XCTAssertTrue(
            AgentsDirectoryFilter.results(values, query: "", scope: .all, isLive: false).isEmpty
        )
        XCTAssertTrue(
            AgentsDirectoryFilter.results(values, query: "worker", scope: .active, isLive: false).isEmpty
        )
    }

    func testDirectorySearchFindsAgentBeyond128Entries() {
        let agents = (0..<181).map {
            fixture(id: "agent-\($0)", name: "Member \($0)")
        }
        let results = AgentsDirectoryFilter.results(
            agents, query: "Member 180", scope: .all, isLive: true
        )
        XCTAssertEqual(results.map(\.agentID), ["agent-180"])
        XCTAssertEqual(
            AgentsDirectoryFilter.results(
                agents, query: "", scope: .all, isLive: true
            ).count,
            181
        )
    }

    func testEmptyMessagesDistinguishSearchAndConnectionStates() {
        XCTAssertTrue(
            AgentsDirectoryFilter.emptyMessage(total: 0, scope: .all, query: "", isLive: true)
                .contains("No agents")
        )
        XCTAssertTrue(
            AgentsDirectoryFilter.emptyMessage(total: 3, scope: .active, query: "", isLive: true)
                .contains("No active")
        )
        XCTAssertTrue(
            AgentsDirectoryFilter.emptyMessage(total: 3, scope: .all, query: "unknown", isLive: true)
                .contains("No agents match")
        )
        XCTAssertTrue(
            AgentsDirectoryFilter.emptyMessage(total: 3, scope: .all, query: "", isLive: false)
                .contains("unavailable")
        )
    }
}
