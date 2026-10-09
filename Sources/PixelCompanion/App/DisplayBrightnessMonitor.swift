import Combine
import Foundation
import IOKit.graphics

/// Legacy public IOKit read-only display parameter API. Modern internal
/// displays and most external displays may not expose this key at all.
enum PublicDisplayBrightnessReader {
    static func read() -> Double? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault, IOServiceMatching("IODisplayConnect"), &iterator
        ) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }

        var count = 0
        var brightness: Double?
        while true {
            let service = IOIteratorNext(iterator)
            guard service != 0 else { break }
            defer { IOObjectRelease(service) }
            count += 1
            // No screen-to-service mapping is claimed. Multiple candidates
            // are ambiguous even when only one supports the parameter.
            guard count == 1 else { return nil }
            var scalar: Float = 0
            let key = CFStringCreateWithCString(
                nil, kIODisplayBrightnessKey, CFStringBuiltInEncodings.UTF8.rawValue
            )
            if IODisplayGetFloatParameter(service, 0, key, &scalar) == KERN_SUCCESS {
                brightness = Double(scalar)
            }
        }
        return DisplayBrightnessSelection.unambiguous(brightness, serviceCount: count)
    }
}

/// Never requests Screen Recording or Accessibility, never sets brightness,
/// and never stores per-device identifiers, names, or reading history.
@MainActor
final class DisplayBrightnessMonitor: ObservableObject {
    @Published private(set) var snapshot = DisplayBrightnessSnapshot.unavailable
    private let readBrightness: () -> Double?
    private var ticker: Timer?
    private(set) var enabled = false

    static let refreshInterval: TimeInterval = 15

    init(readBrightness: @escaping () -> Double? = PublicDisplayBrightnessReader.read) {
        self.readBrightness = readBrightness
    }

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
        let next = DisplayBrightnessSnapshot.validated(readBrightness())
        if snapshot != next { snapshot = next }
    }
}
