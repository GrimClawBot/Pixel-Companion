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
