import Foundation
import PixelCompanionCore
@testable import PixelCompanion
import XCTest

final class MusicNowPlayingTests: XCTestCase {
    func testPlayingSongMetadataIsPreservedOnlyFromValidFields() {
        let item = MusicNowPlayingSnapshot.validated(
            fields: ["playing", "Song", "Artist", "Album"]
        )
        XCTAssertEqual(item?.playback, .playing)
        XCTAssertEqual(item?.title, "Song")
        XCTAssertEqual(item?.artist, "Artist")
        XCTAssertEqual(item?.album, "Album")
    }

    func testStoppedPlayerClearsEvenPreviouslyReportedPrivateTrack() {
        let stopped = MusicNowPlayingSnapshot.validated(
            fields: ["stopped", "Old secret", "Private artist", "Private album"]
        )
        XCTAssertEqual(stopped?.playback, .stopped)
        XCTAssertNil(stopped?.title)
        XCTAssertNil(stopped?.artist)
        XCTAssertNil(stopped?.album)
    }

    func testMalformedOrUnknownScriptingResultDoesNotMakeUpState() {
        XCTAssertNil(MusicNowPlayingSnapshot.validated(fields: []))
        XCTAssertNil(MusicNowPlayingSnapshot.validated(fields: ["playing", "Track"]))
        XCTAssertNil(MusicNowPlayingSnapshot.validated(
            fields: ["unknown", "Track", "Artist", "Album"]
        ))
    }

    func testMissingAndVeryLongFieldsRemainPrivateAndBounded() {
        let paused = MusicNowPlayingSnapshot.validated(
            fields: ["paused", "  ", " ", String(repeating: "X", count: 500)]
        )
        XCTAssertEqual(paused?.playback, .paused)
        XCTAssertNil(paused?.title)
        XCTAssertNil(paused?.artist)
        XCTAssertEqual(paused?.album?.count, 160)
    }

    func testMetadataStripsControlCharactersAndDirectionalSpoofing() {
        let rawTitle = "Secret\nTrack\tName\u{202E}spoof\u{2066}"
        let item = MusicNowPlayingSnapshot.validated(
            fields: ["playing", rawTitle, "Artist\u{200F} Name", "Album"]
        )
        XCTAssertEqual(item?.title, "SecretTrackNamespoof")
        XCTAssertEqual(item?.artist, "Artist Name")
    }

    func testControlOnlyMetadataDoesNotProduceFakeTitle() {
        let item = MusicNowPlayingSnapshot.validated(
            fields: ["playing", "\n\r\t\u{202D}\u{2069}", "", ""]
        )
        XCTAssertNil(item?.title)
        XCTAssertEqual(item?.displayedTitle(showTitles: false), "Track details hidden")
        XCTAssertEqual(item?.displayedTitle(showTitles: true), "Track title not reported")
    }

    func testMetadataLengthBoundAppliesAfterRemovingUnsafeScalars() {
        let rawTitle = String(repeating: "\u{202E}", count: 200)
            + String(repeating: "Z", count: 200)
        let item = MusicNowPlayingSnapshot.validated(
            fields: ["playing", rawTitle, "", ""]
        )
        XCTAssertEqual(item?.title, String(repeating: "Z", count: 160))
    }

    func testTracksAreMaskedUntilUserSeparatelyEnablesDetails() {
        let item = MusicNowPlayingSnapshot.validated(
            fields: ["playing", "Private track", "Artist", "Album"]
        )!
        XCTAssertEqual(item.displayedTitle(showTitles: false), "Track details hidden")
        XCTAssertEqual(item.displayedTitle(showTitles: true), "Private track")
    }

    @MainActor
    func testPermissionAndMissingMusicErrorsAreClear() {
        XCTAssertTrue(MusicConnectionState.musicNotRunning.description.contains("not open"))
        XCTAssertTrue(MusicConnectionState.permissionUnavailable.description.contains("Automation"))
        XCTAssertTrue(MusicConnectionState.notConnected.description.contains("Connect"))
        XCTAssertEqual(MusicNowPlayingMonitor.refreshInterval, 30)
    }

    func testMusicSettingsOffAndPrivacyOffByDefault() {
        let suite = "MusicSettings-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let setting = SettingsStore(defaults: defaults)
        XCTAssertFalse(setting.musicWidgetEnabled)
        XCTAssertFalse(setting.musicShowTrackDetails)
        setting.musicWidgetEnabled = true
        XCTAssertTrue(SettingsStore(defaults: defaults).musicWidgetEnabled)
        XCTAssertFalse(SettingsStore(defaults: defaults).musicShowTrackDetails)
        XCTAssertFalse(setting.calendarWidgetEnabled)
        XCTAssertFalse(setting.focusTimerEnabled)
        XCTAssertFalse(setting.batteryHUDEnabled)
    }

    @MainActor
    func testEnableAndRefreshNeverSendAppleEventBeforeConnect() {
        let counter = MusicReadCounter()
        let monitor = MusicNowPlayingMonitor(
            musicIsRunning: { true },
            hasUsageDescription: { true },
            readTrack: { counter.increment(); return .denied }
        )
        monitor.configure(enabled: true)
        monitor.refresh()
        XCTAssertEqual(counter.count, 0)
        XCTAssertEqual(monitor.state, .notConnected)
        monitor.configure(enabled: false)
        monitor.refresh()
        XCTAssertEqual(counter.count, 0)
        XCTAssertEqual(monitor.state, .disabled)
    }

    @MainActor
    func testExplicitConnectDoesNotLaunchMusicIfItIsClosed() {
        let counter = MusicReadCounter()
        let monitor = MusicNowPlayingMonitor(
            musicIsRunning: { false },
            hasUsageDescription: { true },
            readTrack: { counter.increment(); return .denied }
        )
        monitor.configure(enabled: true)
        monitor.connect()
        XCTAssertEqual(monitor.state, .musicNotRunning)
        XCTAssertNil(monitor.snapshot)
        XCTAssertEqual(counter.count, 0)
    }

    @MainActor
    func testUnpackagedSwiftRunCannotRequestAppleEventPermission() {
        let counter = MusicReadCounter()
        let monitor = MusicNowPlayingMonitor(
            musicIsRunning: { true },
            hasUsageDescription: { false },
            readTrack: { counter.increment(); return .denied }
        )
        monitor.configure(enabled: true)
        monitor.connect()
        XCTAssertEqual(monitor.state, .permissionUnavailable)
        XCTAssertNil(monitor.snapshot)
        XCTAssertEqual(counter.count, 0)
    }
}

/// Uses a locked test-only counter instead of talking to a real Music app.
private final class MusicReadCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func increment() {
        lock.lock()
        value += 1
        lock.unlock()
    }
}
