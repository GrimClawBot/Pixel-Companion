import PixelCompanionCore
import XCTest

final class MockConnectorTests: XCTestCase {
    private func makeConnector(_ script: MockScript = .demo, state: ConnectionState = .connected) -> MockConnector {
        MockConnector(id: .mockDemo, displayName: "Mock", script: script, connectionState: state)
    }

    func testStartsAtFirstStep() {
        let connector = makeConnector()

        XCTAssertEqual(connector.tick, 0)
        XCTAssertEqual(connector.currentActivity?.title, MockScript.demo.steps[0].title)
        XCTAssertEqual(connector.currentActivity?.timestamp, MockScript.referenceDate)
    }

    func testRefreshAdvancesOnlyWhileConnected() {
        let connector = makeConnector()
        connector.refresh()
        XCTAssertEqual(connector.tick, 1)

        for state in [ConnectionState.connecting, .disconnected, .error] {
            connector.simulatedConnectionState = state
            connector.refresh()
            XCTAssertEqual(connector.tick, 1, "\(state) must freeze the script")
        }
    }

    func testReplayIsDeterministic() {
        let first = makeConnector()
        let second = makeConnector()
        for _ in 0..<20 {
            first.refresh()
            second.refresh()
            XCTAssertEqual(ConnectorSnapshot(capturing: first), ConnectorSnapshot(capturing: second))
        }
    }

    func testScriptLoopsAndTimestampsKeepGrowing() {
        let script = MockScript.demo
        let connector = makeConnector()
        connector.advance(by: script.steps.count)

        XCTAssertEqual(connector.currentStep, script.steps[0])
        XCTAssertEqual(
            connector.currentActivity?.timestamp,
            script.startDate.addingTimeInterval(Double(script.steps.count) * script.stepInterval)
        )
        XCTAssertEqual(connector.currentActivity?.id, "mock-\(script.steps.count)")
    }

    func testRecentActivityIsNewestFirstAndLimited() {
        let connector = makeConnector()
        connector.advance(by: 5)

        let events = connector.recentActivity(limit: 3)
        XCTAssertEqual(events.map(\.id), ["mock-5", "mock-4", "mock-3"])
        XCTAssertEqual(connector.recentActivity(limit: 50).count, 6)
        XCTAssertTrue(connector.recentActivity(limit: 0).isEmpty)
    }

    func testApprovalsFollowTheCurrentStep() throws {
        let script = MockScript.demo
        let approvalStep = try XCTUnwrap(script.steps.firstIndex { !$0.pendingApprovals.isEmpty })
        let connector = makeConnector()
        XCTAssertTrue(connector.pendingApprovals().isEmpty)

        connector.advance(by: approvalStep)
        XCTAssertEqual(connector.pendingApprovals().map(\.title), script.steps[approvalStep].pendingApprovals)

        connector.advance()
        XCTAssertEqual(connector.pendingApprovals().map(\.title), script.steps[approvalStep + 1].pendingApprovals)
    }

    func testUsageComesFromTheScript() {
        let connector = makeConnector()
        connector.advance(by: 2)

        let usage = connector.currentUsage()
        XCTAssertEqual(usage?.used, MockScript.demo.steps[2].usageUsed)
        XCTAssertEqual(usage?.limit, MockScript.demo.usageLimit)
    }

    func testChatReturnsScriptedMessagesOldestFirst() {
        let script = MockScript.demo
        let connector = makeConnector()
        connector.advance(by: script.steps.count - 1)

        let expected = script.steps.compactMap(\.message)
        XCTAssertEqual(connector.recentMessages(limit: 50).map(\.text), expected)
        XCTAssertEqual(connector.recentMessages(limit: 2).map(\.text), Array(expected.suffix(2)))
        XCTAssertTrue(connector.recentMessages(limit: 0).isEmpty)
    }

    func testSimulatedErrorReportsReason() {
        let connector = makeConnector(state: .error)

        XCTAssertEqual(connector.connectionState, .error)
        XCTAssertNotNil(connector.lastError)
        connector.simulatedConnectionState = .connected
        XCTAssertNil(connector.lastError)
    }

    func testResetAndNegativeAdvanceNeverGoBelowZero() {
        let connector = makeConnector()
        connector.advance(by: 3)
        connector.reset()
        XCTAssertEqual(connector.tick, 0)

        connector.advance(by: -10)
        XCTAssertEqual(connector.tick, 0)
    }

    func testEmptyScriptFallsBackToSingleIdleStep() {
        let script = MockScript(steps: [])

        XCTAssertEqual(script.steps.count, 1)
        XCTAssertEqual(makeConnector(script).currentActivity?.kind, .note)
    }

    func testScriptEmptiedAfterInitPlaysIdleStep() {
        var script = MockScript.demo
        script.steps.removeAll()

        XCTAssertEqual(script.step(at: 0), MockScript.idleStep)
        XCTAssertEqual(script.step(at: -3), MockScript.idleStep)
        let connector = makeConnector(script)
        connector.advance(by: 5)
        XCTAssertEqual(connector.currentActivity?.title, MockScript.idleStep.title)
        XCTAssertTrue(connector.pendingApprovals().isEmpty)
        XCTAssertTrue(connector.recentMessages(limit: 10).isEmpty)
    }

    func testMockReportsNoAuthRequirement() {
        XCTAssertEqual(makeConnector().authStatus, .notRequired)
    }

    func testRegistryBuildsOnlyKnownConnectors() throws {
        let demo = try XCTUnwrap(ConnectorRegistry.makeConnector(id: .mockDemo, connectionState: .connecting))
        XCTAssertEqual(demo.id, .mockDemo)
        XCTAssertEqual(demo.connectionState, .connecting)
        XCTAssertNotNil(ConnectorRegistry.makeConnector(id: .mockQuiet, connectionState: .connected))
        XCTAssertNil(ConnectorRegistry.makeConnector(id: .disabled, connectionState: .connected))
        let unknown = ConnectorID(rawValue: "unknown")
        XCTAssertNil(ConnectorRegistry.makeConnector(id: unknown, connectionState: .connected))
    }

    func testRegistryOptionsAreUniqueAndIncludeDefault() {
        let ids = ConnectorRegistry.options.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertTrue(ids.contains(ConnectorRegistry.defaultID))
        XCTAssertTrue(ids.contains(.disabled))
    }
}
