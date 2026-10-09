import Combine
import Foundation
import IOKit.ps

/// Reads only Apple's public IOKit power-source API. No background daemon,
/// filesystem persistence, extra entitlements or network traffic.
@MainActor
final class BatteryPowerMonitor: ObservableObject {
    @Published private(set) var snapshot = BatteryPowerSnapshot.unavailable
    private var ticker: Timer?
    private(set) var enabled = false

    static let refreshInterval: TimeInterval = 30

    func configure(enabled newValue: Bool) {
        guard enabled != newValue else { return }
        enabled = newValue
        if newValue {
            refresh()
            let timer = Timer(timeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
            RunLoop.main.add(timer, forMode: .common)
            ticker = timer
        } else {
            ticker?.invalidate()
            ticker = nil
            snapshot = .unavailable
        }
    }

    func refresh() {
        guard enabled else { return }
        let info = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let sources = IOPSCopyPowerSourcesList(info).takeRetainedValue() as [AnyObject]
        let descriptions = sources.compactMap { source -> [String: Any]? in
            IOPSGetPowerSourceDescription(info, source)?
                .takeUnretainedValue() as? [String: Any]
        }
        let next = BatteryPowerSnapshot.reported(
            by: descriptions,
            lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled
        )
        if next != snapshot { snapshot = next }
    }
}
