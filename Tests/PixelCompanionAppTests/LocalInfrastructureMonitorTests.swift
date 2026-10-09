import Foundation
@testable import PixelCompanion
import XCTest

@MainActor
final class LocalInfrastructureMonitorTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-10-09T12:00:00Z")!

    private func host(
        id: String = "node-1",
        time: String = "2026-10-09T11:59:30Z",
        cpu: Double? = 42
    ) -> [String: Any] {
        var row: [String: Any] = [
            "id": id, "name": "Node A", "observedAt": time,
            "memoryUsedBytes": 4_000, "memoryTotalBytes": 8_000,
            "diskUsedBytes": 100, "diskTotalBytes": 200,
            "temperatureCelsius": 46.2, "receiveBytesPerSecond": 500,
            "transmitBytesPerSecond": 300,
            "deployment": ["name": "app", "state": "healthy"]
        ]
        if let cpu { row["cpuPercent"] = cpu }
        return row
    }

    private func data(_ rows: [[String: Any]], version: Int = 1) -> Data {
        try! JSONSerialization.data(withJSONObject: [
            "schemaVersion": version, "hosts": rows
        ])
    }

    private func parsed(_ rows: [[String: Any]]) -> LocalInfrastructureStatus {
        LocalInfrastructureParser.parse(data(rows), now: now)
    }

    func testFreshMetricsAndDeploymentAreReportedOnly() throws {
        guard case let .loaded(hosts) = parsed([host()]) else {
            return XCTFail("Expected live bounded host report")
        }
        let node = try XCTUnwrap(hosts.first)
        XCTAssertEqual(hosts.count, 1)
        XCTAssertEqual(node.id, "node-1")
        XCTAssertTrue(node.isFresh(at: now))
        XCTAssertEqual(node.cpuPercent, 42)
        XCTAssertEqual(node.memoryFraction, 0.5)
        XCTAssertEqual(node.diskFraction, 0.5)
        XCTAssertEqual(node.temperatureCelsius, 46.2)
        XCTAssertEqual(node.receiveBytesPerSecond, 500)
        XCTAssertEqual(node.deployment?.state, .healthy)
    }

    func testOldTimestampNeverBecomesFreshMetrics() throws {
        guard case let .loaded(hosts) = parsed([
            host(time: "2026-10-09T11:55:00Z")
        ]) else { return XCTFail("Historical report should parse") }
        XCTAssertFalse(try XCTUnwrap(hosts.first).isFresh(at: now))
        XCTAssertEqual(hosts.first?.cpuPercent, 42)
    }

    func testTooFarFutureTimestampAndInvalidDatesFailClosed() {
        XCTAssertEqual(parsed([host(time: "2026-10-09T12:01:00Z")]), .unavailable)
        XCTAssertEqual(parsed([host(time: "not-a-time")]), .unavailable)
        XCTAssertEqual(parsed([host(time: "2027-01-01T00:00:00Z")]), .unavailable)
    }

    func testInvalidMetricsAndIncompleteCapacityAreUnavailable() {
        XCTAssertEqual(parsed([host(cpu: -1)]), .unavailable)
        XCTAssertEqual(parsed([host(cpu: 101)]), .unavailable)
        var row = host()
        row["memoryUsedBytes"] = 9_000
        XCTAssertEqual(parsed([row]), .unavailable)
        row = host()
        row.removeValue(forKey: "diskTotalBytes")
        XCTAssertEqual(parsed([row]), .unavailable)
        row = host()
        row["diskTotalBytes"] = 0
        XCTAssertEqual(parsed([row]), .unavailable)
        row = host()
        row["temperatureCelsius"] = 900
        XCTAssertEqual(parsed([row]), .unavailable)
        row = host()
        row["receiveBytesPerSecond"] = -5
        XCTAssertEqual(parsed([row]), .unavailable)
    }

    func testDuplicateSourceIDsAndOversizedFeedFailClosed() {
        XCTAssertEqual(parsed([host(), host()]), .unavailable)
        XCTAssertEqual(parsed((0..<9).map { host(id: "node-\($0)") }), .unavailable)
        XCTAssertEqual(
            LocalInfrastructureParser.parse(Data(repeating: 65, count: 65_537), now: now),
            .unavailable
        )
        XCTAssertEqual(LocalInfrastructureParser.parse(Data(), now: now), .unavailable)
        XCTAssertEqual(
            LocalInfrastructureParser.parse(data([host()], version: 2), now: now),
            .unavailable
        )
    }

    func testEmptyReportDoesNotImplyHealthyHost() {
        XCTAssertEqual(parsed([]), .empty)
        var minimal = host()
        ["cpuPercent", "memoryUsedBytes", "memoryTotalBytes", "diskUsedBytes",
         "diskTotalBytes", "temperatureCelsius", "receiveBytesPerSecond",
         "transmitBytesPerSecond", "deployment"].forEach { minimal.removeValue(forKey: $0) }
        guard case let .loaded(hosts) = parsed([minimal]) else {
            return XCTFail("Missing optional values should be allowed")
        }
        XCTAssertNil(hosts.first?.memoryFraction)
        XCTAssertNil(hosts.first?.cpuPercent)
        XCTAssertNil(hosts.first?.deployment)
    }

    func testBidiNamesSanitizedAndBadIDsRejected() throws {
        var row = host()
        row["name"] = "Node\u{202E} A\u{2066}"
        row["deployment"] = ["name": "service\u{202E}", "state": "degraded"]
        guard case let .loaded(hosts) = parsed([row]) else {
            return XCTFail("Safe display name should parse")
        }
        XCTAssertEqual(hosts.first?.name, "Node A")
        XCTAssertEqual(hosts.first?.deployment?.name, "service")
        XCTAssertEqual(hosts.first?.deployment?.state, .degraded)
        XCTAssertEqual(parsed([host(id: "foo/bar")]), .unavailable)
        XCTAssertEqual(parsed([host(id: "")]), .unavailable)
    }

    func testMalformedDeploymentAndNegativeBytesCannotAppearHealthy() {
        var row = host()
        row["deployment"] = ["name": "service", "state": "great"]
        XCTAssertEqual(parsed([row]), .unavailable)
        row = host()
        row["memoryUsedBytes"] = -5
        XCTAssertEqual(parsed([row]), .unavailable)
    }

    func testOptInLifecycleClearsLocalPathOnDisable() {
        let url = URL(fileURLWithPath: "/tmp/owner-selected-infra.json")
        let bytes = data([host()])
        let monitor = LocalInfrastructureMonitor(read: { file in
            file == url ? bytes : nil
        }, now: { self.now })
        XCTAssertEqual(monitor.status, .disabled)
        monitor.connect(url)
        XCTAssertEqual(monitor.status, .disabled)
        monitor.configure(enabled: true)
        XCTAssertEqual(monitor.status, .unconnected)
        monitor.connect(url)
        XCTAssertTrue(monitor.isConnected)
        guard case .loaded = monitor.status else { return XCTFail("Not loaded") }
        monitor.configure(enabled: false)
        XCTAssertFalse(monitor.isConnected)
        XCTAssertEqual(monitor.status, .disabled)
        monitor.configure(enabled: true)
        XCTAssertEqual(monitor.status, .unconnected)
        monitor.disconnect()
        XCTAssertEqual(monitor.status, .unconnected)
    }

    func testMissingSelectedFileImmediatelyInvalidatesLiveReport() {
        let url = URL(fileURLWithPath: "/tmp/owner-selected-infra.json")
        var available = true
        let bytes = data([host()])
        let monitor = LocalInfrastructureMonitor(
            read: { _ in available ? bytes : nil }, now: { self.now }
        )
        monitor.configure(enabled: true)
        monitor.connect(url)
        guard case .loaded = monitor.status else { return XCTFail("Not loaded") }
        available = false
        monitor.refresh()
        XCTAssertEqual(monitor.status, .unavailable)
        monitor.disconnect()
    }
}
