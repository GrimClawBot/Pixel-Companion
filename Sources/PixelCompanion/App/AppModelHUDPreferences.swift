import Combine
import Foundation

extension AppModel {
    var musicWidgetEnabled: Bool {
        get { settings.musicWidgetEnabled }
        set {
            guard newValue != settings.musicWidgetEnabled else { return }
            objectWillChange.send()
            settings.musicWidgetEnabled = newValue
            musicMonitor.configure(enabled: newValue)
        }
    }

    var calendarWidgetEnabled: Bool {
        get { settings.calendarWidgetEnabled }
        set {
            guard newValue != settings.calendarWidgetEnabled else { return }
            objectWillChange.send()
            settings.calendarWidgetEnabled = newValue
            calendarMonitor.configure(enabled: newValue)
        }
    }

    var outputVolumeHUDEnabled: Bool {
        get { settings.outputVolumeHUDEnabled }
        set {
            guard newValue != settings.outputVolumeHUDEnabled else { return }
            objectWillChange.send()
            settings.outputVolumeHUDEnabled = newValue
            outputVolumeMonitor.configure(enabled: newValue)
        }
    }

    var batteryHUDEnabled: Bool {
        get { settings.batteryHUDEnabled }
        set {
            guard newValue != settings.batteryHUDEnabled else { return }
            objectWillChange.send()
            settings.batteryHUDEnabled = newValue
            batteryMonitor.configure(enabled: newValue)
        }
    }
}
