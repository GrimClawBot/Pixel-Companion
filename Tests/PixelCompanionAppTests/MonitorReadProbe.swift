import Foundation
import XCTest

/// Thread-safe test-only reader for the three off-main local monitor transports.
final class MonitorReadProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var bytes: Data?
    private var observedURLs: [URL] = []
    private let waitGate: DispatchSemaphore?
    private let started: XCTestExpectation?

    init(bytes: Data?, waitGate: DispatchSemaphore? = nil, started: XCTestExpectation? = nil) {
        self.bytes = bytes
        self.waitGate = waitGate
        self.started = started
    }

    func read(_ url: URL) -> Data? {
        lock.lock()
        observedURLs.append(url)
        let payload = bytes
        lock.unlock()
        started?.fulfill()
        waitGate?.wait()
        return payload
    }

    func setBytes(_ newValue: Data?) {
        lock.lock()
        bytes = newValue
        lock.unlock()
    }

    var URLs: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return observedURLs
    }

    var count: Int { URLs.count }
}

@MainActor
func waitForMonitorStatus(
    file: StaticString = #filePath, line: UInt = #line,
    _ matches: () -> Bool
) async {
    for _ in 0..<200 {
        if matches() { return }
        try? await Task.sleep(for: .milliseconds(10))
    }
    XCTFail("Timed out waiting for background monitor report", file: file, line: line)
}
