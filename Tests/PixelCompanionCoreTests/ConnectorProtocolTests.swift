import PixelCompanionCore
import XCTest

/// A connector that implements nothing beyond the required members.
private final class BareConnector: Connector {
    let id = ConnectorID(rawValue: "test.bare")
    let displayName = "Bare"
    var connectionState: ConnectionState = .connected
}

/// A connector that reports a failure reason even when it is not in `.error`.
private final class FlakyConnector: Connector, ActivitySource {
    let id = ConnectorID(rawValue: "test.flaky")
    let displayName = "Flaky"
    var connectionState: ConnectionState = .connected
    var lastError: String? { "stale failure" }
    var activity: (any ActivitySource)? { self }
    var currentActivity: ActivityEvent? { nil }
    private(set) var requestedLimit: Int?

    func recentActivity(limit: Int) -> [ActivityEvent] {
        requestedLimit = limit
        return []
    }
}

final class ConnectorProtocolTests: XCTestCase {
    func testBareConnectorGetsEmptyCapabilitiesFromDefaults() {
        let connector = BareConnector()

        XCTAssertNil(connector.lastError)
        XCTAssertNil(connector.auth)
        XCTAssertNil(connector.activity)
        XCTAssertNil(connector.approvals)
        XCTAssertNil(connector.usage)
        XCTAssertNil(connector.chat)
        connector.refresh()
    }

    func testSnapshotOfBareConnectorHasNoData() {
        let snapshot = ConnectorSnapshot(capturing: BareConnector())

        XCTAssertEqual(snapshot.connectorName, "Bare")
        XCTAssertEqual(snapshot.connectionState, .connected)
        XCTAssertEqual(snapshot.authStatus, .notRequired)
        XCTAssertNil(snapshot.currentActivity)
        XCTAssertTrue(snapshot.recentActivity.isEmpty)
        XCTAssertTrue(snapshot.pendingApprovals.isEmpty)
        XCTAssertNil(snapshot.usage)
        XCTAssertTrue(snapshot.recentMessages.isEmpty)
    }

    func testNilConnectorYieldsNoConnectorSnapshot() {
        let snapshot = ConnectorSnapshot(capturing: nil)

        XCTAssertEqual(snapshot, .noConnector)
        XCTAssertEqual(snapshot.connectionState, .disconnected)
    }

    func testLastErrorIsOnlyCapturedInErrorState() {
        let connector = FlakyConnector()
        XCTAssertNil(ConnectorSnapshot(capturing: connector).lastError)

        connector.connectionState = .error
        XCTAssertEqual(ConnectorSnapshot(capturing: connector).lastError, "stale failure")
    }

    func testNegativeLimitsAreClampedToZero() {
        let connector = FlakyConnector()
        _ = ConnectorSnapshot(capturing: connector, activityLimit: -3)

        XCTAssertEqual(connector.requestedLimit, 0)
    }

    func testUsageFraction() {
        func fraction(_ used: Int, of limit: Int?) -> Double? {
            UsageSnapshot(used: used, limit: limit, unit: "requests", periodLabel: "Today").fractionUsed
        }
        XCTAssertEqual(fraction(250, of: 1_000), 0.25)
        XCTAssertEqual(fraction(1_500, of: 1_000), 1)
        XCTAssertNil(fraction(10, of: nil))
        XCTAssertNil(fraction(10, of: 0))
    }
}
