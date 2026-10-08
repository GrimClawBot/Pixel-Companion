import Foundation
import PixelCompanionCore
@testable import PixelCompanion
import XCTest

final class DownloadProgressTests: XCTestCase {
    func testKnownBytesReportRealPercentageOnly() {
        XCTAssertEqual(
            DownloadProgressState.validated(.init(receivedBytes: 25, expectedBytes: 100)),
            .active(percent: 25)
        )
        XCTAssertEqual(
            DownloadProgressState.validated(.init(receivedBytes: 1, expectedBytes: 100)),
            .active(percent: 1)
        )
        XCTAssertEqual(
            DownloadProgressState.validated(.init(receivedBytes: 100, expectedBytes: 100)),
            .finished
        )
    }

    func testUnknownSizeDoesNotInventPercent() {
        XCTAssertEqual(
            DownloadProgressState.validated(.init(receivedBytes: 5, expectedBytes: nil)),
            .active(percent: nil)
        )
    }

    func testBadByteCountsNeverRenderProgress() {
        for report in [
            DownloadProgressReport(receivedBytes: -1, expectedBytes: 100),
            DownloadProgressReport(receivedBytes: 101, expectedBytes: 100),
            DownloadProgressReport(receivedBytes: 0, expectedBytes: 0),
            DownloadProgressReport(receivedBytes: 10, expectedBytes: -1)
        ] {
            XCTAssertEqual(.validated(report), .idle)
        }
    }

    func testMissingTransferIsIdleNotFabricated() {
        XCTAssertEqual(DownloadProgressState.validated(nil), .idle)
    }

    @MainActor
    func testNoSourceNeverStartsPollingOrInventsDownloads() {
        let monitor = DownloadProgressMonitor()
        monitor.configure(enabled: true)
        XCTAssertEqual(monitor.state, .noSource)
        monitor.refresh()
        XCTAssertEqual(monitor.state, .noSource)
        XCTAssertEqual(DownloadProgressMonitor.refreshInterval, 5)
        monitor.configure(enabled: false)
    }

    @MainActor
    func testRegisteredSourceRequiresOptInAndCleansUp() {
        let fake = FakeProgressSource(report: .init(receivedBytes: 5, expectedBytes: 10))
        let monitor = DownloadProgressMonitor()
        monitor.register(source: fake)
        XCTAssertEqual(fake.reads, 0)
        monitor.configure(enabled: true)
        XCTAssertEqual(fake.reads, 1)
        XCTAssertEqual(monitor.state, .active(percent: 50))
        monitor.configure(enabled: false)
        monitor.refresh()
        XCTAssertEqual(fake.reads, 1)
        XCTAssertEqual(monitor.state, .noSource)
    }

    @MainActor
    func testDisconnectClearsPreviousPrivateState() {
        let fake = FakeProgressSource(report: .init(receivedBytes: 60, expectedBytes: 100))
        let monitor = DownloadProgressMonitor()
        monitor.register(source: fake)
        monitor.configure(enabled: true)
        XCTAssertEqual(monitor.state, .active(percent: 60))
        monitor.register(source: nil)
        XCTAssertEqual(monitor.state, .noSource)
        monitor.configure(enabled: false)
    }

    func testDownloadHUDIsOffByDefaultAndResets() {
        let suite = "DownloadHUD-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SettingsStore(defaults: defaults)
        XCTAssertFalse(store.downloadHUDEnabled)
        store.downloadHUDEnabled = true
        XCTAssertTrue(SettingsStore(defaults: defaults).downloadHUDEnabled)
        XCTAssertFalse(store.outputVolumeHUDEnabled)
        XCTAssertFalse(store.displayBrightnessHUDEnabled)
        store.reset()
        XCTAssertFalse(store.downloadHUDEnabled)
    }
}

private final class FakeProgressSource: DownloadProgressSource {
    let report: DownloadProgressReport?
    private(set) var reads = 0

    init(report: DownloadProgressReport?) { self.report = report }

    func currentTransfer() -> DownloadProgressReport? {
        reads += 1
        return report
    }
}
