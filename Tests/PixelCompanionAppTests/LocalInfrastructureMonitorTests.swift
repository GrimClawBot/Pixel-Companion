import Foundation
@testable import PixelCompanion
import XCTest

private final class LockedReadAvailability: @unchecked Sendable {
    private let lock = NSLock()
    private var value = true

    func set(_ newValue: Bool) {
        lock.lock()
        value = newValue
        lock.unlock()
    }

    func get() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

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
        do {
            return try JSONSerialization.data(withJSONObject: [
                "schemaVersion": version, "hosts": rows
            ])
        } catch {
            XCTFail("Invalid JSON fixture: \(error)")
            return Data()
        }
    }

    private func parsed(_ rows: [[String: Any]]) -> LocalInfrastructureStatus {
        LocalInfrastructureParser.parse(data(rows), now: now)
    }

    private func waitFor(_ predicate: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<200 {
            if predicate() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for asynchronous infrastructure report", file: file, line: line)
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

    func testOptInLifecycleClearsLocalPathOnDisable() async {
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
        await waitFor {
            if case .loaded = monitor.status { return true }
            return false
        }
        guard case .loaded = monitor.status else { return XCTFail("Not loaded") }
        monitor.configure(enabled: false)
        XCTAssertFalse(monitor.isConnected)
        XCTAssertEqual(monitor.status, .disabled)
        monitor.configure(enabled: true)
        XCTAssertEqual(monitor.status, .unconnected)
        monitor.disconnect()
        XCTAssertEqual(monitor.status, .unconnected)
    }

    func testMissingSelectedFileImmediatelyInvalidatesLiveReport() async {
        let url = URL(fileURLWithPath: "/tmp/owner-selected-infra.json")
        let availability = LockedReadAvailability()
        let bytes = data([host()])
        let monitor = LocalInfrastructureMonitor(
            read: { _ in availability.get() ? bytes : nil }, now: { self.now }
        )
        monitor.configure(enabled: true)
        monitor.connect(url)
        await waitFor {
            if case .loaded = monitor.status { return true }
            return false
        }
        availability.set(false)
        monitor.refresh()
        await waitFor { monitor.status == .unavailable }
        XCTAssertEqual(monitor.status, .unavailable)
        monitor.disconnect()
    }

    func testSlowReportReadNeverBlocksMainActorOrRestoresOldFile() async {
        let first = URL(fileURLWithPath: "/tmp/owner-infrastructure-slow.json")
        let second = URL(fileURLWithPath: "/tmp/owner-infrastructure-current.json")
        let slowReadStarted = expectation(description: "background file read started")
        let slowReadGate = DispatchSemaphore(value: 0)
        defer { slowReadGate.signal() }
        let older = data([host(id: "old", cpu: 99)])
        let current = data([host(id: "current", cpu: 7)])
        let monitor = LocalInfrastructureMonitor(read: { file in
            if file == first {
                slowReadStarted.fulfill()
                slowReadGate.wait()
                return older
            }
            return file == second ? current : nil
        }, now: { self.now })

        monitor.configure(enabled: true)
        monitor.connect(first)
        // The main actor must still run while the old read remains blocked.
        await fulfillment(of: [slowReadStarted], timeout: 2)
        XCTAssertEqual(monitor.status, .unavailable)
        monitor.connect(second)
        await waitFor {
            if case let .loaded(hosts) = monitor.status {
                return hosts.count == 1 && hosts[0].id == "current" && hosts[0].cpuPercent == 7
            }
            return false
        }
        slowReadGate.signal()
        try? await Task.sleep(for: .milliseconds(60))
        if case let .loaded(hosts) = monitor.status {
            XCTAssertEqual(hosts.first?.id, "current")
        } else {
            XCTFail("Old source replaced the current report")
        }
        monitor.configure(enabled: false)
        XCTAssertEqual(monitor.status, .disabled)
    }

    func testDisplayedMetricsDisappearAtStaleBoundary() throws {
        guard case let .loaded(hosts) = parsed([host()]),
              let node = hosts.first else {
            return XCTFail("Expected fixture host")
        }
        let justBeforeLimit = now.addingTimeInterval(90)
        let beyondLimit = now.addingTimeInterval(91)
        let fresh = LocalInfrastructureHostDisplay(host: node, now: justBeforeLimit)
        XCTAssertTrue(fresh.isFresh)
        XCTAssertEqual(fresh.visibleMetrics?.cpuPercent, 42)
        XCTAssertEqual(fresh.visibleMetrics?.deployment?.state, .healthy)

        let stale = LocalInfrastructureHostDisplay(host: node, now: beyondLimit)
        XCTAssertFalse(stale.isFresh)
        XCTAssertNil(stale.visibleMetrics?.cpuPercent)
        XCTAssertNil(stale.visibleMetrics?.deployment)
        XCTAssertNil(stale.visibleMetrics)
    }
}
