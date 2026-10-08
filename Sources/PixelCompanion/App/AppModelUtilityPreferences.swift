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
}
