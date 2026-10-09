import Foundation
import XCTest

/// Thread-safe injected reader: no real user files, accounts or provider settings.
final class LockedLocalReportReader: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Data?
    private var paths: [URL] = []

    init(_ result: Data? = nil) { self.result = result }

    func read(_ path: URL) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        paths.append(path)
        return result
    }

    func set(_ data: Data?) {
        lock.lock()
        result = data
        lock.unlock()
    }

    var calls: Int {
        lock.lock()
        defer { lock.unlock() }
        return paths.count
    }

    var lastPath: URL? {
        lock.lock()
        defer { lock.unlock() }
        return paths.last
    }
}

@MainActor
func awaitLocalReport(
    _ message: String = "Asynchronous report not delivered",
    condition: () -> Bool,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    for _ in 0..<200 {
        if condition() { return }
        try? await Task.sleep(for: .milliseconds(10))
    }
    XCTFail(message, file: file, line: line)
}

/// Simulates the initial read arriving after the user has pressed Start Check.
final class DelayedBaselineReader: @unchecked Sendable {
    private let lock = NSLock()
    private let gate = DispatchSemaphore(value: 0)
    private var payload: Data
    private var firstRead = true
    private var firstStarted = false

    init(_ payload: Data) { self.payload = payload }

    var started: Bool {
        lock.lock()
        defer { lock.unlock() }
        return firstStarted
    }

    func set(_ data: Data) {
        lock.lock()
        payload = data
        lock.unlock()
    }

    func release() { gate.signal() }

    func read(_ file: URL) -> Data? {
        lock.lock()
        let wait = firstRead
        if firstRead {
            firstRead = false
            firstStarted = true
        }
        lock.unlock()
        if wait { gate.wait() }
        lock.lock()
        defer { lock.unlock() }
        return payload
    }
}
