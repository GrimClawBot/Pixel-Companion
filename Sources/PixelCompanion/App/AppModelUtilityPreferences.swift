import Combine
import PixelCompanionCore

/// Small nonsecret standalone utility preferences isolated from connector code.
extension AppModel {
    var musicShowTrackDetails: Bool {
        get { settings.musicShowTrackDetails }
        set {
            guard newValue != settings.musicShowTrackDetails else { return }
            objectWillChange.send()
            settings.musicShowTrackDetails = newValue
        }
    }

    var calendarShowTitles: Bool {
        get { settings.calendarShowTitles }
        set {
            guard newValue != settings.calendarShowTitles else { return }
            objectWillChange.send()
            settings.calendarShowTitles = newValue
        }
    }

    var displayBrightnessHUDEnabled: Bool {
        get { settings.displayBrightnessHUDEnabled }
        set {
            guard newValue != settings.displayBrightnessHUDEnabled else { return }
            objectWillChange.send()
            settings.displayBrightnessHUDEnabled = newValue
            displayBrightnessMonitor.configure(enabled: newValue)
        }
    }

    var downloadHUDEnabled: Bool {
        get { settings.downloadHUDEnabled }
        set {
            guard newValue != settings.downloadHUDEnabled else { return }
            objectWillChange.send()
            settings.downloadHUDEnabled = newValue
            downloadMonitor.configure(enabled: newValue)
        }
    }
    var fileShelfEnabled: Bool {
        get { settings.fileShelfEnabled }
        set {
            guard newValue != settings.fileShelfEnabled else { return }
            objectWillChange.send()
            settings.fileShelfEnabled = newValue
            fileShelf.configure(enabled: newValue)
        }
    }
    var clipboardHistoryEnabled: Bool {
        get { settings.clipboardHistoryEnabled }
        set {
            guard newValue != settings.clipboardHistoryEnabled else { return }
            objectWillChange.send()
            settings.clipboardHistoryEnabled = newValue
            clipboardHistory.configure(enabled: newValue)
        }
    }
    var localAgentFeedEnabled: Bool {
        get { settings.localAgentFeedEnabled }
        set {
            guard newValue != settings.localAgentFeedEnabled else { return }
            objectWillChange.send()
            settings.localAgentFeedEnabled = newValue
            localAgentFeed.configure(enabled: newValue)
        }
    }
    var codexPresenceEnabled: Bool {
        get { settings.codexPresenceEnabled }
        set {
            guard newValue != settings.codexPresenceEnabled else { return }
            objectWillChange.send()
            settings.codexPresenceEnabled = newValue
            codexProcessMonitor.configure(enabled: newValue)
        }
    }
    var codexTurnEventsEnabled: Bool {
        get { settings.codexTurnEventsEnabled }
        set {
            guard newValue != settings.codexTurnEventsEnabled else { return }
            objectWillChange.send()
            settings.codexTurnEventsEnabled = newValue
            codexTurnMonitor.configure(enabled: newValue)
        }
    }
    var claudeHookEventsEnabled: Bool {
        get { settings.claudeHookEventsEnabled }
        set {
            guard newValue != settings.claudeHookEventsEnabled else { return }
            objectWillChange.send()
            settings.claudeHookEventsEnabled = newValue
            claudeHookMonitor.configure(enabled: newValue)
        }
    }
    var focusTimerEnabled: Bool {
        get { settings.focusTimerEnabled }
        set {
            guard newValue != settings.focusTimerEnabled else { return }
            objectWillChange.send()
            settings.focusTimerEnabled = newValue
            if !newValue { focusTimer.stop() }
        }
    }
}
