import Foundation
import PixelCompanionCore

/// Pure scheduling decision. Neither polling cadence nor a wake handler can
/// change connector permissions or trigger writes.
enum CompanionRefreshCadence {
    static let lowPowerPaperclipInterval: TimeInterval = 20

    static func interval(
        isMock: Bool,
        mockInterval: TimeInterval,
        paperclipInterval: TimeInterval,
        conserveEnergy: Bool,
        lowPowerMode: Bool
    ) -> TimeInterval {
        if isMock { return mockInterval }
        return conserveEnergy && lowPowerMode
            ? max(lowPowerPaperclipInterval, paperclipInterval)
            : paperclipInterval
    }
}
