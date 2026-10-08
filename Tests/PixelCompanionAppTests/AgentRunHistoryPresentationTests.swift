import PixelCompanionCore
@testable import PixelCompanion
import XCTest

final class AgentRunHistoryPresentationTests: XCTestCase {
    func testReportedTokenCountsAreAccurateAndNoEstimatesAreAdded() {
        let known = AgentRunSnapshot(
            id: "run-1", state: .completed, inputTokens: 1200,
            cachedInputTokens: 400, outputTokens: 38
        )
        XCTAssertEqual(
            AgentRunHistoryPresentation.tokenLabel(known),
            "1,200 in · 400 cached · 38 out"
        )
        let unknown = AgentRunSnapshot(id: "run-2", state: .unknown)
        XCTAssertEqual(
            AgentRunHistoryPresentation.tokenLabel(unknown),
            "Run tokens not reported"
        )
    }

    func testUnknownRunIsNotPresentedAsActive() {
        XCTAssertEqual(AgentRunHistoryPresentation.stateLabel(.unknown), "Unconfirmed")
        XCTAssertEqual(AgentRunHistoryPresentation.stateLabel(.running), "Running")
        XCTAssertEqual(AgentRunHistoryPresentation.stateLabel(.queued), "Queued")
        XCTAssertEqual(AgentRunHistoryPresentation.stateLabel(.failed), "Failed")
        XCTAssertEqual(AgentRunHistoryPresentation.stateLabel(.completed), "Completed")
    }
}
