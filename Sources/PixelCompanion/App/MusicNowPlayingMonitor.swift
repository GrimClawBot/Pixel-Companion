import AppKit
import Combine
import Foundation

enum AppleMusicReadResult: Sendable {
    case reported(MusicNowPlayingSnapshot)
    case denied
    case unavailable
}

/// Public Apple Events scripting of Apple Music's reported player state.
/// The only Apple Event emitted reads state and track text; it never tells
/// Music to play, pause, skip, launch, or change its library.
enum AppleMusicReadClient {
    static func readCurrentTrack() -> AppleMusicReadResult {
        let source = """
        tell application id "com.apple.Music"
            set playback to "stopped"
            if player state is playing then
                set playback to "playing"
            else if player state is paused then
                set playback to "paused"
            end if
            if playback is "stopped" then return {playback, "", "", ""}
            if not (exists current track) then return {playback, "", "", ""}
            set songTitle to name of current track as text
            set songArtist to artist of current track as text
            set songAlbum to album of current track as text
            return {playback, songTitle, songArtist, songAlbum}
        end tell
        """
        guard let script = NSAppleScript(source: source) else { return .unavailable }
        var details: NSDictionary?
        let descriptor = script.executeAndReturnError(&details)
        if let code = details?[NSAppleScript.errorNumber] as? Int,
           code == -1743 { return .denied }
        guard descriptor.numberOfItems == 4 else { return .unavailable }
        let fields = (1...4).compactMap { descriptor.atIndex($0)?.stringValue }
        guard let snapshot = MusicNowPlayingSnapshot.validated(fields: fields) else {
            return .unavailable
        }
        return .reported(snapshot)
    }
}

/// Opt-in Music.app-specific Now Playing source. Disabled means zero polling.
/// Enabling the widget does NOT send Apple Events; only explicit Connect does.
/// No active connection is restored across app launches.
@MainActor
final class MusicNowPlayingMonitor: ObservableObject {
    @Published private(set) var state: MusicConnectionState = .disabled
    @Published private(set) var snapshot: MusicNowPlayingSnapshot?

    private let musicIsRunning: () -> Bool
    private let hasUsageDescription: () -> Bool
    private let readTrack: @Sendable () -> AppleMusicReadResult

    init(
        musicIsRunning: @escaping () -> Bool = {
            !NSRunningApplication.runningApplications(
                withBundleIdentifier: "com.apple.Music"
            ).isEmpty
        },
        hasUsageDescription: @escaping () -> Bool = {
            Bundle.main.object(forInfoDictionaryKey: "NSAppleEventsUsageDescription") != nil
        },
        readTrack: @escaping @Sendable () -> AppleMusicReadResult = {
            AppleMusicReadClient.readCurrentTrack()
        }
    ) {
        self.musicIsRunning = musicIsRunning
        self.hasUsageDescription = hasUsageDescription
        self.readTrack = readTrack
    }

    private var timer: Timer?
    private var generation = 0
    private var fetching = false
    private var connectedThisLaunch = false
    private(set) var enabled = false

    static let refreshInterval: TimeInterval = 30

    func configure(enabled next: Bool) {
        guard enabled != next else { return }
        enabled = next
        generation += 1
        timer?.invalidate()
        timer = nil
        connectedThisLaunch = false
        fetching = false
        snapshot = nil
        state = next ? .notConnected : .disabled
    }

    /// Only called by the UI's user-triggered Connect button.
    func connect() {
        guard enabled, !fetching else { return }
        guard hasUsageDescription() else {
            state = .permissionUnavailable
            return
        }
        fetch(explicitConsent: true)
    }

    func refresh() {
        guard enabled, connectedThisLaunch, !fetching else { return }
        fetch(explicitConsent: false)
    }

    private func fetch(explicitConsent: Bool) {
        // NSRunningApplication does not launch Apple Music or send Apple Events.
        guard musicIsRunning() else {
            snapshot = nil
            state = .musicNotRunning
            return
        }

        fetching = true
        state = .connecting
        generation += 1
        let token = generation
        let readTrack = self.readTrack
        Task { [weak self] in
            let result = await Task.detached(priority: .utility) {
                readTrack()
            }.value
            guard let self, self.enabled, token == self.generation else { return }
            self.fetching = false
            switch result {
            case let .reported(value):
                self.connectedThisLaunch = true
                self.snapshot = value
                switch value.playback {
                case .playing: self.state = .playing
                case .paused: self.state = .paused
                case .stopped: self.state = .stopped
                }
                self.startTimerIfNeeded()
            case .denied:
                self.connectedThisLaunch = false
                self.snapshot = nil
                self.state = .permissionUnavailable
                self.stopTimer()
            case .unavailable:
                self.snapshot = nil
                self.state = .failed
                if explicitConsent { self.connectedThisLaunch = false }
                if !self.connectedThisLaunch { self.stopTimer() }
            }
        }
    }

    private func startTimerIfNeeded() {
        guard timer == nil else { return }
        let tick = Timer(timeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        RunLoop.main.add(tick, forMode: .common)
        timer = tick
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}
